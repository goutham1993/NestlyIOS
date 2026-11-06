import Foundation

public enum TimerKey: String, CaseIterable, Codable, Sendable { case BREAST_LEFT, BREAST_RIGHT, PUMP, SLEEP }

/// A stopwatch that survives process death. `accumulatedMs` holds time from earlier runs;
/// `runningSince` is set while the timer is ticking. `sessionStart` is when it was first started.
public struct TimerState: Equatable, Hashable, Codable, Sendable {
    public var accumulatedMs: Int64
    public var runningSince: EpochMs?
    public var sessionStart: EpochMs?

    public init(accumulatedMs: Int64 = 0, runningSince: EpochMs? = nil, sessionStart: EpochMs? = nil) {
        self.accumulatedMs = accumulatedMs
        self.runningSince = runningSince
        self.sessionStart = sessionStart
    }

    public var isRunning: Bool { runningSince != nil }
    public var isIdle: Bool { accumulatedMs == 0 && runningSince == nil }

    public func elapsedMs(_ now: EpochMs) -> Int64 {
        accumulatedMs + (runningSince.map { max(now - $0, 0) } ?? 0)
    }

    public func start(_ now: EpochMs) -> TimerState {
        if isRunning { return self }
        return TimerState(accumulatedMs: accumulatedMs, runningSince: now, sessionStart: sessionStart ?? now)
    }

    public func pause(_ now: EpochMs) -> TimerState {
        if !isRunning { return self }
        return TimerState(accumulatedMs: elapsedMs(now), runningSince: nil, sessionStart: sessionStart)
    }

    public func toggle(_ now: EpochMs) -> TimerState { isRunning ? pause(now) : start(now) }
}

/// Persists timers in (App Group) user defaults so the app, widgets and Live Activity intents share them.
public final class ActiveTimerStore: @unchecked Sendable {
    public static let didChange = Notification.Name("NestlyActiveTimersDidChange")

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func timers() -> [TimerKey: TimerState] {
        lock.lock()
        defer { lock.unlock() }
        return Dictionary(uniqueKeysWithValues: TimerKey.allCases.map { ($0, read($0)) })
    }

    public func state(_ key: TimerKey) -> TimerState {
        lock.lock()
        defer { lock.unlock() }
        return read(key)
    }

    @discardableResult
    public func update(_ key: TimerKey, _ transform: (TimerState) -> TimerState) -> TimerState {
        lock.lock()
        let next = transform(read(key))
        defaults.set(next.accumulatedMs, forKey: accumulatedKey(key))
        if let r = next.runningSince { defaults.set(r, forKey: runningKey(key)) } else { defaults.removeObject(forKey: runningKey(key)) }
        if let s = next.sessionStart { defaults.set(s, forKey: sessionKey(key)) } else { defaults.removeObject(forKey: sessionKey(key)) }
        lock.unlock()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        return next
    }

    public func clear(_ keys: TimerKey...) { clear(keys) }

    public func clear(_ keys: [TimerKey]) {
        lock.lock()
        for key in keys {
            defaults.removeObject(forKey: accumulatedKey(key))
            defaults.removeObject(forKey: runningKey(key))
            defaults.removeObject(forKey: sessionKey(key))
        }
        lock.unlock()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    private func read(_ key: TimerKey) -> TimerState {
        TimerState(
            accumulatedMs: (defaults.object(forKey: accumulatedKey(key)) as? NSNumber)?.int64Value ?? 0,
            runningSince: (defaults.object(forKey: runningKey(key)) as? NSNumber)?.int64Value,
            sessionStart: (defaults.object(forKey: sessionKey(key)) as? NSNumber)?.int64Value
        )
    }

    private func accumulatedKey(_ key: TimerKey) -> String { "active_timers.\(key.rawValue)_accumulated" }
    private func runningKey(_ key: TimerKey) -> String { "active_timers.\(key.rawValue)_running_since" }
    private func sessionKey(_ key: TimerKey) -> String { "active_timers.\(key.rawValue)_session_start" }
}

/// Amount for a one-tap bottle feed: the stored default wins, otherwise the most recent bottle amount.
/// Nil when there is nothing sensible to save.
public func resolveQuickBottleMl(defaultMl: Double?, lastMl: Double?) -> Double? {
    [defaultMl, lastMl].compactMap { $0 }.first { $0 > 0 }
}

/// What the auth client reported while a quick log waited for the restored session.
public enum SessionProbe: Sendable {
    case signedIn, signedOut, restoring, refreshFailed
}

public enum SessionWaitOutcome: Sendable { case SIGNED_IN, SIGNED_OUT, NOT_READY }

/// Only a definitive signed-in / signed-out status is a verdict. A cold process that is still
/// restoring or refreshing its session — or a wait that timed out (`nil`) — is NOT a sign-out.
public func sessionWaitOutcome(_ status: SessionProbe?) -> SessionWaitOutcome {
    switch status {
    case .signedIn: .SIGNED_IN
    case .signedOut: .SIGNED_OUT
    default: .NOT_READY
    }
}

public enum QuickBottleResult: Equatable, Sendable {
    case saved(ml: Double, atMs: EpochMs)
    case notSignedIn
    case sessionNotReady
    case noChild
    case noAmount
    case failed
    case alreadySaving

    public func message(_ prefs: UnitPrefs, zone: TimeZone = .current) -> String {
        switch self {
        case let .saved(ml, atMs): "Bottle feed saved: \(Format.volume(ml, prefs)) at \(Format.time(atMs, zone: zone))"
        case .notSignedIn: "Couldn't save bottle feed. Open Nestly and sign in first."
        case .sessionNotReady: "Couldn't save bottle feed yet — still restoring your sign-in. Check your connection and try again."
        case .noChild: "Couldn't save bottle feed. Open Nestly and select a child first."
        case .noAmount: "No default bottle amount set. Open Nestly to set one first."
        case .failed: "Couldn't save bottle feed. Check your connection and try again."
        case .alreadySaving: "Saving bottle feed…"
        }
    }
}

public enum QuickVitaminDResult: Equatable, Sendable {
    case saved(atMs: EpochMs)
    case alreadyGiven(atMs: EpochMs)
    case notSignedIn
    case sessionNotReady
    case noChild
    case failed
}
