import Foundation

public typealias EpochMs = Int64

@Sendable public func nowMs() -> EpochMs { EpochMs((Date().timeIntervalSince1970 * 1000).rounded(.down)) }

public extension Date {
    var epochMs: EpochMs { EpochMs((timeIntervalSince1970 * 1000).rounded(.down)) }
    init(epochMs: EpochMs) { self.init(timeIntervalSince1970: Double(epochMs) / 1000) }
}

/// A calendar date with `java.time.LocalDate` semantics (proleptic Gregorian, no zone).
public struct LocalDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(_ year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func of(_ year: Int, _ month: Int, _ day: Int) -> LocalDate { LocalDate(year, month, day) }

    /// Parses "YYYY-MM-DD".
    public static func parse(_ raw: String) -> LocalDate? {
        let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), d >= 1, d <= LocalDate.lengthOfMonth(y, m) else { return nil }
        return LocalDate(y, m, d)
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = LocalDate.parse(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(raw)"))
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    public static func < (a: LocalDate, b: LocalDate) -> Bool { a.epochDay < b.epochDay }

    public func isBefore(_ other: LocalDate) -> Bool { self < other }
    public func isAfter(_ other: LocalDate) -> Bool { other < self }

    // MARK: Epoch-day arithmetic (Howard Hinnant's civil algorithms)

    public var epochDay: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public init(epochDay: Int) {
        let z = epochDay + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        self.init(y, m, d)
    }

    public static func isLeap(_ year: Int) -> Bool { (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 }

    public static func lengthOfMonth(_ year: Int, _ month: Int) -> Int {
        switch month {
        case 2: return isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    public var lengthOfMonth: Int { LocalDate.lengthOfMonth(year, month) }

    var prolepticMonth: Int { year * 12 + month - 1 }

    public func plusDays(_ n: Int) -> LocalDate { n == 0 ? self : LocalDate(epochDay: epochDay + n) }
    public func minusDays(_ n: Int) -> LocalDate { plusDays(-n) }
    public func plusWeeks(_ n: Int) -> LocalDate { plusDays(n * 7) }

    public func plusMonths(_ n: Int) -> LocalDate {
        if n == 0 { return self }
        let calc = prolepticMonth + n
        let y = Int((Double(calc) / 12).rounded(.down))
        let m = calc - y * 12 + 1
        return LocalDate(y, m, min(day, LocalDate.lengthOfMonth(y, m)))
    }

    public func minusMonths(_ n: Int) -> LocalDate { plusMonths(-n) }
    public func plusYears(_ n: Int) -> LocalDate { plusMonths(n * 12) }
    public func minusYears(_ n: Int) -> LocalDate { plusMonths(-n * 12) }

    /// `ChronoUnit.DAYS.between(a, b)`
    public static func daysBetween(_ a: LocalDate, _ b: LocalDate) -> Int { b.epochDay - a.epochDay }

    /// `ChronoUnit.MONTHS.between(a, b)`
    public static func monthsBetween(_ a: LocalDate, _ b: LocalDate) -> Int {
        let packed1 = a.prolepticMonth * 32 + a.day
        let packed2 = b.prolepticMonth * 32 + b.day
        return (packed2 - packed1) / 32
    }

    public struct Period: Equatable, Sendable {
        public let years: Int
        public let months: Int
        public let days: Int
    }

    /// `java.time.Period.between(start, end)`
    public static func period(_ start: LocalDate, _ end: LocalDate) -> Period {
        var totalMonths = end.prolepticMonth - start.prolepticMonth
        var days = end.day - start.day
        if totalMonths > 0 && days < 0 {
            totalMonths -= 1
            let calcDate = start.plusMonths(totalMonths)
            days = end.epochDay - calcDate.epochDay
        } else if totalMonths < 0 && days > 0 {
            totalMonths += 1
            days -= end.lengthOfMonth
        }
        return Period(years: totalMonths / 12, months: totalMonths % 12, days: days)
    }

    /// ISO day of week, 1 = Monday … 7 = Sunday.
    public var isoDayOfWeek: Int {
        let d = (epochDay + 3) % 7
        return (d < 0 ? d + 7 : d) + 1
    }

    /// `Calendar` weekday, 1 = Sunday … 7 = Saturday.
    public var calendarWeekday: Int { isoDayOfWeek % 7 + 1 }

    // MARK: Zone conversions

    static func calendar(_ zone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal
    }

    public static func of(ms: EpochMs, zone: TimeZone = .current) -> LocalDate {
        let comps = calendar(zone).dateComponents([.year, .month, .day], from: Date(epochMs: ms))
        return LocalDate(comps.year!, comps.month!, comps.day!)
    }

    public static func today(_ zone: TimeZone = .current) -> LocalDate { of(ms: nowMs(), zone: zone) }

    public func atTimeMs(_ hour: Int, _ minute: Int = 0, zone: TimeZone = .current) -> EpochMs {
        let comps = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return LocalDate.calendar(zone).date(from: comps)!.epochMs
    }

    public func startOfDayMs(_ zone: TimeZone = .current) -> EpochMs { atTimeMs(0, 0, zone: zone) }

    public var asDateComponents: DateComponents { DateComponents(year: year, month: month, day: day) }

    public func date(zone: TimeZone = .current) -> Date { Date(epochMs: startOfDayMs(zone)) }
}

public extension TimeZone {
    static var utc: TimeZone { TimeZone(identifier: "UTC")! }
}

/// Hour of day (0-23) of [ms] in [zone].
public func hourOf(_ ms: EpochMs, zone: TimeZone = .current) -> Int {
    LocalDate.calendar(zone).component(.hour, from: Date(epochMs: ms))
}
