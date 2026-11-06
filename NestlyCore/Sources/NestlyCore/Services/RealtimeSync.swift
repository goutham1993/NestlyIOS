import Foundation
import Supabase

/// One realtime channel per family (`nestly-{familyId}`). Payloads are ignored: every change
/// just bumps that table's refresh tick. Subscribes with exponential backoff (2 s → 60 s).
public final class RealtimeSync: @unchecked Sendable {
    public static let shared = RealtimeSync(backend: .shared)

    private let backend: Backend
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var familyId: String?
    /// Called for every realtime change (the app debounces notification rescheduling on it).
    public var onChange: (@Sendable (Table) -> Void)?

    public init(backend: Backend) { self.backend = backend }

    private static let tables: [(Table, String)] = [
        (.activity, "activity"), (.profile, "profile"), (.caregiver, "caregiver"), (.family, "family"),
        (.reminder, "reminder"), (.appointment, "appointment"), (.appointmentQuestion, "appointment_question"), (.note, "note"),
    ]

    public func start(familyId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard familyId != self.familyId || task == nil else { return }
        task?.cancel()
        self.familyId = familyId
        let onChange = onChange
        task = Task { [backend] in
            var delay: Double = 2
            while !Task.isCancelled {
                let channel = backend.client.channel("nestly-\(familyId)")
                var tokens: [RealtimeSubscription] = []
                for (table, name) in Self.tables {
                    let filter: RealtimePostgresFilter = table == .family ? .eq("id", value: familyId) : .eq("family_id", value: familyId)
                    tokens.append(channel.onPostgresChange(AnyAction.self, schema: "public", table: name, filter: filter) { _ in
                        backend.bus.bump(table)
                        onChange?(table)
                    })
                }
                do {
                    let joined = try await withTimeout(seconds: 15) { try await channel.subscribeWithError(); return true }
                    if joined == true {
                        delay = 2
                        backend.bus.bumpAll()
                        for await status in channel.statusChange where status == .unsubscribed { break }
                    }
                } catch {}
                tokens.removeAll()
                await backend.client.removeChannel(channel)
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay = min(60, delay * 2)
            }
        }
    }

    public func stop() {
        lock.lock()
        let running = task
        task = nil
        familyId = nil
        lock.unlock()
        running?.cancel()
        Task { [backend] in await backend.client.removeAllChannels() }
    }
}
