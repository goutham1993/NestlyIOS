import Foundation

/// How the estimated next feed relates to now, for dashboard-style displays.
public enum NextFeedState: Equatable, Sendable {
    case noFeed
    case upcoming(dueMs: EpochMs, remainingMs: EpochMs)
    case dueNow(dueMs: EpochMs)
    case overdue(dueMs: EpochMs, overdueMs: EpochMs)

    public var dueMs: EpochMs? {
        switch self {
        case .noFeed: nil
        case let .upcoming(due, _), let .dueNow(due), let .overdue(due, _): due
        }
    }
}

public enum ReminderLogic {
    public static func typesFor(_ kind: ReminderKind) -> [ActivityType] {
        switch kind {
        case .FEED: [.BOTTLE_FEED, .BREASTFEED, .SOLIDS]
        case .PUMP: [.PUMP]
        case .DIAPER: [.DIAPER]
        case .SLEEP: [.SLEEP]
        }
    }

    /// Whether this activity anchors the milk / FEED reminder clock.
    /// Bottle and breastfeed always do; solids only when marked as a milk replacement.
    public static func resetsFeedSchedule(_ activity: ActivityEntity) -> Bool {
        switch activity.type {
        case .BOTTLE_FEED, .BREASTFEED: return true
        case .SOLIDS: return activity.solids?.resetsFeedSchedule ?? true
        default: return false
        }
    }

    /// When the next notification should fire. If the due time is already past, schedules a
    /// catch-up one minute from [now] so something still alerts once.
    public static func nextFireMs(_ lastActivityStart: EpochMs?, _ intervalMinutes: Int, now: EpochMs = nowMs()) -> EpochMs? {
        guard let last = lastActivityStart else { return nil }
        let due = last + EpochMs(intervalMinutes) * 60_000
        return due > now ? due : now + 60_000
    }

    public static func nextFeedDueMs(_ lastFeedStart: EpochMs?, _ intervalMinutes: Int) -> EpochMs? {
        lastFeedStart.map { $0 + EpochMs(max(intervalMinutes, 1)) * 60_000 }
    }

    public static func nextFeedState(_ lastFeedStart: EpochMs?, _ intervalMinutes: Int, now: EpochMs) -> NextFeedState {
        guard let due = nextFeedDueMs(lastFeedStart, intervalMinutes) else { return .noFeed }
        if now < due { return .upcoming(dueMs: due, remainingMs: due - now) }
        if now - due < dueNowWindowMs { return .dueNow(dueMs: due) }
        return .overdue(dueMs: due, overdueMs: now - due)
    }

    public static func defaultIntervalMinutes(_ kind: ReminderKind) -> Int {
        switch kind {
        case .FEED, .PUMP: 180
        case .DIAPER, .SLEEP: 120
        }
    }

    static let dueNowWindowMs: EpochMs = 60_000

    public static func label(_ kind: ReminderKind) -> String {
        switch kind {
        case .FEED: "Feed"
        case .PUMP: "Pump"
        case .DIAPER: "Diaper"
        case .SLEEP: "Sleep"
        }
    }
}

public enum AppointmentReminderLogic {
    /// When the reminder for an appointment starting at [startsAt] should fire, or nil when no
    /// alarm should be scheduled. A passed lead time fires as a catch-up one minute from now
    /// (or at the appointment time if that's sooner).
    public static func fireAtMs(_ startsAt: EpochMs, _ lead: AppointmentReminderLead, now: EpochMs = nowMs()) -> EpochMs? {
        guard let leadMinutes = lead.leadMinutes else { return nil }
        if startsAt <= now { return nil }
        let ideal = startsAt - EpochMs(leadMinutes) * 60_000
        return ideal > now ? ideal : min(now + 60_000, startsAt)
    }

    public static func requestCode(_ appointmentId: String) -> Int32 { javaHashCode("appointment:" + appointmentId) }
}

/// Once-a-day doses (Vitamin D): given at any time during the local calendar day.
public enum DailyDose {
    public static func givenAt(
        _ entries: [ActivityEntity],
        startOfToday: EpochMs,
        startOfTomorrow: EpochMs,
        type: ActivityType = .VITAMIN_D
    ) -> EpochMs? {
        entries
            .filter { $0.deletedAt == nil && $0.type == type && $0.startTime >= startOfToday && $0.startTime < startOfTomorrow }
            .map(\.startTime)
            .min()
    }

    public static func givenToday(_ entries: [ActivityEntity], now: EpochMs = nowMs(), zone: TimeZone = .current) -> EpochMs? {
        let today = LocalDate.of(ms: now, zone: zone)
        return givenAt(entries, startOfToday: today.startOfDayMs(zone), startOfTomorrow: today.plusDays(1).startOfDayMs(zone))
    }
}
