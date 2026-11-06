import Foundation

public struct ImportError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Minimal RFC 4180 parser: quoted fields, escaped quotes (`""`), and newlines inside quotes.
/// Iterates Unicode scalars because Swift treats "\r\n" as a single Character.
public enum CsvParser {
    public static func parse(_ input: String, delimiter: Character = ",") -> [[String]] {
        let delim = delimiter.unicodeScalars.first!
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var fieldStarted = false

        func endField() {
            row.append(String(field))
            field = String.UnicodeScalarView()
            fieldStarted = false
        }

        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        var scalars = Array(input.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < scalars.count && scalars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    if !fieldStarted && field.isEmpty { inQuotes = true } else { field.append(c) }
                case delim:
                    endField()
                case "\r":
                    if i + 1 < scalars.count && scalars[i + 1] == "\n" { i += 1 }
                    endRow()
                case "\n":
                    endRow()
                default:
                    field.append(c)
                    fieldStarted = true
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    /// Parses with the first row as header; each record maps header name to value (blank values dropped).
    public static func parseRecords(_ input: String, delimiter: Character = ",") -> [[String: String]] {
        recordsFromRows(parse(input, delimiter: delimiter))
    }

    /// Header-mapped records from already-parsed rows (CSV, TSV, spreadsheet, …).
    public static func recordsFromRows(_ rows: [[String]]) -> [[String: String]] {
        guard let first = rows.first else { return [] }
        let header = first.map(\.trimmed)
        return rows.dropFirst()
            .filter { $0.contains { !$0.isBlank } }
            .map { values in
                var record: [String: String] = [:]
                for (index, name) in header.enumerated() {
                    let value = values[safe: index]
                    if !name.isEmpty, let value, !value.isBlank {
                        record[name] = value.trimmed
                    }
                }
                return record
            }
    }
}

/// Reads tabular exports regardless of container: CSV, TSV, XLSX (zip + XML), Excel 2003
/// SpreadsheetML and HTML-table .xls files. Detection is by content, not file name.
public enum SpreadsheetReader {
    public static func parseRecords(_ data: Data) throws -> [[String: String]] {
        CsvParser.recordsFromRows(try parseRows(data))
    }

    public static func parseRows(_ data: Data) throws -> [[String]] {
        let bytes = [UInt8](data)
        if bytes.isEmpty { return [] }
        if bytes.count >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B {
            return try XlsxParser.parseRows(bytes)
        }
        if bytes.count >= 4 && bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0 {
            throw ImportError("This is a legacy binary .xls file, which isn't supported. Open it in Excel or Google Sheets and re-export/save as .xlsx or .csv, then import that file.")
        }
        let text = decodeText(bytes)
        let trimmed = String(text.unicodeScalars.drop { ["\u{FEFF}", " ", "\t", "\r", "\n"].contains($0) })
        if trimmed.hasPrefix("<?xml") && trimmed.contains("Workbook") {
            return try SpreadsheetMlParser.parseRows(text)
        }
        let lower = trimmed.lowercased()
        if trimmed.hasPrefix("<") && (lower.contains("<table") || lower.contains("<tr")) {
            return HtmlTableParser.parseRows(text)
        }
        let firstLine = String(String.UnicodeScalarView(text.unicodeScalars.prefix { $0 != "\n" && $0 != "\r" }))
        let tabs = firstLine.unicodeScalars.filter { $0 == "\t" }.count
        let commas = firstLine.unicodeScalars.filter { $0 == "," }.count
        return CsvParser.parse(text, delimiter: tabs > commas ? "\t" : ",")
    }

    private static func decodeText(_ bytes: [UInt8]) -> String {
        if bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE {
            return String(data: Data(bytes), encoding: .utf16LittleEndian).map { $0.hasPrefix("\u{FEFF}") ? String($0.dropFirst()) : $0 } ?? ""
        }
        if bytes.count >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF {
            return String(data: Data(bytes), encoding: .utf16BigEndian).map { $0.hasPrefix("\u{FEFF}") ? String($0.dropFirst()) : $0 } ?? ""
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// Minimal XLSX reader: first worksheet + shared strings.
enum XlsxParser {
    static func parseRows(_ bytes: [UInt8]) throws -> [[String]] {
        let entries = try ZipReader.entries(bytes)

        let sharedStrings: [String] = try entries["xl/sharedStrings.xml"].map { xml in
            try XmlNode.parse(xml).descendants("si").map { $0.textOfDescendants("t") }
        } ?? []

        guard let sheetXml = findFirstSheet(entries) else { return [] }
        let doc = try XmlNode.parse(sheetXml)
        return doc.descendants("row").map { rowEl in
            var values: [Int: String] = [:]
            var maxCol = -1
            for cell in rowEl.descendants("c") {
                let col = columnIndex(cell.attributes["r"])
                if col < 0 { continue }
                values[col] = cellValue(cell, sharedStrings)
                maxCol = max(maxCol, col)
            }
            return maxCol < 0 ? [] : (0...maxCol).map { values[$0] ?? "" }
        }
    }

    private static func findFirstSheet(_ entries: [String: [UInt8]]) -> [UInt8]? {
        if let workbook = entries["xl/workbook.xml"], let rels = entries["xl/_rels/workbook.xml.rels"],
           let wb = try? XmlNode.parse(workbook), let relDoc = try? XmlNode.parse(rels),
           let sheet = wb.descendants("sheet").first {
            let relId = sheet.attributes["r:id"] ?? ""
            if let rel = relDoc.descendants("Relationship").first(where: { $0.attributes["Id"] == relId }) {
                let target = rel.attributes["Target"] ?? ""
                let path: String
                if target.hasPrefix("/") {
                    path = String(target.drop { $0 == "/" })
                } else if target.hasPrefix("xl/") {
                    path = target
                } else {
                    path = "xl/\(target)"
                }
                if let data = entries[path] { return data }
            }
        }
        return entries.keys
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted()
            .first
            .flatMap { entries[$0] }
    }

    private static func columnIndex(_ ref: String?) -> Int {
        guard let ref, !ref.isBlank else { return -1 }
        var col = 0
        var seen = false
        for ch in ref.uppercased().unicodeScalars {
            guard ch.value >= 65 && ch.value <= 90 else { break }
            seen = true
            col = col * 26 + Int(ch.value - 65 + 1)
        }
        return seen ? col - 1 : -1
    }

    private static func cellValue(_ cell: XmlNode, _ sharedStrings: [String]) -> String {
        switch cell.attributes["t"] {
        case "s":
            guard let index = Int(cell.textOfDescendants("v").trimmed) else { return "" }
            return sharedStrings[safe: index] ?? ""
        case "inlineStr":
            return cell.textOfDescendants("t")
        default:
            return cell.textOfDescendants("v")
        }
    }
}

/// Excel 2003 XML Spreadsheet (.xls saved as XML).
enum SpreadsheetMlParser {
    static func parseRows(_ text: String) throws -> [[String]] {
        let doc = try XmlNode.parse(Array(text.utf8))
        return doc.descendants("Row").map { row in
            row.descendants("Cell").map { cell in cell.descendants("Data").first?.textContent ?? "" }
        }
    }
}

/// .xls files that are really an HTML table (a common export trick).
enum HtmlTableParser {
    private static let rowRegex = try! NSRegularExpression(pattern: "<tr[^>]*>(.*?)</tr>", options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let cellRegex = try! NSRegularExpression(pattern: "<t[dh][^>]*>(.*?)</t[dh]>", options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let tagRegex = try! NSRegularExpression(pattern: "<[^>]+>")

    static func parseRows(_ text: String) -> [[String]] {
        let ns = text as NSString
        return rowRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { row in
            let inner = ns.substring(with: row.range(at: 1))
            let innerNs = inner as NSString
            return cellRegex.matches(in: inner, range: NSRange(location: 0, length: innerNs.length)).map { cell in
                let raw = innerNs.substring(with: cell.range(at: 1))
                let stripped = tagRegex.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: (raw as NSString).length), withTemplate: "")
                return unescape(stripped).trimmed
            }
        }
    }

    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// Kotlin-style lenient long parsing: "1790896458000", "1790896458000.0", "3600.0".
public extension String {
    func toLongFlexible() -> Int64? {
        let t = trimmed
        if let v = Int64(t) { return v }
        if let d = Double(t), d.isFinite, abs(d) < 9.2e18 { return Int64(d) }
        return nil
    }
}
