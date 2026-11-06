import Compression
import Foundation

/// Reads stored and deflated entries of a zip archive via its central directory, falling back to a
/// sequential scan of local headers when the directory is missing.
enum ZipReader {
    static func entries(_ bytes: [UInt8]) throws -> [String: [UInt8]] {
        if let central = try? centralDirectoryEntries(bytes), !central.isEmpty { return central }
        return try localEntries(bytes)
    }

    private static func u16(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ o: Int) -> Int { u16(b, o) | u16(b, o + 2) << 16 }

    private static func centralDirectoryEntries(_ b: [UInt8]) throws -> [String: [UInt8]] {
        guard b.count >= 22 else { throw ImportError("Not a valid zip file.") }
        var eocd = -1
        var i = b.count - 22
        let floor = max(0, b.count - 22 - 65_535)
        while i >= floor {
            if b[i] == 0x50 && b[i + 1] == 0x4B && b[i + 2] == 0x05 && b[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ImportError("Not a valid zip file.") }
        let count = u16(b, eocd + 10)
        var p = u32(b, eocd + 16)
        var out: [String: [UInt8]] = [:]
        for _ in 0..<count {
            guard p + 46 <= b.count, u32(b, p) == 0x0201_4B50 else { break }
            let method = u16(b, p + 10)
            let compressedSize = u32(b, p + 20)
            let size = u32(b, p + 24)
            let nameLen = u16(b, p + 28)
            let extraLen = u16(b, p + 30)
            let commentLen = u16(b, p + 32)
            let localOffset = u32(b, p + 42)
            let name = String(decoding: b[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            p += 46 + nameLen + extraLen + commentLen

            guard localOffset + 30 <= b.count, u32(b, localOffset) == 0x0403_4B50 else { continue }
            let dataStart = localOffset + 30 + u16(b, localOffset + 26) + u16(b, localOffset + 28)
            guard dataStart + compressedSize <= b.count, !name.hasSuffix("/") else { continue }
            out[name] = try decode(Array(b[dataStart..<(dataStart + compressedSize)]), method: method, size: size)
        }
        return out
    }

    private static func localEntries(_ b: [UInt8]) throws -> [String: [UInt8]] {
        var out: [String: [UInt8]] = [:]
        var p = 0
        while p + 30 <= b.count, u32(b, p) == 0x0403_4B50 {
            let flags = u16(b, p + 6)
            let method = u16(b, p + 8)
            let compressedSize = u32(b, p + 18)
            let size = u32(b, p + 22)
            let nameLen = u16(b, p + 26)
            let extraLen = u16(b, p + 28)
            let name = String(decoding: b[(p + 30)..<(p + 30 + nameLen)], as: UTF8.self)
            let dataStart = p + 30 + nameLen + extraLen
            if flags & 0x08 != 0 { throw ImportError("Unsupported zip layout.") }
            guard dataStart + compressedSize <= b.count else { break }
            if !name.hasSuffix("/") {
                out[name] = try decode(Array(b[dataStart..<(dataStart + compressedSize)]), method: method, size: size)
            }
            p = dataStart + compressedSize
        }
        return out
    }

    private static func decode(_ data: [UInt8], method: Int, size: Int) throws -> [UInt8] {
        switch method {
        case 0: return data
        case 8: return try inflate(data, expectedSize: size)
        default: throw ImportError("Unsupported zip compression method \(method).")
        }
    }

    /// Raw DEFLATE (zip method 8) via Compression's ZLIB algorithm, which is headerless.
    static func inflate(_ data: [UInt8], expectedSize: Int) throws -> [UInt8] {
        if data.isEmpty { return [] }
        var capacity = max(expectedSize, data.count * 4, 1024)
        while true {
            var out = [UInt8](repeating: 0, count: capacity)
            let written = data.withUnsafeBufferPointer { src in
                out.withUnsafeMutableBufferPointer { dst in
                    compression_decode_buffer(dst.baseAddress!, capacity, src.baseAddress!, data.count, nil, COMPRESSION_ZLIB)
                }
            }
            if written == 0 { throw ImportError("Couldn't decompress the spreadsheet.") }
            if written < capacity || expectedSize == written {
                return Array(out.prefix(written))
            }
            capacity *= 2
        }
    }
}

/// Tiny DOM built with XMLParser. Element names are qualified ("x:Row"); lookups match local names.
final class XmlNode {
    let name: String
    var attributes: [String: String]
    var children: [XmlNode] = []
    var text = ""
    weak var parent: XmlNode?

    init(name: String, attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
    }

    var localName: String { name.split(separator: ":").last.map(String.init) ?? name }

    var textContent: String {
        // Text is stored on nodes in document order as interleaved "#text" children.
        children.reduce(into: "") { acc, child in acc += child.name == "#text" ? child.text : child.textContent }
    }

    /// All descendant elements with the given local name, in document order.
    func descendants(_ local: String) -> [XmlNode] {
        var out: [XmlNode] = []
        func walk(_ node: XmlNode) {
            for child in node.children where child.name != "#text" {
                if child.localName == local { out.append(child) }
                walk(child)
            }
        }
        walk(self)
        return out
    }

    func textOfDescendants(_ local: String) -> String {
        descendants(local).map(\.textContent).joined()
    }

    static func parse(_ bytes: [UInt8]) throws -> XmlNode {
        let builder = Builder()
        let parser = XMLParser(data: Data(bytes))
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        guard parser.parse() else {
            throw ImportError("Couldn't read the spreadsheet: \(parser.parserError?.localizedDescription ?? "invalid XML")")
        }
        return builder.root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        let root = XmlNode(name: "#document")
        lazy var current: XmlNode = root

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let node = XmlNode(name: qName ?? elementName, attributes: attributeDict)
            node.parent = current
            current.children.append(node)
            current = node
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            current = current.parent ?? root
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            appendText(string)
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            appendText(String(decoding: CDATABlock, as: UTF8.self))
        }

        private func appendText(_ s: String) {
            if let last = current.children.last, last.name == "#text" {
                last.text += s
            } else {
                let t = XmlNode(name: "#text")
                t.text = s
                current.children.append(t)
            }
        }
    }
}
