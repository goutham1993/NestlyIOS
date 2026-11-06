import Foundation
import Observation

/// Tables whose changes drive refetches.
public enum Table: String, CaseIterable, Sendable {
    case activity, profile, caregiver, family, reminder, appointment, appointmentQuestion, note
}

/// One monotonically increasing tick per table. Every local write, realtime event, foreground,
/// reconnect and manual retry bumps ticks; refetch streams listen and reload.
public final class RefreshBus: @unchecked Sendable {
    public static let shared = RefreshBus()

    private let lock = NSLock()
    private var ticks: [Table: Int] = [:]
    private var listeners: [UUID: (tables: Set<Table>, continuation: AsyncStream<Void>.Continuation)] = [:]

    public init() {}

    public func tick(_ table: Table) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return ticks[table] ?? 0
    }

    public func bump(_ tables: Table...) { bump(Set(tables)) }

    public func bumpAll() { bump(Set(Table.allCases)) }

    public func bump(_ tables: Set<Table>) {
        lock.lock()
        for t in tables { ticks[t, default: 0] += 1 }
        let targets = listeners.values.filter { !$0.tables.isDisjoint(with: tables) }.map(\.continuation)
        lock.unlock()
        for c in targets { c.yield() }
    }

    /// A change signal for any of `tables`. Bursts coalesce: at most one pending signal is buffered.
    public func changes(_ tables: Set<Table>) -> AsyncStream<Void> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        lock.lock()
        listeners[id] = (tables, continuation)
        lock.unlock()
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.listeners[id] = nil
            self.lock.unlock()
        }
        return stream
    }
}

/// Global "couldn't reach the server" banner state.
@MainActor
@Observable
public final class DataErrors {
    public static let shared = DataErrors()
    public static let defaultMessage = "Couldn't reach the server. Check your connection."

    public private(set) var message: String?

    public init() {}

    public func report(_ error: Error? = nil) {
        message = Self.defaultMessage
    }

    public func clear() {
        message = nil
    }
}

/// A version-checked update matched no row: someone else changed it first.
public struct ConflictError: LocalizedError, Equatable {
    public static let message = "This entry was changed by someone else. Showing the latest version."
    public init() {}
    public var errorDescription: String? { Self.message }
}

/// Fetches once immediately, then again whenever any of `tables` ticks.
/// - A tick that lands while a fetch is in flight does not cancel it; one more fetch follows.
/// - On failure the error is reported and the last good value is re-emitted; if the very first
///   fetch fails nothing is emitted, so consumers stay in their loading state.
public func refetch<T: Sendable>(
    _ tables: [Table],
    bus: RefreshBus = .shared,
    errors: DataErrors? = nil,
    fetch: @escaping @Sendable () async throws -> T
) -> AsyncStream<T> {
    AsyncStream { continuation in
        // Subscribe before the first fetch so ticks during it are not missed.
        let changes = bus.changes(Set(tables))
        let task = Task {
            let sink = await MainActor.run { errors ?? DataErrors.shared }
            var last: T?
            var iterator = changes.makeAsyncIterator()
            while !Task.isCancelled {
                do {
                    let value = try await fetch()
                    last = value
                    continuation.yield(value)
                    await sink.clear()
                } catch is CancellationError {
                    break
                } catch {
                    if Task.isCancelled { break }
                    await sink.report(error)
                    if let last { continuation.yield(last) }
                }
                guard await iterator.next() != nil else { break }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
