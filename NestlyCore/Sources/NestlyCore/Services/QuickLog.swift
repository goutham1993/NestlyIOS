import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

public extension ActiveTimerStore {
    static let shared = ActiveTimerStore(defaults: AppConfig.sharedDefaults)
}

public enum WidgetRefresher {
    public static func reloadAll() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

/// In-process guard so a second tap while a quick save is in flight is ignored (never retried).
actor QuickLogGate {
    static let shared = QuickLogGate()
    private var busy: Set<String> = []

    func enter(_ key: String) -> Bool { busy.insert(key).inserted }
    func leave(_ key: String) { busy.remove(key) }
}

/// One-tap bottle feed for the widget, Siri, the home-screen quick action and the nightstand
/// (spec §21.1): default amount, else the last bottle's amount, at tap time.
public enum QuickBottleLog {
    public static func run(repos: Repositories = .shared, at now: EpochMs = nowMs(), sessionWait: Double = 30) async -> QuickBottleResult {
        guard await QuickLogGate.shared.enter("bottle") else { return .alreadySaving }
        defer { Task { await QuickLogGate.shared.leave("bottle") } }

        switch sessionWaitOutcome(await repos.backend.probeSession(timeout: sessionWait)) {
        case .SIGNED_OUT: return .notSignedIn
        case .NOT_READY: return .sessionNotReady
        case .SIGNED_IN: break
        }
        do {
            guard let profile = try await repos.family.selectedProfile() else { return .noChild }
            let defaultMl = repos.prefs.defaultBottleMl
            let lastMl: Double? = (defaultMl ?? 0) > 0 ? nil :
                (try? await repos.activities.getLatest(familyId: profile.familyId, profileId: profile.id, .BOTTLE_FEED))?.bottle?.totalMl
            guard let ml = resolveQuickBottleMl(defaultMl: defaultMl, lastMl: lastMl) else { return .noAmount }
            let draft = EntryDraft(startTime: now, bottleMl: ml)
            guard EntryBuilder.canSave(.BOTTLE, draft) else { return .noAmount }
            let ctx = EntryContext(
                familyId: profile.familyId, profileId: profile.id,
                caregiverId: try await repos.family.currentCaregiverId(familyId: profile.familyId),
                timeZone: TimeZone.current.identifier, now: now, newId: newUUID
            )
            try await repos.activities.saveAll(EntryBuilder.build(.BOTTLE, draft, ctx))
            WidgetRefresher.reloadAll()
            Task.detached { await NotificationScheduler.rescheduleAll(repos: repos) }
            return .saved(ml: ml, atMs: now)
        } catch {
            return .failed
        }
    }
}

public extension QuickBottleResult {
    /// The nightstand's own wording.
    func nightstandMessage(_ prefs: UnitPrefs, zone: TimeZone = .current) -> String {
        switch self {
        case let .saved(ml, atMs): "Feed added successfully: \(Format.volume(ml, prefs)) at \(Format.time(atMs, zone: zone))"
        case .notSignedIn: "Couldn't add feed. Open Nestly and sign in first."
        case .sessionNotReady: "Couldn't add feed yet — sign-in is still loading. Check your connection and tap again."
        case .noChild: "Couldn't add feed. Open Nestly and select a child first."
        case .noAmount: "No default bottle amount set. Open Nestly to set one first."
        case .failed: "Couldn't add feed. Check your connection and try again."
        case .alreadySaving: "Saving bottle feed…"
        }
    }

    /// Short form for the widget ("Saved 4 oz at 6:14pm").
    func widgetMessage(_ prefs: UnitPrefs, zone: TimeZone = .current) -> String {
        if case let .saved(ml, atMs) = self { return "Saved \(Format.volume(ml, prefs)) at \(Format.time(atMs, zone: zone))" }
        return message(prefs, zone: zone)
    }

