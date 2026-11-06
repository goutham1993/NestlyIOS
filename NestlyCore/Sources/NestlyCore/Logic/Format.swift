import Foundation

public enum Format {
    private static let lock = NSLock()
    private static var formatters: [String: DateFormatter] = [:]

    static func formatter(_ pattern: String, _ zone: TimeZone) -> DateFormatter {
        let key = "\(pattern)|\(zone.identifier)"
        lock.lock()
        defer { lock.unlock() }
        if let f = formatters[key] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = zone
        f.dateFormat = pattern
        formatters[key] = f
        return f
    }

    public static func pattern(_ pattern: String, _ ms: EpochMs, zone: TimeZone = .current) -> String {
        formatter(pattern, zone).string(from: Date(epochMs: ms))
    }

    /// "6:14pm"
    public static func time(_ epochMs: EpochMs, zone: TimeZone = .current) -> String {
        pattern("h:mma", epochMs, zone: zone).lowercased()
    }

    /// "Today", "Yesterday", "Tomorrow" or "Sep 30" (with the year if not this year).
    public static func relativeDay(_ epochMs: EpochMs, now: EpochMs, zone: TimeZone = .current) -> String {
        let date = LocalDate.of(ms: epochMs, zone: zone)
        let today = LocalDate.of(ms: now, zone: zone)
        if date == today { return "Today" }
        if date == today.minusDays(1) { return "Yesterday" }
        if date == today.plusDays(1) { return "Tomorrow" }
        return date.year == today.year ? dateText(date, "MMM d") : dateText(date, "MMM d, yyyy")
    }

    /// "Today  8:07pm"
    public static func dayAndTime(_ epochMs: EpochMs, now: EpochMs, zone: TimeZone = .current) -> String {
        "\(relativeDay(epochMs, now: now, zone: zone))  \(time(epochMs, zone: zone))"
    }

    /// Calendar-day distance from today: "Today", "Tomorrow", "in 5 days", "in 2 weeks", "in 3 months",
    /// "in 1 year", or the past equivalents ("Yesterday", "2 weeks ago").
    public static func countdown(_ epochMs: EpochMs, now: EpochMs, zone: TimeZone = .current) -> String {
        let date = LocalDate.of(ms: epochMs, zone: zone)
        let today = LocalDate.of(ms: now, zone: zone)
        let future = !date.isBefore(today)
        let (from, to) = future ? (today, date) : (date, today)
        let days = LocalDate.daysBetween(from, to)
        let months = LocalDate.monthsBetween(from, to)
        func unit(_ value: Int, _ name: String) -> String { "\(value) \(name)\(value == 1 ? "" : "s")" }
        let amount: String
        if days == 0 { return "Today" }
        if days == 1 { return future ? "Tomorrow" : "Yesterday" }
        if days < 14 {
            amount = unit(days, "day")
        } else if days < 30 || months == 0 {
            amount = unit(days / 7, "week")
        } else if months < 12 {
            amount = unit(months, "month")
        } else {
            amount = unit(months / 12, "year")
        }
        return future ? "in \(amount)" : "\(amount) ago"
    }

    /// "Thu, Oct 1"
    public static func headerDate(_ now: EpochMs, zone: TimeZone = .current) -> String {
        pattern("EEE, MMM d", now, zone: zone)
    }

    /// "May 12 2026 4:30am"
    public static func longDateTime(_ epochMs: EpochMs, zone: TimeZone = .current) -> String {
        "\(pattern("MMM d yyyy", epochMs, zone: zone)) \(time(epochMs, zone: zone))"
    }

    /// "Oct 1, 2026"
    public static func date(_ date: LocalDate) -> String { dateText(date, "MMM d, yyyy") }

    public static func dateText(_ date: LocalDate, _ pattern: String) -> String {
        formatter(pattern, .utc).string(from: Date(epochMs: date.startOfDayMs(.utc)))
    }

