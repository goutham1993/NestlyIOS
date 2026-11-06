import Foundation

public enum MetricUnit: Sendable { case COUNT, VOLUME, DURATION }

/// PER_DAY: window total / days. AVERAGE: mean of the individual samples (bottles, gaps, naps…).
public enum MetricStat: Sendable { case PER_DAY, AVERAGE }

public enum DayPart: Sendable { case ALL, DAY, NIGHT }

public enum TrendSeries: Int, CaseIterable, Comparable, Sendable {
    case FEED, BOTTLE, BREASTFEED, COMBO, SOLIDS, BREAST_MILK, FORMULA, OTHER_MILK, PUMP, WET, DIRTY, MIXED_DIAPER, DRY, SLEEP, NAP, AWAKE

    public static func < (a: TrendSeries, b: TrendSeries) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .FEED: "Feeds"
        case .BOTTLE: "Bottle Feed"
        case .BREASTFEED: "Breastfeed"
        case .COMBO: "Combo Feed"
        case .SOLIDS: "Solids"
        case .BREAST_MILK: "Breast Milk"
        case .FORMULA: "Formula"
        case .OTHER_MILK: "Unspecified"
        case .PUMP: "Pump"
        case .WET: "Wet"
        case .DIRTY: "Dirty"
        case .MIXED_DIAPER: "Wet + Dirty"
        case .DRY: "Dry"
        case .SLEEP: "Sleep"
        case .NAP: "Naps"
        case .AWAKE: "Awake"
        }
    }
}

public enum TrendMetric: String, CaseIterable, Sendable, Identifiable {
    case FEED_SESSIONS, TOTAL_BF, DAY_BF, NIGHT_BF, BF_LENGTH, AMOUNT_BOTTLEFED, BOTTLE_SIZE, TIME_BETWEEN_FEEDS,
         PUMP_SESSIONS, AMOUNT_PUMPED, PUMP_HOURS,
         TOTAL_DIAPERS, DAY_DIAPERS, NIGHT_DIAPERS,
         TOTAL_SLEEP, DAY_SLEEP, NIGHT_SLEEP, LONGEST_SLEEP, DAY_NAPS, NAP_LENGTH, WAKE_WINDOW

    public var id: String { rawValue }

    struct Spec {
        let section: CardKind
        let title: String
        let unit: MetricUnit
        let stat: MetricStat
        var part: DayPart = .ALL
        var noun: String = ""
        var showBreakdown = false
    }

    var spec: Spec {
        switch self {
        case .FEED_SESSIONS: Spec(section: .FEED, title: "Feed Sessions", unit: .COUNT, stat: .PER_DAY, noun: "sessions", showBreakdown: true)
        case .TOTAL_BF: Spec(section: .FEED, title: "Total BF Hours", unit: .DURATION, stat: .PER_DAY)
        case .DAY_BF: Spec(section: .FEED, title: "Daytime BF Hours", unit: .DURATION, stat: .PER_DAY, part: .DAY)
        case .NIGHT_BF: Spec(section: .FEED, title: "Nighttime BF Hours", unit: .DURATION, stat: .PER_DAY, part: .NIGHT)
        case .BF_LENGTH: Spec(section: .FEED, title: "BF Session Length", unit: .DURATION, stat: .AVERAGE)
        case .AMOUNT_BOTTLEFED: Spec(section: .FEED, title: "Amount Bottlefed", unit: .VOLUME, stat: .PER_DAY, showBreakdown: true)
        case .BOTTLE_SIZE: Spec(section: .FEED, title: "Bottle Size", unit: .VOLUME, stat: .AVERAGE)
        case .TIME_BETWEEN_FEEDS: Spec(section: .FEED, title: "Time Btwn Feedings", unit: .DURATION, stat: .AVERAGE)
        case .PUMP_SESSIONS: Spec(section: .PUMP, title: "Pump Sessions", unit: .COUNT, stat: .PER_DAY, noun: "sessions")
        case .AMOUNT_PUMPED: Spec(section: .PUMP, title: "Amount Pumped", unit: .VOLUME, stat: .PER_DAY)
        case .PUMP_HOURS: Spec(section: .PUMP, title: "Total Pump Hours", unit: .DURATION, stat: .PER_DAY)
        case .TOTAL_DIAPERS: Spec(section: .DIAPER, title: "Total Diapers", unit: .COUNT, stat: .PER_DAY, noun: "diapers", showBreakdown: true)
        case .DAY_DIAPERS: Spec(section: .DIAPER, title: "Daytime Diapers", unit: .COUNT, stat: .PER_DAY, part: .DAY, noun: "diapers")
        case .NIGHT_DIAPERS: Spec(section: .DIAPER, title: "Nighttime Diapers", unit: .COUNT, stat: .PER_DAY, part: .NIGHT, noun: "diapers")
        case .TOTAL_SLEEP: Spec(section: .SLEEP, title: "Total Sleep", unit: .DURATION, stat: .PER_DAY)
        case .DAY_SLEEP: Spec(section: .SLEEP, title: "Daytime Sleep", unit: .DURATION, stat: .PER_DAY, part: .DAY)
        case .NIGHT_SLEEP: Spec(section: .SLEEP, title: "Nighttime Sleep", unit: .DURATION, stat: .PER_DAY, part: .NIGHT)
        case .LONGEST_SLEEP: Spec(section: .SLEEP, title: "Longest Sleep", unit: .DURATION, stat: .AVERAGE)
        case .DAY_NAPS: Spec(section: .SLEEP, title: "Daytime Naps", unit: .COUNT, stat: .PER_DAY, part: .DAY, noun: "naps")
        case .NAP_LENGTH: Spec(section: .SLEEP, title: "Daytime Nap Length", unit: .DURATION, stat: .AVERAGE, part: .DAY)
        case .WAKE_WINDOW: Spec(section: .SLEEP, title: "Wake Window", unit: .DURATION, stat: .AVERAGE)
        }
    }

