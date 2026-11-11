import Foundation
import Supabase

public struct FamilyRepository: Sendable {
    public let backend: Backend
    public let photos: PhotoStore
    private var prefs: Preferences { backend.prefs }

    public init(backend: Backend = .shared) {
        self.backend = backend
        photos = PhotoStore(backend: backend)
    }

    // MARK: Reads

    /// Non-deleted profiles in all my families, oldest first.
    public func fetchProfiles() async throws -> [ProfileEntity] {
        let dtos: [ProfileDto] = try await backend.from("profile").select().is("deleted_at", value: nil)
            .order("created_at", ascending: true).execute().value
        return try dtos.map { try $0.toEntity() }
    }

    public func fetchFamilies() async throws -> [FamilyEntity] {
        let dtos: [FamilyDto] = try await backend.from("family").select().is("deleted_at", value: nil)
            .order("created_at", ascending: true).execute().value
        return try dtos.map { try $0.toEntity() }
    }

    public func fetchCaregivers(familyId: String) async throws -> [CaregiverEntity] {
        let dtos: [CaregiverDto] = try await backend.from("caregiver").select().eq("family_id", value: familyId)
            .is("deleted_at", value: nil).order("name", ascending: true).execute().value
        return try dtos.map { try $0.toEntity() }
    }

    public func fetchAllCaregivers(familyIds: [String]) async throws -> [CaregiverEntity] {
        guard !familyIds.isEmpty else { return [] }
        let dtos: [CaregiverDto] = try await backend.from("caregiver").select().in("family_id", values: familyIds)
            .is("deleted_at", value: nil).order("name", ascending: true).execute().value
        return try dtos.map { try $0.toEntity() }
    }

    /// Stored selection if still present, else the first profile.
    public func selectedProfile(in profiles: [ProfileEntity]) -> ProfileEntity? {
        profiles.first { $0.id == prefs.selectedProfileId } ?? profiles.first
    }

    /// Mine (by user id), else the stored choice, else the first.
    public func currentCaregiver(in caregivers: [CaregiverEntity]) -> CaregiverEntity? {
        if let uid = backend.currentUserId, let mine = caregivers.first(where: { $0.userId == uid }) { return mine }
        return caregivers.first { $0.id == prefs.currentCaregiverId } ?? caregivers.first
    }

    public func selectedProfile() async throws -> ProfileEntity? { selectedProfile(in: try await fetchProfiles()) }

    public func currentCaregiverId(familyId: String) async throws -> String? {
        currentCaregiver(in: try await fetchCaregivers(familyId: familyId))?.id
    }

    /// Selected profile's family, else the current caregiver's family (so a family joined by invite wins
    /// over the empty one sign-up created), else the first family I can see.
    public func currentFamilyId() async throws -> String? {
        if let profile = try await selectedProfile() { return profile.familyId }
        let families = try await fetchFamilies()
        if families.count > 1, let caregiverId = prefs.currentCaregiverId,
           let mine = try await fetchAllCaregivers(familyIds: families.map(\.id)).first(where: { $0.id == caregiverId }) {
            return mine.familyId
        }
        return families.first?.id
    }

    // MARK: Writes

    @discardableResult
    public func createFamily(caregiverName: String) async throws -> String {
        guard let uid = backend.currentUserId else { throw ImportError("Sign in first.") }
        let now = nowMs()
        let family = FamilyEntity(id: newUUID(), name: nil, createdAt: now, updatedAt: now)
        try await backend.insert("family", family.toDto())
        let caregiver = CaregiverEntity(
            id: newUUID(), familyId: family.id, name: caregiverName.trimmedNilIfEmpty ?? "Caregiver",
            userId: uid, role: CaregiverRole.OWNER.rawValue, createdAt: now, updatedAt: now
        )
        try await backend.insert("caregiver", caregiver.toDto())
        prefs.setCurrentCaregiver(caregiver.id)
        backend.bus.bump(.family, .caregiver)
        return family.id
    }