    var isSaved: Bool { if case .saved = self { true } else { false } }
}

/// Today's Vitamin D with no UI, reusing the last dose (or 400 IU). Never logs twice a day.
public enum QuickVitaminDLog {
    public static func run(repos: Repositories = .shared, at now: EpochMs = nowMs(), sessionWait: Double = 30) async -> QuickVitaminDResult {
        guard await QuickLogGate.shared.enter("vitd") else { return .failed }
        defer { Task { await QuickLogGate.shared.leave("vitd") } }

        switch sessionWaitOutcome(await repos.backend.probeSession(timeout: sessionWait)) {
        case .SIGNED_OUT: return .notSignedIn
        case .NOT_READY: return .sessionNotReady
        case .SIGNED_IN: break
        }
        do {
            guard let profile = try await repos.family.selectedProfile() else { return .noChild }
            let zone = TimeZone.current
            let startOfToday = LocalDate.of(ms: now, zone: zone).startOfDayMs(zone)
            let last = try await repos.activities.getLatest(familyId: profile.familyId, profileId: profile.id, .VITAMIN_D)
            if let last, last.startTime >= startOfToday { return .alreadyGiven(atMs: last.startTime) }
            let draft = EntryDraft(
                startTime: now,
                dose: last?.medical?.dose ?? EntryBuilder.VITAMIN_D_DEFAULT_DOSE,
                doseUnit: last?.medical?.doseUnit ?? EntryBuilder.VITAMIN_D_DEFAULT_UNIT
            )
            let ctx = EntryContext(
                familyId: profile.familyId, profileId: profile.id,
                caregiverId: try await repos.family.currentCaregiverId(familyId: profile.familyId),
                timeZone: zone.identifier, now: now, newId: newUUID
            )
            try await repos.activities.saveAll(EntryBuilder.build(.VITAMIN_D, draft, ctx))
            WidgetRefresher.reloadAll()
            return .saved(atMs: now)
        } catch {
            return .failed
        }
    }
}

public extension QuickVitaminDResult {
    func message(zone: TimeZone = .current) -> String {
        switch self {
        case let .saved(atMs): "Vitamin D added at \(Format.time(atMs, zone: zone))"
        case let .alreadyGiven(atMs): "Vitamin D was already given today at \(Format.time(atMs, zone: zone))"
        case .notSignedIn: "Couldn't add Vitamin D. Open Nestly and sign in first."
        case .sessionNotReady: "Couldn't add Vitamin D yet — sign-in is still loading. Check your connection and tap again."
        case .noChild: "Couldn't add Vitamin D. Open Nestly and select a child first."
        case .failed: "Couldn't add Vitamin D. Check your connection and try again."
        }
    }
}

/// Everything the "Next feed" widget and the nightstand show.
public struct FeedSnapshot: Sendable, Equatable {
    public var childName: String
    /// Newest bottle / breastfeed / solids (including solids that keep the milk schedule).
    public var lastFeed: ActivityEntity?
    /// Latest feed that anchors next-feed / FEED reminders (skips non-resetting solids).
    public var scheduleFeed: ActivityEntity?
    public var intervalMinutes: Int
    public var vitaminDGivenAt: EpochMs?
    public var todayFeedCount: Int
    public var todayBottleMl: Double
    /// Average gap between today's feed sessions; nil with fewer than two.
    public var todayAvgIntervalMs: EpochMs? = nil

    public var nextDueMs: EpochMs? { ReminderLogic.nextFeedDueMs(scheduleFeed?.startTime, intervalMinutes) }

    public func state(now: EpochMs) -> NextFeedState { ReminderLogic.nextFeedState(scheduleFeed?.startTime, intervalMinutes, now: now) }

    public static func placeholder(now: EpochMs = nowMs()) -> FeedSnapshot {
        let last = ActivityEntity(id: "p", familyId: "f", profileId: "c", type: .BOTTLE_FEED, startTime: now - 75 * 60_000, timeZone: TimeZone.current.identifier, bottle: BottleDetails(totalMl: 120), createdAt: now, updatedAt: now)
        return FeedSnapshot(
            childName: "Baby",
            lastFeed: last,
            scheduleFeed: last,
            intervalMinutes: 180, vitaminDGivenAt: nil, todayFeedCount: 4, todayBottleMl: 480
        )
    }
}

public enum FeedSnapshotResult: Sendable, Equatable {
    case notSignedIn
    case noChild
    case unavailable
    case ready(FeedSnapshot)
}

public enum FeedSnapshotLoader {
    public static let feedTypes: [ActivityType] = [.BOTTLE_FEED, .BREASTFEED, .SOLIDS]

    public static func load(repos: Repositories = .shared, now: EpochMs = nowMs(), sessionWait: Double = 20) async -> FeedSnapshotResult {
        switch sessionWaitOutcome(await repos.backend.probeSession(timeout: sessionWait)) {
        case .SIGNED_OUT: return .notSignedIn
        case .NOT_READY: return .unavailable
        case .SIGNED_IN: break
        }
        do {
            guard let profile = try await repos.family.selectedProfile() else { return .noChild }
            let zone = TimeZone.current
            let today = LocalDate.of(ms: now, zone: zone)
            let start = today.startOfDayMs(zone)
            let todayRows = try await repos.activities.range(familyId: profile.familyId, profileId: profile.id, from: start, to: today.plusDays(1).startOfDayMs(zone))
            let last = try await repos.activities.latestOf(familyId: profile.familyId, profileId: profile.id, feedTypes)
            let schedule = try await repos.activities.latestFeedForSchedule(familyId: profile.familyId, profileId: profile.id)
            let reminders = (try? await repos.reminders.fetchMine()) ?? []
            let interval = reminders.first { $0.kind == .FEED && $0.profileId == profile.id }?.intervalMinutes
                ?? repos.prefs.defaultFeedIntervalMinutes
            let feeds = todayRows.filter { feedTypes.contains($0.type) }
            let sessionStarts = Dictionary(grouping: feeds) { $0.comboGroupId ?? $0.id }
                .values.compactMap { $0.map(\.startTime).min() }.sorted()
            let sessions = sessionStarts.count
            let avgInterval = sessions >= 2 ? (sessionStarts[sessions - 1] - sessionStarts[0]) / EpochMs(sessions - 1) : nil
            return .ready(FeedSnapshot(
                childName: profile.name,
                lastFeed: last,
                scheduleFeed: schedule,
                intervalMinutes: interval,
                vitaminDGivenAt: DailyDose.givenAt(todayRows, startOfToday: start, startOfTomorrow: today.plusDays(1).startOfDayMs(zone)),
                todayFeedCount: sessions,
                todayBottleMl: feeds.reduce(0) { $0 + ($1.bottle?.totalMl ?? 0) },
                todayAvgIntervalMs: avgInterval
            ))
        } catch {
            return .unavailable
        }
    }
}
