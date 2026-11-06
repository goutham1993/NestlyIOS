import Foundation
import Supabase

/// Personal interval reminders: RLS only shows the signed-in caregiver's own rows.
public struct ReminderRepository: Sendable {
    public let backend: Backend
    static let table = "reminder"

    public init(backend: Backend = .shared) { self.backend = backend }

    public func fetchMine() async throws -> [ReminderEntity] {
        let dtos: [ReminderDto] = try await backend.from(Self.table).select().is("deleted_at", value: nil).execute().value
        return try dtos.map { try $0.toEntity() }
    }

    /// PUMP reminders are parent-level (`profile_id` null); others belong to the child.
    public func getOrCreate(familyId: String, caregiverId: String, profileId: String, kind: ReminderKind) async throws -> ReminderEntity {
        let scopeProfile: String? = kind == .PUMP ? nil : profileId
        var q = backend.from(Self.table).select().eq("caregiver_id", value: caregiverId).eq("kind", value: kind.rawValue).is("deleted_at", value: nil)
        if let scopeProfile { q = q.eq("profile_id", value: scopeProfile) } else { q = q.is("profile_id", value: nil) }
        let found: [ReminderDto] = try await q.limit(1).execute().value
        if let first = found.first { return try first.toEntity() }
        let now = nowMs()
        let row = ReminderEntity(
            id: newUUID(), familyId: familyId, caregiverId: caregiverId, profileId: scopeProfile, kind: kind,
            intervalMinutes: ReminderLogic.defaultIntervalMinutes(kind), enabled: false, createdAt: now, updatedAt: now
        )
        try await backend.insert(Self.table, row.toDto())
        backend.bus.bump(.reminder)
        return row
    }

    @discardableResult
    public func update(_ reminder: ReminderEntity) async throws -> ReminderEntity {
        let fresh = try await backend.versionedUpdate(Self.table, reminder.toDto()).toEntity()
        backend.bus.bump(.reminder)
        return fresh
    }
}

public struct AppointmentRepository: Sendable {
    public let backend: Backend
    static let table = "appointment"

    public init(backend: Backend = .shared) { self.backend = backend }

    public func list(profileId: String) async throws -> [AppointmentEntity] {
        let dtos: [AppointmentDto] = try await backend.from(Self.table).select().eq("profile_id", value: profileId)
            .is("deleted_at", value: nil).order("starts_at", ascending: true).execute().value
        return try dtos.map { try $0.toEntity() }
    }

    /// Upcoming appointments with a reminder across all my families (notification scheduling).
    public func upcomingWithReminders(now: EpochMs = nowMs(), limit: Int = 50) async throws -> [AppointmentEntity] {
        let dtos: [AppointmentDto] = try await backend.from(Self.table).select().is("deleted_at", value: nil)
            .gte("starts_at", value: (now - 5 * 60_000).toIso())
            .not("reminder_lead_minutes", operator: .is, value: "null")
            .order("starts_at", ascending: true).limit(limit).execute().value
        return try dtos.map { try $0.toEntity() }
    }

    public func get(_ id: String) async throws -> AppointmentEntity? {
        let dtos: [AppointmentDto] = try await backend.from(Self.table).select().eq("id", value: id).is("deleted_at", value: nil).execute().value
        return try dtos.first?.toEntity()
    }

    /// Insert when `isNew`, else version-checked update.
    @discardableResult
    public func save(_ appointment: AppointmentEntity, isNew: Bool) async throws -> AppointmentEntity {
        var row = appointment
        row.updatedAt = nowMs()
        let saved: AppointmentEntity
        if isNew {
            row.version = 1
            try await backend.insert(Self.table, row.toDto())
            saved = row
        } else {
            saved = try await backend.versionedUpdate(Self.table, row.toDto()).toEntity()
        }
        backend.bus.bump(.appointment)
        return saved
    }

    public func delete(_ appointment: AppointmentEntity) async throws {
        try await backend.softDelete(Self.table, id: appointment.id, version: appointment.version)
        backend.bus.bump(.appointment)
    }
}

public struct NoteRepository: Sendable {
    public let backend: Backend
    static let table = "note"

    public init(backend: Backend = .shared) { self.backend = backend }

    public func list(profileId: String) async throws -> [NoteEntity] {
        let dtos: [NoteDto] = try await backend.from(Self.table).select().eq("profile_id", value: profileId)
            .is("deleted_at", value: nil).order("updated_at", ascending: false).execute().value
        return try dtos.map { try $0.toEntity() }
    }

    public func get(_ id: String) async throws -> NoteEntity? {
        let dtos: [NoteDto] = try await backend.from(Self.table).select().eq("id", value: id).is("deleted_at", value: nil).execute().value
        return try dtos.first?.toEntity()
    }

    @discardableResult
    public func save(_ note: NoteEntity, isNew: Bool) async throws -> NoteEntity {
        var row = note
        row.updatedAt = nowMs()
        let saved: NoteEntity
        if isNew {
            row.version = 1
            try await backend.insert(Self.table, row.toDto())
            saved = row
        } else {
            saved = try await backend.versionedUpdate(Self.table, row.toDto()).toEntity()
        }
        backend.bus.bump(.note)
        return saved
    }

    public func delete(_ note: NoteEntity) async throws {
        try await backend.softDelete(Self.table, id: note.id, version: note.version)
        backend.bus.bump(.note)
    }
}

/// All repositories over one backend.
public struct Repositories: Sendable {
    public static let shared = Repositories(backend: .shared)

    public let backend: Backend
    public let family: FamilyRepository
    public let activities: ActivityRepository
    public let reminders: ReminderRepository
    public let appointments: AppointmentRepository
    public let notes: NoteRepository

    public init(backend: Backend) {
        self.backend = backend
        family = FamilyRepository(backend: backend)
        activities = ActivityRepository(backend: backend)
        reminders = ReminderRepository(backend: backend)
        appointments = AppointmentRepository(backend: backend)
        notes = NoteRepository(backend: backend)
    }

    public var prefs: Preferences { backend.prefs }
    public var photos: PhotoStore { activities.photos }
}