    public var section: CardKind { spec.section }
    public var title: String { spec.title }
    public var unit: MetricUnit { spec.unit }
    public var stat: MetricStat { spec.stat }
    public var part: DayPart { spec.part }
    public var noun: String { spec.noun }
    public var showBreakdown: Bool { spec.showBreakdown }
}

public struct TrendSegment: Equatable, Sendable {
    public let series: TrendSeries
    public let value: Double
}

public struct TrendDay: Equatable, Sendable {
    public let date: LocalDate
    public let segments: [TrendSegment]
    public var total: Double { segments.reduce(0) { $0 + $1.value } }
}

/// Something to plot on the calendar: a point (start == end) or an interval such as a sleep.
public struct TrendMark: Equatable, Sendable {
    public let entryId: String
    public let series: TrendSeries
    public let startMs: EpochMs
    public let endMs: EpochMs
}

public struct MetricResult: Equatable, Sendable {
    public let metric: TrendMetric
    /// Per-day average for PER_DAY, sample mean for AVERAGE. Counts, mL or seconds.
    public let value: Double
    public let sampleCount: Int
    public let days: [TrendDay]
    public let breakdown: [TrendSegment]
    /// Contributing entries, newest first.
    public let entries: [ActivityEntity]
    public let marks: [TrendMark]
}

public enum TrendsAggregator {
    /// Daytime is 6am–6pm.
    public static let DAY_START_HOUR = 6
    public static let DAY_END_HOUR = 18

    private struct Sample {
        let date: LocalDate
        let series: TrendSeries
        let value: Double
        let entry: ActivityEntity
    }

    private struct Session {
        let startMs: EpochMs
        let series: TrendSeries
        let entries: [ActivityEntity]
    }

    public static func computeAll(_ entries: [ActivityEntity], from: LocalDate, days: Int, zone: TimeZone = .current) -> [MetricResult] {
        TrendMetric.allCases.map { compute($0, entries, from: from, days: days, zone: zone) }
    }

    public static func compute(_ metric: TrendMetric, _ entries: [ActivityEntity], from: LocalDate, days: Int, zone: TimeZone = .current) -> MetricResult {
        let dates = (0..<max(days, 0)).map { from.plusDays($0) }
        let until = from.plusDays(days)
        let (allSamples, allMarks) = samples(metric, entries, zone)
        let samples = allSamples.filter { !$0.date.isBefore(from) && $0.date.isBefore(until) }
        let fromMs = from.startOfDayMs(zone)
        let untilMs = until.startOfDayMs(zone)
        let marks = allMarks.filter { $0.endMs >= fromMs && $0.startMs < untilMs }

        let byDate = Dictionary(grouping: samples, by: \.date)
        let trendDays = dates.map { date in TrendDay(date: date, segments: combine(byDate[date] ?? [], metric.stat, divisor: 1)) }
        let total = samples.reduce(0.0) { $0 + $1.value }
        let value: Double
        switch metric.stat {
        case .PER_DAY: value = days == 0 ? 0 : total / Double(days)
        case .AVERAGE: value = samples.isEmpty ? 0 : total / Double(samples.count)
        }
        return MetricResult(
            metric: metric,
            value: value,
            sampleCount: samples.count,
            days: trendDays,
            breakdown: combine(samples, metric.stat, divisor: days),
            entries: samples.map(\.entry).distinctBy(\.id).sortedStableDescending { $0.startTime },
            marks: marks
        )
    }

