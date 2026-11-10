import Foundation
import Supabase

public struct ActivityRepository: Sendable {
    public let backend: Backend
    public let photos: PhotoStore
    static let table = "activity"

    public init(backend: Backend = .shared) {
        self.backend = backend
        photos = PhotoStore(backend: backend)
    }

    private func base(_ familyId: String) -> PostgrestFilterBuilder {
        backend.from(Self.table).select().eq("family_id", value: familyId).is("deleted_at", value: nil)
    }

    /// Activities of a child plus the parent's (profile-less) pump rows.
    private func scoped(_ familyId: String, _ profileId: String?) -> PostgrestFilterBuilder {
        let q = base(familyId)
        guard let profileId, !profileId.isBlank else { return q.is("profile_id", value: nil) }
        return q.or("profile_id.eq.\(profileId),profile_id.is.null")
    }

    private func entities(_ dtos: [ActivityDto]) throws -> [ActivityEntity] { try dtos.map { try $0.toEntity() } }

    /// `start_time ∈ [from, to)`, newest first.
    public func range(familyId: String, profileId: String?, from: EpochMs, to: EpochMs) async throws -> [ActivityEntity] {
        let fromIso = from.toIso(), toIso = to.toIso()
        let dtos: [ActivityDto] = try await backend.fetchAll { a, b in
            scoped(familyId, profileId).gte("start_time", value: fromIso).lt("start_time", value: toIso)
                .order("start_time", ascending: false).range(from: a, to: b)
        }
        return try entities(dtos)
    }

    /// Every row of `types` for the child (growth charts, milestones, vaccines).
    public func ofTypes(familyId: String, profileId: String?, _ types: [ActivityType]) async throws -> [ActivityEntity] {
        let raw = types.map(\.rawValue)
        let dtos: [ActivityDto] = try await backend.fetchAll { a, b in
            scoped(familyId, profileId).in("type", values: raw).order("start_time", ascending: false).range(from: a, to: b)
        }
        return try entities(dtos)
    }

    /// Latest row of the types. A blank profile matches only `profile_id IS NULL`.
    public func latestOf(familyId: String, profileId: String?, _ types: [ActivityType]) async throws -> ActivityEntity? {
        var q = base(familyId).in("type", values: types.map(\.rawValue))
        if let profileId, !profileId.isBlank { q = q.eq("profile_id", value: profileId) } else { q = q.is("profile_id", value: nil) }
        let dtos: [ActivityDto] = try await q.order("start_time", ascending: false).limit(1).execute().value
        return try dtos.first?.toEntity()
    }

    public func getLatest(familyId: String, profileId: String?, _ type: ActivityType) async throws -> ActivityEntity? {
        try await latestOf(familyId: familyId, profileId: type == .PUMP ? nil : profileId, [type])
    }

    /// Latest feed that should move the milk / FEED reminder clock (bottle, breastfeed, or
    /// solids marked as a milk replacement). Skips solids that keep the milk schedule.
    public func latestFeedForSchedule(familyId: String, profileId: String) async throws -> ActivityEntity? {
        let types = ReminderLogic.typesFor(.FEED).map(\.rawValue)
        let dtos: [ActivityDto] = try await base(familyId)
            .eq("profile_id", value: profileId)
            .in("type", values: types)
            .order("start_time", ascending: false)
            .limit(30)
            .execute().value
        return try dtos.lazy.map { try $0.toEntity() }.first { ReminderLogic.resetsFeedSchedule($0) }
    }

    public func get(_ id: String) async throws -> ActivityEntity? {
        let dtos: [ActivityDto] = try await backend.from(Self.table).select().eq("id", value: id).is("deleted_at", value: nil).execute().value
        return try dtos.first?.toEntity()
    }

    public func comboRows(_ groupId: String) async throws -> [ActivityEntity] {
        let dtos: [ActivityDto] = try await backend.from(Self.table).select()
            .eq("combo_group_id", value: groupId).is("deleted_at", value: nil)
            .order("start_time", ascending: true).execute().value
        return try entities(dtos)
    }

    /// Inserts new rows, version-checks updates of existing ones, uploads local photos first and
    /// soft-deletes `removed` (the dropped half of an edited combo).
    public func saveAll(_ rows: [ActivityEntity], existing: [ActivityEntity] = [], removed: [ActivityEntity] = [], now: EpochMs = nowMs()) async throws {
        let existingById = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for var row in rows {
            if let local = row.photoUri, PhotoStore.isLocal(local) {
                row.photoUri = try await photos.upload(localPath: local, familyId: row.familyId, activityId: row.id)
            }
            row.updatedAt = now
            if let old = existingById[row.id] {
                var dto = row.toDto()
                dto.version = old.version
                try await backend.versionedUpdate(Self.table, dto, now: now)
            } else {
                var dto = row.toDto()
                dto.version = 1
                try await backend.insert(Self.table, dto)
            }
        }
        for row in removed {
            try await backend.softDelete(Self.table, id: row.id, version: row.version, now: now)
        }
        backend.bus.bump(.activity)
    }

    public func delete(_ row: ActivityEntity) async throws {
        try await backend.softDelete(Self.table, id: row.id, version: row.version)
        backend.bus.bump(.activity)
    }

    public func fetchCountsByType(familyId: String) async throws -> [ActivityType: Int] {
        let rows: [TypeOnlyDto] = try await backend.fetchAll { a, b in
            backend.from(Self.table).select("type").eq("family_id", value: familyId).is("deleted_at", value: nil)
                .order("id").range(from: a, to: b)
        }
        return Dictionary(grouping: rows, by: \.type).mapValues(\.count)
    }

    /// Active activities of the families, oldest first (export).
    public func exportAll(familyIds: [String]) async throws -> [ActivityEntity] {
        guard !familyIds.isEmpty else { return [] }
        let dtos: [ActivityDto] = try await backend.fetchAll { a, b in
            backend.from(Self.table).select().in("family_id", values: familyIds).is("deleted_at", value: nil)
                .order("start_time", ascending: true).order("id").range(from: a, to: b)
        }
        return try entities(dtos)
    }

    public func upsert(_ rows: [ActivityEntity]) async throws {
        try await backend.upsert(Self.table, rows.map { $0.toDto() })
        backend.bus.bump(.activity)
    }
}
