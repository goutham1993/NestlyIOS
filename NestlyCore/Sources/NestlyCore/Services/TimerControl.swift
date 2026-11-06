import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// The stopwatch groups a Live Activity can mirror.
public enum TimerGroup: String, Codable, Hashable, Sendable, CaseIterable {
    case BREASTFEED, PUMP, SLEEP

    public var keys: [TimerKey] {
        switch self {
        case .BREASTFEED: [.BREAST_LEFT, .BREAST_RIGHT]
        case .PUMP: [.PUMP]
        case .SLEEP: [.SLEEP]
        }
    }

    public var entryKind: EntryKind {
        switch self {
        case .BREASTFEED: .BREASTFEED
        case .PUMP: .PUMP
        case .SLEEP: .SLEEP
        }
    }

    public static func of(_ key: TimerKey) -> TimerGroup {
        switch key {
        case .BREAST_LEFT, .BREAST_RIGHT: .BREASTFEED
        case .PUMP: .PUMP
        case .SLEEP: .SLEEP
        }
    }
}

/// Snapshot of one timer group, shared by the Live Activity and its intents.
public struct TimerGroupState: Codable, Hashable, Sendable {
    public var side: BreastSide?
    public var accumulatedSeconds: Int64
    public var runningSince: Date?

    public var isPaused: Bool { runningSince == nil }

    public init(side: BreastSide?, accumulatedSeconds: Int64, runningSince: Date?) {
        self.side = side
        self.accumulatedSeconds = accumulatedSeconds
        self.runningSince = runningSince
    }

    /// Virtual start for `Text(timerInterval:)` while running.
    public var timerStart: Date? { runningSince.map { $0.addingTimeInterval(-Double(accumulatedSeconds)) } }

    public func elapsedSeconds(at date: Date = Date()) -> Int64 {
        accumulatedSeconds + (runningSince.map { Int64(max(0, date.timeIntervalSince($0))) } ?? 0)
    }
}

/// Timer mutations shared by the entry sheet, Live Activity buttons and intents. Starting one
/// breast side pauses the other.
public enum TimerControl {
    static let lastSideKey = "active_timers.last_breast_side"
    static let childNameKey = "active_timers.child_name"

    public static var store: ActiveTimerStore { .shared }

    public static var lastBreastSide: BreastSide? {
        AppConfig.sharedDefaults.string(forKey: lastSideKey).flatMap(BreastSide.init(rawValue:))
    }

    public static func setChildName(_ name: String?) { AppConfig.sharedDefaults.set(name, forKey: childNameKey) }
    public static var childName: String { AppConfig.sharedDefaults.string(forKey: childNameKey) ?? "Baby" }

    public static func toggle(_ key: TimerKey, now: EpochMs = nowMs()) {
        let state = store.update(key) { $0.toggle(now) }
        if key == .BREAST_LEFT || key == .BREAST_RIGHT {
            store.update(key == .BREAST_LEFT ? .BREAST_RIGHT : .BREAST_LEFT) { $0.pause(now) }
            if state.isRunning { AppConfig.sharedDefaults.set(key == .BREAST_LEFT ? "LEFT" : "RIGHT", forKey: lastSideKey) }
        }
        syncLiveActivities()
    }

    public static func setDuration(_ key: TimerKey, seconds: Int64, now: EpochMs = nowMs()) {
        store.update(key) { TimerState(accumulatedMs: seconds * 1000, runningSince: nil, sessionStart: $0.sessionStart ?? (now - seconds * 1000)) }
        syncLiveActivities()
    }

    public static func pauseResume(_ group: TimerGroup, now: EpochMs = nowMs()) {
        switch group {
        case .BREASTFEED:
            let timers = store.timers()
            if let running = group.keys.first(where: { timers[$0]?.isRunning == true }) {
                store.update(running) { $0.pause(now) }
                syncLiveActivities()
            } else {
                toggle(lastBreastSide == .RIGHT ? .BREAST_RIGHT : .BREAST_LEFT, now: now)
            }
        case .PUMP: toggle(.PUMP, now: now)
        case .SLEEP: toggle(.SLEEP, now: now)
        }
    }

    public static func switchSide(now: EpochMs = nowMs()) {
        let timers = store.timers()
        let current: TimerKey = timers[.BREAST_LEFT]?.isRunning == true ? .BREAST_LEFT
            : timers[.BREAST_RIGHT]?.isRunning == true ? .BREAST_RIGHT
            : (lastBreastSide == .RIGHT ? .BREAST_RIGHT : .BREAST_LEFT)
        toggle(current == .BREAST_LEFT ? .BREAST_RIGHT : .BREAST_LEFT, now: now)
    }

    public static func clear(_ group: TimerGroup) {
        store.clear(group.keys)
        syncLiveActivities()
    }

    public static func state(_ group: TimerGroup, now: EpochMs = nowMs()) -> TimerGroupState? {
        let timers = store.timers()
        let states = group.keys.map { timers[$0] ?? TimerState() }
        guard states.contains(where: { !$0.isIdle }) else { return nil }
        let runningIndex = states.firstIndex { $0.isRunning }
        let accumulated = states.reduce(Int64(0)) { $0 + $1.accumulatedMs } / 1000
        var side: BreastSide?
        if group == .BREASTFEED {
            side = runningIndex.map { $0 == 0 ? .LEFT : .RIGHT } ?? lastBreastSide
        }
        let since = runningIndex.flatMap { states[$0].runningSince }.map { Date(epochMs: $0) }
        return TimerGroupState(side: side, accumulatedSeconds: accumulated, runningSince: since)
    }

    /// Mirrors every non-idle timer group into a Live Activity and ends the rest.
    public static func syncLiveActivities() {
        #if canImport(ActivityKit) && os(iOS)
        LiveTimerActivities.sync()
        #endif
    }
}

#if canImport(ActivityKit) && os(iOS)
public struct TimerActivityAttributes: ActivityAttributes {
    public typealias ContentState = TimerGroupState

    public var childName: String
    public var group: TimerGroup

    public init(childName: String, group: TimerGroup) {
        self.childName = childName
        self.group = group
    }

    public func title(_ state: TimerGroupState) -> String {
        switch group {
        case .BREASTFEED:
            guard let side = state.side else { return "Breastfeeding" }
            return "Breastfeeding · \(side == .LEFT ? "Left" : "Right")"
        case .PUMP: return "Pumping"
        case .SLEEP: return "Sleeping"
        }
    }
}

public enum LiveTimerActivities {
    public static func sync() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let existing = Activity<TimerActivityAttributes>.activities
        for group in TimerGroup.allCases {
            let mine = existing.filter { $0.attributes.group == group }
            if let state = TimerControl.state(group) {
                let content = ActivityContent(state: state, staleDate: nil)
                if mine.isEmpty {
                    _ = try? Activity.request(attributes: TimerActivityAttributes(childName: TimerControl.childName, group: group), content: content)
                } else {
                    for activity in mine { Task { await activity.update(content) } }
                }
            } else {
                for activity in mine { Task { await activity.end(nil, dismissalPolicy: .immediate) } }
            }
        }
    }

    /// Like `sync()`, but waits for updates so an intent's process isn't suspended mid-update.
    public static func syncAndWait() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        for group in TimerGroup.allCases {
            let mine = Activity<TimerActivityAttributes>.activities.filter { $0.attributes.group == group }
            if let state = TimerControl.state(group) {
                for activity in mine { await activity.update(ActivityContent(state: state, staleDate: nil)) }
            } else {
                for activity in mine { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }

    public static func endAll() {
        for activity in Activity<TimerActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
#endif