    private static func combine(_ samples: [Sample], _ stat: MetricStat, divisor: Int) -> [TrendSegment] {
        samples.groupedOrdered(by: \.series)
            .map { group -> TrendSegment in
                let sum = group.values.reduce(0.0) { $0 + $1.value }
                let value = stat == .PER_DAY ? sum / Double(max(divisor, 1)) : sum / Double(group.values.count)
                return TrendSegment(series: group.key, value: value)
            }
            .sortedStable { $0.series.rawValue }
    }

    private static func samples(_ metric: TrendMetric, _ entries: [ActivityEntity], _ zone: TimeZone) -> ([Sample], [TrendMark]) {
        let ascending = entries.sortedStable { $0.startTime }
        let feeds = ascending.filter { feedTypes.contains($0.type) }
        let breastfeeds = ascending.filter { $0.type == .BREASTFEED }
        let bottles = ascending.filter { $0.type == .BOTTLE_FEED }
        let pumps = ascending.filter { $0.type == .PUMP }
        let diapers = ascending.filter { $0.type == .DIAPER }
        let sleeps = ascending.filter { $0.type == .SLEEP && $0.endTime != nil && $0.endTime! > $0.startTime }

        func dateOf(_ e: ActivityEntity) -> LocalDate { LocalDate.of(ms: e.startTime, zone: zone) }
        func daytime(_ e: ActivityEntity) -> Bool { isDaytime(e.startTime, zone) }
        func pointMarks(_ list: [ActivityEntity], _ series: (ActivityEntity) -> TrendSeries) -> [TrendMark] {
            list.map { TrendMark(entryId: $0.id, series: series($0), startMs: $0.startTime, endMs: $0.startTime) }
        }
        func partFilter(_ e: ActivityEntity) -> Bool {
            switch metric.part {
            case .ALL: true
            case .DAY: daytime(e)
            case .NIGHT: !daytime(e)
            }
        }
        func breastMark(_ e: ActivityEntity) -> TrendMark {
            TrendMark(entryId: e.id, series: .BREASTFEED, startMs: e.startTime, endMs: e.endTime ?? (e.startTime + breastSec(e) * 1000))
        }

        switch metric {
        case .FEED_SESSIONS:
            let s = sessions(feeds)
            return (
                s.map { Sample(date: LocalDate.of(ms: $0.startMs, zone: zone), series: $0.series, value: 1, entry: $0.entries[0]) },
                s.flatMap { session in session.entries.map { TrendMark(entryId: $0.id, series: session.series, startMs: $0.startTime, endMs: $0.startTime) } }
            )
        case .TOTAL_BF, .DAY_BF, .NIGHT_BF:
            let list = breastfeeds.filter(partFilter)
            return (list.map { Sample(date: dateOf($0), series: .BREASTFEED, value: Double(breastSec($0)), entry: $0) }, list.map(breastMark))
        case .BF_LENGTH:
            let list = breastfeeds.filter { breastSec($0) > 0 }
            return (list.map { Sample(date: dateOf($0), series: .BREASTFEED, value: Double(breastSec($0)), entry: $0) }, list.map(breastMark))
        case .AMOUNT_BOTTLEFED:
            let samples = bottles.flatMap { entry -> [Sample] in
                guard let b = entry.bottle else { return [] }
                let total = b.totalMl ?? ((b.breastMilkMl ?? 0) + (b.formulaMl ?? 0))
                let breastMilk = b.breastMilkMl ?? (b.milkType == .BREAST_MILK ? total : 0)
                let formula = b.formulaMl ?? (b.milkType == .FORMULA ? total : 0)
                let other = max(total - breastMilk - formula, 0)
                return [(TrendSeries.BREAST_MILK, breastMilk), (.FORMULA, formula), (.OTHER_MILK, other)]
                    .filter { $0.1 > 0 }
                    .map { Sample(date: dateOf(entry), series: $0.0, value: $0.1, entry: entry) }
            }
            return (samples, pointMarks(samples.map(\.entry).distinctBy(\.id), milkSeries))
        case .BOTTLE_SIZE:
            let list = bottles.filter { ($0.bottle?.totalMl ?? 0) > 0 }
            return (list.map { Sample(date: dateOf($0), series: .BOTTLE, value: $0.bottle!.totalMl!, entry: $0) }, pointMarks(list) { _ in .BOTTLE })
        case .TIME_BETWEEN_FEEDS:
            let s = sessions(feeds)
            return (
                s.zipWithNext().map { prev, next in
                    Sample(date: LocalDate.of(ms: next.startMs, zone: zone), series: .FEED, value: Double(next.startMs - prev.startMs) / 1000, entry: next.entries[0])
                },
                s.map { TrendMark(entryId: $0.entries[0].id, series: $0.series, startMs: $0.startMs, endMs: $0.startMs) }
            )
        case .PUMP_SESSIONS:
            return (pumps.map { Sample(date: dateOf($0), series: .PUMP, value: 1, entry: $0) }, pumpMarks(pumps))
        case .AMOUNT_PUMPED:
            let list = pumps.filter { pumpMl($0) > 0 }
            return (list.map { Sample(date: dateOf($0), series: .PUMP, value: pumpMl($0), entry: $0) }, pumpMarks(list))
        case .PUMP_HOURS:
            let list = pumps.filter { ($0.pump?.durationSec ?? 0) > 0 }
            return (list.map { Sample(date: dateOf($0), series: .PUMP, value: Double($0.pump!.durationSec), entry: $0) }, pumpMarks(list))
        case .TOTAL_DIAPERS, .DAY_DIAPERS, .NIGHT_DIAPERS:
            let list = diapers.filter(partFilter)
            return (list.map { Sample(date: dateOf($0), series: diaperSeries($0), value: 1, entry: $0) }, pointMarks(list, diaperSeries))
        case .TOTAL_SLEEP, .DAY_SLEEP, .NIGHT_SLEEP:
            // Split each sleep across the calendar days (and day/night bands) it overlaps.
            let samples = sleeps.flatMap { sleep -> [Sample] in
                let end = sleep.endTime!
                var date = LocalDate.of(ms: sleep.startTime, zone: zone)
                let lastDate = LocalDate.of(ms: end, zone: zone)
                var out: [Sample] = []
                while !date.isAfter(lastDate) {
                    let dayStart = date.startOfDayMs(zone)
                    let nextDay = date.plusDays(1).startOfDayMs(zone)
                    let lightStart = date.atTimeMs(DAY_START_HOUR, 0, zone: zone)
                    let lightEnd = date.atTimeMs(DAY_END_HOUR, 0, zone: zone)
                    let total = overlapSec(sleep.startTime, end, dayStart, nextDay)
                    let light = overlapSec(sleep.startTime, end, lightStart, lightEnd)
                    let sec: Double
                    switch metric.part {
                    case .ALL: sec = total
                    case .DAY: sec = light
                    case .NIGHT: sec = total - light
                    }
                    if sec > 0 { out.append(Sample(date: date, series: .SLEEP, value: sec, entry: sleep)) }
                    date = date.plusDays(1)
                }
                return out
            }
            return (samples, sleepMarks(samples.map(\.entry).distinctBy(\.id)))
        case .LONGEST_SLEEP:
            let longest = sleeps.groupedOrdered(by: dateOf).map { group -> Sample in
                var best = group.values[0]
                for s in group.values.dropFirst() where (s.endTime! - s.startTime) > (best.endTime! - best.startTime) { best = s }
                return Sample(date: group.key, series: .SLEEP, value: Double(best.endTime! - best.startTime) / 1000, entry: best)
            }
            return (longest, sleepMarks(longest.map(\.entry)))
        case .DAY_NAPS, .NAP_LENGTH:
            let naps = sleeps.filter(daytime)
            return (
                naps.map {
                    let value = metric == .DAY_NAPS ? 1.0 : Double($0.endTime! - $0.startTime) / 1000
                    return Sample(date: dateOf($0), series: .NAP, value: value, entry: $0)
                },
                sleepMarks(naps, .NAP)
            )
        case .WAKE_WINDOW:
            let gaps = sleeps.zipWithNext().filter { prev, next in next.startTime > prev.endTime! }
            return (
                gaps.map { prev, next in Sample(date: dateOf(next), series: .AWAKE, value: Double(next.startTime - prev.endTime!) / 1000, entry: next) },
                gaps.map { prev, next in TrendMark(entryId: next.id, series: .AWAKE, startMs: prev.endTime!, endMs: next.startTime) }
            )
        }
    }