    /// Reuses the family I already have (iOS fix vs Android, which orphaned one); only creates a
    /// family when there is none at all. A staged local `photoPath` is uploaded before insert.
    @discardableResult
    public func addChild(name: String, sex: Sex?, birthDate: LocalDate?, caregiverName: String, photoPath: String? = nil) async throws -> ProfileEntity {
        let now = nowMs()
        let familyId: String
        if let existing = try await currentFamilyId() {
            familyId = existing
            if let cgName = caregiverName.trimmedNilIfEmpty {
                let caregivers = try await fetchCaregivers(familyId: familyId)
                if !caregivers.contains(where: { $0.name.lowercased() == cgName.lowercased() }) {
                    try await backend.insert("caregiver", CaregiverEntity(id: newUUID(), familyId: familyId, name: cgName, createdAt: now, updatedAt: now).toDto())
                }
            }
        } else {
            familyId = try await createFamily(caregiverName: caregiverName)
        }
        let id = newUUID()
        let storedPhoto = try await storedProfilePhoto(photoPath, familyId: familyId, profileId: id)
        let profile = ProfileEntity(id: id, familyId: familyId, name: name.trimmed, birthDate: birthDate, sex: sex, profileType: .CHILD, photoPath: storedPhoto, createdAt: now, updatedAt: now)
        do {
            try await backend.insert("profile", profile.toDto())
        } catch {
            if let storedPhoto, photoPath.map(PhotoStore.isLocal) == true {
                try? await photos.deleteProfile(path: storedPhoto)
            }
            throw error
        }
        prefs.setSelectedProfile(profile.id)
        backend.bus.bump(.profile, .caregiver, .family)
        return profile
    }

    public func joinWithInvite(code: String, name: String) async throws {
        let results: [AcceptInviteResult] = try await backend.client
            .rpc("accept_family_invite", params: AcceptInviteParams(code: code.trimmed, caregiverName: name.trimmed))
            .execute().value
        guard let result = results.first else { throw ImportError("Invite is invalid or expired") }
        prefs.setCurrentCaregiver(result.caregiverId)
        backend.bus.bump(.family, .caregiver, .profile)
    }

    public func createInvite(familyId: String) async throws -> String {
        struct NewInvite: Encodable, Sendable {
            let id: String
            let family_id: String
        }
        struct CodeOnly: Decodable, Sendable { let code: String }
        let id = newUUID()
        try await backend.insert("family_invite", NewInvite(id: id, family_id: familyId))
        let rows: [CodeOnly] = try await backend.from("family_invite").select("code").eq("id", value: id).execute().value
        guard let code = rows.first?.code else { throw ImportError("Couldn't create an invite code.") }
        return code
    }

    @discardableResult
    public func updateChild(_ profile: ProfileEntity) async throws -> ProfileEntity {
        let previous = try await get(profileId: profile.id)?.photoPath
        var row = profile
        let incoming = row.photoPath
        row.photoPath = try await storedProfilePhoto(incoming, familyId: row.familyId, profileId: row.id)
        let uploaded = (incoming.map(PhotoStore.isLocal) ?? false) ? row.photoPath : nil
        do {
            let fresh = try await backend.versionedUpdate("profile", row.toDto()).toEntity()
            if let previous, previous != fresh.photoPath {
                try? await photos.deleteProfile(path: previous)
            }
            prefs.setSelectedProfile(profile.id)
            backend.bus.bump(.profile)
            return fresh
        } catch {
            if let uploaded { try? await photos.deleteProfile(path: uploaded) }
            throw error
        }
    }

    /// Uploads a staged JPEG. A remote path or nil is stored as given.
    private func storedProfilePhoto(_ path: String?, familyId: String, profileId: String) async throws -> String? {
        guard let path else { return nil }
        guard PhotoStore.isLocal(path) else { return path }
        return try await photos.uploadProfile(localPath: path, familyId: familyId, profileId: profileId)
    }

