import Foundation

/// ISO-8601 timestamps as exchanged with Postgres/PostgREST.
public enum ISOTime {
    /// "2026-11-05T14:03:22.123Z"
    public static func toIso(_ ms: EpochMs) -> String {
        let secs = Int(floorDiv(ms, 1000))
        let millis = Int(ms - EpochMs(secs) * 1000)
        let days = floorDivInt(secs, 86_400)
        let secOfDay = secs - days * 86_400
        let date = LocalDate(epochDay: days)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
            date.year, date.month, date.day,
            secOfDay / 3600, (secOfDay % 3600) / 60, secOfDay % 60, millis
        )
    }

    /// Lenient parse: with/without fraction (any precision), `Z` or `±HH[:MM]` offset, `T` or space.
    public static func toMillis(_ raw: String) -> EpochMs? {
        let s = Array(raw.trimmingCharacters(in: .whitespaces).utf8)
        var i = 0
        func digits(_ n: Int) -> Int? {
            guard i + n <= s.count else { return nil }
            var v = 0
            for k in 0..<n {
                let c = s[i + k]
                guard c >= 48 && c <= 57 else { return nil }
                v = v * 10 + Int(c - 48)
            }
            i += n
            return v
        }
        func expect(_ c: UInt8) -> Bool {
            guard i < s.count, s[i] == c else { return false }
            i += 1
            return true
        }
        guard let y = digits(4), expect(45), let mo = digits(2), expect(45), let d = digits(2) else { return nil }
        var h = 0, mi = 0, sec = 0, fracMs = 0
        if i < s.count, s[i] == 84 || s[i] == 116 || s[i] == 32 {
            i += 1
            guard let hh = digits(2), expect(58), let mm = digits(2) else { return nil }
            h = hh
            mi = mm
            if expect(58) {
                guard let ss = digits(2) else { return nil }
                sec = ss
                if i < s.count, s[i] == 46 || s[i] == 44 {
                    i += 1
                    var scale = 100
                    var any = false
                    while i < s.count, s[i] >= 48, s[i] <= 57 {
                        fracMs += Int(s[i] - 48) * scale
                        scale /= 10
                        any = true
                        i += 1
                    }
                    if !any { return nil }
                }
            }
        }
        var offsetSec = 0
        if i < s.count {
            let c = s[i]
            if c == 90 || c == 122 {
                i += 1
            } else if c == 43 || c == 45 {
                let sign = c == 45 ? -1 : 1
                i += 1
                guard let oh = digits(2) else { return nil }
                var om = 0
                if expect(58) {
                    guard let m = digits(2) else { return nil }
                    om = m
                } else if let m = digits(2) {
                    om = m
                }
                offsetSec = sign * (oh * 3600 + om * 60)
            } else {
                return nil
            }
        }
        guard i == s.count else { return nil }
        let days = LocalDate(y, mo, d).epochDay
        let total = EpochMs(days) * 86_400 + EpochMs(h * 3600 + mi * 60 + sec) - EpochMs(offsetSec)
        return total * 1000 + EpochMs(fracMs)
    }

    static func floorDiv(_ a: EpochMs, _ b: EpochMs) -> EpochMs {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    static func floorDivInt(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }
}

public struct ISOParseError: Error, LocalizedError {
    public let value: String
    public var errorDescription: String? { "Unparseable timestamp \(value)" }
}

public extension EpochMs {
    func toIso() -> String { ISOTime.toIso(self) }
}

public extension String {
    func isoToMillis() throws -> EpochMs {
        guard let ms = ISOTime.toMillis(self) else { throw ISOParseError(value: self) }
        return ms
    }
}
