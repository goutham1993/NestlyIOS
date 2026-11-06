import CryptoKit
import Foundation

public func newUUID() -> String { UUID().uuidString.lowercased() }

/// Java `UUID.nameUUIDFromBytes`: MD5 of the bytes, stamped as version 3 / IETF variant.
public func nameUUIDFromBytes(_ bytes: [UInt8]) -> String {
    var b = Array(Insecure.MD5.hash(data: bytes))
    b[6] = (b[6] & 0x0F) | 0x30
    b[8] = (b[8] & 0x3F) | 0x80
    let hex = b.map { String(format: "%02x", $0) }.joined()
    let chars = Array(hex)
    return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(chars[$0]) }.joined(separator: "-")
}

/// Java `String.hashCode()` over UTF-16 code units.
public func javaHashCode(_ s: String) -> Int32 {
    var h: Int32 = 0
    for unit in s.utf16 { h = h &* 31 &+ Int32(unit) }
    return h
}

/// Kotlin/Java `Math.round` (ties toward positive infinity).
public func kRound(_ x: Double) -> Int64 { Int64((x + 0.5).rounded(.down)) }

public extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var nilIfBlank: String? { isBlank ? nil : self }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedNilIfEmpty: String? { let t = trimmed; return t.isEmpty ? nil : t }
}

public extension Optional where Wrapped == String {
    var isNullOrBlank: Bool { self?.isBlank ?? true }
    var orEmpty: String { self ?? "" }
}

public extension Sequence {
    /// Stable sort by a comparable key (Kotlin `sortedBy`).
    func sortedStable<K: Comparable>(by key: (Element) -> K) -> [Element] {
        enumerated().sorted { a, b in
            let ka = key(a.element), kb = key(b.element)
            return ka == kb ? a.offset < b.offset : ka < kb
        }.map(\.element)
    }

    /// Stable descending sort (Kotlin `sortedByDescending`).
    func sortedStableDescending<K: Comparable>(by key: (Element) -> K) -> [Element] {
        enumerated().sorted { a, b in
            let ka = key(a.element), kb = key(b.element)
            return ka == kb ? a.offset < b.offset : ka > kb
        }.map(\.element)
    }

    /// Kotlin `groupBy`: keys in first-seen order.
    func groupedOrdered<K: Hashable>(by key: (Element) -> K) -> [(key: K, values: [Element])] {
        var order: [K] = []
        var map: [K: [Element]] = [:]
        for e in self {
            let k = key(e)
            if map[k] == nil { order.append(k) }
            map[k, default: []].append(e)
        }
        return order.map { ($0, map[$0]!) }
    }

    func distinctBy<K: Hashable>(_ key: (Element) -> K) -> [Element] {
        var seen = Set<K>()
        return filter { seen.insert(key($0)).inserted }
    }
}

public extension Array {
    /// Kotlin `zipWithNext`.
    func zipWithNext() -> [(Element, Element)] {
        guard count > 1 else { return [] }
        return (0..<(count - 1)).map { (self[$0], self[$0 + 1]) }
    }

    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }

    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

public extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}

public func withTimeout<T: Sendable>(seconds: Double, _ op: @escaping @Sendable () async throws -> T) async throws -> T? {
    try await withThrowingTaskGroup(of: T?.self) { group in
        group.addTask { try await op() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let first = try await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