    public func get(profileId: String) async throws -> ProfileEntity? {
        let dtos: [ProfileDto] = try await backend.from("profile").select().eq("id", value: profileId).execute().value
        return try dtos.first?.toEntity()
    }

    /// Name-only member; returns the existing caregiver when the name is taken.
    @discardableResult
    public func addCaregiver(familyId: String, name: String) async throws -> CaregiverEntity {
        let trimmed = name.trimmed
        if let existing = try await fetchCaregivers(familyId: familyId).first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            return existing
        }
        let now = nowMs()
        let caregiver = CaregiverEntity(id: newUUID(), familyId: familyId, name: trimmed, createdAt: now, updatedAt: now)
        try await backend.insert("caregiver", caregiver.toDto())
        backend.bus.bump(.caregiver)
        return caregiver
    }

    /// Anyone in the family can remove a name-only caregiver. Only an owner can remove another
    /// signed-in member (the database trigger enforces that). You cannot remove yourself, and the
    /// last caregiver in the family stays.
    public func canRemove(_ caregiver: CaregiverEntity, me: CaregiverEntity?, caregiverCount: Int) -> Bool {
        guard caregiverCount > 1, !isSignedInUser(caregiver) else { return false }
        if caregiver.userId == nil { return true }
        return me?.role == CaregiverRole.OWNER.rawValue
    }

    /// Version-checked soft delete. Past entries that name this caregiver are left in place.
    public func removeCaregiver(_ caregiver: CaregiverEntity) async throws {
        let caregivers = try await fetchCaregivers(familyId: caregiver.familyId)
        guard let fresh = caregivers.first(where: { $0.id == caregiver.id }) else {
            if prefs.currentCaregiverId == caregiver.id { prefs.setCurrentCaregiver(nil) }
            backend.bus.bump(.caregiver)
            return
        }
        let me = currentCaregiver(in: caregivers)
        guard canRemove(fresh, me: me, caregiverCount: caregivers.count) else {
            if isSignedInUser(fresh) {
                throw ImportError("You can't remove yourself from the family.")
            }
            if caregivers.count <= 1 {
                throw ImportError("A family needs at least one caregiver.")
            }
            throw ImportError("Only the family owner can remove a signed-in caregiver.")
        }
        try await backend.softDelete("caregiver", id: fresh.id, version: fresh.version)
        if prefs.currentCaregiverId == fresh.id {
            prefs.setCurrentCaregiver(nil)
        }
        backend.bus.bump(.caregiver)
    }

    public func setCurrentCaregiver(_ id: String) {
        prefs.setCurrentCaregiver(id)
        backend.bus.bump(.caregiver)
    }

    private func isSignedInUser(_ caregiver: CaregiverEntity) -> Bool {
        guard let uid = backend.currentUserId, let theirs = caregiver.userId else { return false }
        return uid.caseInsensitiveCompare(theirs) == .orderedSame
    }

    // MARK: Import

    public func upsertFamilies(_ rows: [FamilyEntity]) async throws {
        try await backend.upsert("family", rows.map { $0.toDto() })
    }

    /// Imported caregivers are always name-only.
    public func upsertCaregivers(_ rows: [CaregiverEntity]) async throws {
        try await backend.upsert("caregiver", rows.map { var c = $0; c.userId = nil; return c.toDto() })
    }

    public func upsertProfiles(_ rows: [ProfileEntity]) async throws {
        try await backend.upsert("profile", rows.map { $0.toDto() })
    }

    #if DEBUG
    /// Hard-deletes everything in the family (debug builds only).
    public func clearFamilyData(familyId: String) async throws {
        for table in ["activity", "reminder", "appointment_question", "appointment", "note", "family_invite", "profile"] {
            try await backend.from(table).delete().eq("family_id", value: familyId).execute()
        }
        try await backend.from("family").delete().eq("id", value: familyId).execute()
        try await backend.from("caregiver").delete().eq("family_id", value: familyId).execute()
        prefs.clearSelection()
        backend.bus.bumpAll()
    }
    #endif
}