    private static let feedTypes: Set<ActivityType> = [.BOTTLE_FEED, .BREASTFEED, .SOLIDS]

    /// Feeds saved together from one Combo Feed count as a single session.
    private static func sessions(_ feeds: [ActivityEntity]) -> [Session] {
        feeds.groupedOrdered { $0.comboGroupId ?? $0.id }
            .map { group -> Session in
                let types = Set(group.values.map(\.type))
                let series: TrendSeries
                if types.count > 1 {
                    series = .COMBO
                } else if types.contains(.BOTTLE_FEED) {
                    series = .BOTTLE
                } else if types.contains(.BREASTFEED) {
                    series = .BREASTFEED
                } else {
                    series = .SOLIDS
                }
                return Session(startMs: group.values.map(\.startTime).min()!, series: series, entries: group.values.sortedStable { $0.startTime })
            }
            .sortedStable { $0.startMs }
    }

    private static func breastSec(_ e: ActivityEntity) -> Int64 {
        e.breastfeed.map { $0.leftDurationSec + $0.rightDurationSec } ?? 0
    }

    private static func pumpMl(_ e: ActivityEntity) -> Double {
        e.pump.map { $0.totalMl ?? (($0.leftMl ?? 0) + ($0.rightMl ?? 0)) } ?? 0
    }