    /// Age since [birthDate]: "Born today", "3 days old", "2 weeks, 3 days old", "4 months, 2 weeks old",
    /// "1 year, 3 months old". Nil if [birthDate] is in the future.
    public static func age(_ birthDate: LocalDate, today: LocalDate = .today()) -> String? {
        if birthDate.isAfter(today) { return nil }
        let period = LocalDate.period(birthDate, today)
        func unit(_ value: Int, _ name: String) -> String { "\(value) \(name)\(value == 1 ? "" : "s")" }
        if period.years > 0 {
            return ([unit(period.years, "year")] + (period.months > 0 ? [unit(period.months, "month")] : []))
                .joined(separator: ", ") + " old"
        }
        if period.months > 0 {
            return ([unit(period.months, "month")] + (period.days / 7 > 0 ? [unit(period.days / 7, "week")] : []))
                .joined(separator: ", ") + " old"
        }
        if period.days >= 7 {
            return ([unit(period.days / 7, "week")] + (period.days % 7 > 0 ? [unit(period.days % 7, "day")] : []))
                .joined(separator: ", ") + " old"
        }
        if period.days > 0 { return "\(unit(period.days, "day")) old" }
        return "Born today"
    }

    /// "1h 53m ago", "5m ago", "Just now", "3d ago"
    public static func ago(_ epochMs: EpochMs, now: EpochMs) -> String {
        let minutes = max((now - epochMs) / 60_000, 0)
        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        if minutes < 60 * 24 { return "\(minutes / 60)h \(minutes % 60)m ago" }
        return "\(minutes / (60 * 24))d ago"
    }

    /// "1h 5m", "12m", "45s", "0s"
    public static func duration(_ totalSec: Int64) -> String {
        let h = totalSec / 3600
        let m = (totalSec % 3600) / 60
        let s = totalSec % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return s > 0 ? "\(m)m \(s)s" : "\(m)m" }
        return "\(s)s"
    }

    /// "Next feeding in 1h 25m at 7:18pm", or how overdue it is. Nil when no feed has been logged.
    public static func nextFeeding(_ state: NextFeedState) -> String? {
        switch state {
        case let .upcoming(due, remaining):
            return "Next feeding in \(durationShort(remaining, roundUp: true)) at \(time(due))"
        case .dueNow:
            return "Next feeding due now"
        case let .overdue(due, overdue):
            return "Next feeding overdue by \(durationShort(overdue, roundUp: false)) · due \(time(due))"
        case .noFeed:
            return nil
        }
    }

    /// "1m", "25m", "1h", "1h 25m", "1d 2h".
    public static func durationShort(_ ms: EpochMs, roundUp: Bool) -> String {
        let totalMinutes = max((roundUp ? ms + 59_999 : ms) / 60_000, 1)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 || (days == 0 && hours == 0) { parts.append("\(minutes)m") }
        return parts.joined(separator: " ")
    }

    /// "150" for whole numbers, "7.34" otherwise.
    public static func number(_ value: Double, maxDecimals: Int = 2) -> String {
        let factor = pow(10.0, Double(maxDecimals))
        let rounded = Double(kRound(value * factor)) / factor
        if rounded == rounded.rounded(.towardZero) { return String(Int64(rounded)) }
        var text = String(rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    public static func ml(_ value: Double) -> String { "\(number(value, maxDecimals: 0)) mL" }

    public static func volume(_ ml: Double, _ prefs: UnitPrefs = .DEFAULT) -> String {
        let decimals = prefs.volume == .OZ ? 1 : 0
        return "\(number(Units.mlToDisplay(ml, prefs.volume), maxDecimals: decimals)) \(Units.volumeLabel(prefs.volume))"
    }

    public static func weight(_ kg: Double, _ prefs: UnitPrefs = .DEFAULT) -> String {
        "\(number(Units.kgToDisplay(kg, prefs.weight), maxDecimals: prefs.weight == .LB ? 1 : 2)) \(Units.weightLabel(prefs.weight))"
    }

    public static func length(_ cm: Double, _ prefs: UnitPrefs = .DEFAULT) -> String {
        "\(number(Units.cmToDisplay(cm, prefs.length), maxDecimals: 1)) \(Units.lengthLabel(prefs.length))"
    }

    public static func temp(_ celsius: Double, _ prefs: UnitPrefs = .DEFAULT) -> String {
        "\(number(Units.cToDisplay(celsius, prefs.temp), maxDecimals: 1)) \(Units.tempLabel(prefs.temp))"
    }

    public static func lowerFirst(_ text: String) -> String { text.prefix(1).lowercased() + text.dropFirst() }

    /// Timer readout: "MM:SS" under an hour, "H:MM" after.
    public static func stopwatch(_ totalSec: Int64) -> String {
        if totalSec >= 3600 { return String(format: "%d:%02d", totalSec / 3600, (totalSec % 3600) / 60) }
        return String(format: "%02d:%02d", totalSec / 60, totalSec % 60)
    }
}