    private static func pumpMarks(_ list: [ActivityEntity]) -> [TrendMark] {
        list.map { TrendMark(entryId: $0.id, series: .PUMP, startMs: $0.startTime, endMs: $0.endTime ?? ($0.startTime + ($0.pump?.durationSec ?? 0) * 1000)) }
    }

    private static func sleepMarks(_ list: [ActivityEntity], _ series: TrendSeries = .SLEEP) -> [TrendMark] {
        list.map { TrendMark(entryId: $0.id, series: series, startMs: $0.startTime, endMs: $0.endTime ?? $0.startTime) }
    }

    private static func milkSeries(_ e: ActivityEntity) -> TrendSeries {
        switch e.bottle?.milkType {
        case .BREAST_MILK: .BREAST_MILK
        case .FORMULA: .FORMULA
        default: .OTHER_MILK
        }
    }

    private static func diaperSeries(_ e: ActivityEntity) -> TrendSeries {
        switch e.diaper?.diaperType {
        case .WET: .WET
        case .DIRTY: .DIRTY
        case .MIXED: .MIXED_DIAPER
        case .DRY, nil: .DRY
        }
    }

    private static func isDaytime(_ ms: EpochMs, _ zone: TimeZone) -> Bool {
        (DAY_START_HOUR..<DAY_END_HOUR).contains(hourOf(ms, zone: zone))
    }

    private static func overlapSec(_ start: EpochMs, _ end: EpochMs, _ from: EpochMs, _ until: EpochMs) -> Double {
        max(Double(min(end, until) - max(start, from)) / 1000, 0)
    }
}

public enum TrendsWindow: String, CaseIterable, Sendable, Identifiable {
    case ONE_DAY, SEVEN_DAYS, FOURTEEN_DAYS

    public var id: String { rawValue }

    public var days: Int {
        switch self {
        case .ONE_DAY: 1
        case .SEVEN_DAYS: 7
        case .FOURTEEN_DAYS: 14
        }
    }

    public var label: String { "\(days)d" }
}

public extension TrendMetric {
    /// "6.5", "150 mL", "3h 30m".
    func formatValue(_ value: Double, _ prefs: UnitPrefs) -> String {
        switch unit {
        case .COUNT: Format.number(value, maxDecimals: 1)
        case .VOLUME: Format.volume(value, prefs)
        case .DURATION: Format.duration(kRound(value))
        }
    }

    /// "6.5 sessions per day", "980 mL per day", "3h 30m average".
    func summary(_ value: Double, _ prefs: UnitPrefs) -> String {
        let amount = unit == .COUNT ? "\(formatValue(value, prefs)) \(noun)" : formatValue(value, prefs)
        switch stat {
        case .PER_DAY: return "\(amount) per day"
        case .AVERAGE: return "\(amount) average"
        }
    }

    /// Below this the change rounds to nothing in the badge.
    func isMeaningful(_ delta: Double) -> Bool {
        let threshold: Double
        switch unit {
        case .COUNT: threshold = 0.05
        case .VOLUME: threshold = 1.5
        case .DURATION: threshold = 1.0
        }
        return abs(delta) >= threshold
    }

    /// "Fewer sessions than the previous 14 days", "Longer than the previous day".
    func comparison(_ delta: Double, _ window: TrendsWindow) -> String {
        let up = delta > 0
        let lead: String
        if unit == .COUNT {
            lead = up ? "More \(noun)" : "Fewer \(noun)"
        } else if unit == .DURATION && stat == .AVERAGE {
            lead = up ? "Longer" : "Shorter"
        } else {
            lead = up ? "More" : "Less"
        }
        return "\(lead) than \(TrendsWindow.periodText(window.days))"
    }
}

public extension TrendsWindow {
    static func periodText(_ days: Int) -> String { days == 1 ? "the previous day" : "the previous \(days) days" }
}
