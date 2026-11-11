import Foundation

public struct ImportResult: Equatable, Sendable {
    public let activityCounts: [ActivityType: Int]
    public let profiles: Int
    public let caregivers: Int
    public let skippedRows: Int

    public var totalActivities: Int { activityCounts.values.reduce(0, +) }

    public init(activityCounts: [ActivityType: Int], profiles: Int, caregivers: Int, skippedRows: Int) {
        self.activityCounts = activityCounts
        self.profiles = profiles
        self.caregivers = caregivers
        self.skippedRows = skippedRows
    }

    /// Message on the Import / Export screen; `source` is "Nara" or "Nestly".
    public func importScreenMessage(source: String) -> String {
        "Imported \(totalActivities) activities, \(profiles) profile(s), \(caregivers) caregiver(s) from \(source). Skipped \(skippedRows) row(s)."
    }

    /// Message on onboarding after a Nara import.
    public var onboardingMessage: String {
        "Imported \(totalActivities) activities for \(profiles) child profile(s) and \(caregivers) caregiver(s). Skipped \(skippedRows) unsupported row(s)."
    }
}

/// The repository surface the Nara importer writes through (Supabase in the app, fakes in tests).
public protocol NaraImportTarget: Sendable {
    func currentFamilyId() async throws -> String?
    func fetchProfiles() async throws -> [ProfileEntity]
    func fetchCaregivers(_ familyId: String) async throws -> [CaregiverEntity]
    func importProfile(_ profile: ProfileEntity) async throws
    func importCaregiver(_ caregiver: CaregiverEntity) async throws
    func importActivities(_ activities: [ActivityEntity]) async throws
}

/// Imports a Nara Baby export as a one-time load into the signed-in user's current family. Nara keys
/// are never used as database ids: everything is remapped with deterministic UUIDs (see `NaraIds`),
/// so importing the same file again updates the imported rows instead of duplicating them.
public struct NaraCsvImporter: Sendable {
    let target: NaraImportTarget
    let clock: @Sendable () -> EpochMs

    public init(target: NaraImportTarget, clock: @escaping @Sendable () -> EpochMs = nowMs) {
        self.target = target
        self.clock = clock
    }

    public func importData(_ data: Data) async throws -> ImportResult {
        let rows = try SpreadsheetReader.parseRecords(data)
        let records = rows.compactMap(NaraRowMapper.map)
        let naraProfiles = records.compactMap(\.asProfile)
        let naraActivities = records.compactMap(\.asActivity)
        if naraProfiles.isEmpty && naraActivities.isEmpty {
            // Dictionary order is random; show header columns in file order when we can.
            let columns = rows.first.map { first in
                (try? SpreadsheetReader.parseRows(data).first?.map(\.trimmed).filter { first[$0] != nil }) ?? Array(first.keys)
            }
            let columnText = columns.map { " (columns: \(Array($0.prefix(6)).joined(separator: ", ")))" } ?? ""
            throw ImportError("No recognizable Nara rows found in this file\(columnText). Make sure it's a Baby Nara export (.csv, .xls or .xlsx), not a different app's file.")
        }
        let now = clock()

        guard let familyId = try await target.currentFamilyId() else {
            throw ImportError("Create or join a family before importing from Nara.")
        }

        // Profiles: match existing children where possible, else create.
        var knownProfiles = try await target.fetchProfiles().filter { $0.familyId == familyId }
        var profileIdByKey: [String: String] = [:]

        for p in naraProfiles {
            let matched = NaraProfileMatcher.match(p.name, p.birthDate, knownProfiles)
            let id = matched?.id ?? NaraIds.profile(p.profileKey)
            profileIdByKey[p.profileKey] = id
            let merged = ProfileEntity(
                id: id,
                familyId: familyId,
                name: p.name,
                birthDate: p.birthDate ?? matched?.birthDate,
                adjustedBirthDate: p.adjustedBirthDate ?? matched?.adjustedBirthDate,
                sex: p.sex ?? matched?.sex,
                profileType: p.profileType,
                photoPath: matched?.photoPath,
                createdAt: matched?.createdAt ?? now,
                updatedAt: now,
                version: matched?.version ?? 1
            )
            try await target.importProfile(merged)
            if matched == nil { knownProfiles.append(merged) }
        }

        // Profiles referenced only by activities (no Profile row in the export).
        struct KeyName: Hashable { let key: String; let name: String }
        let referenced = naraActivities
            .compactMap { a in a.profileKey.map { KeyName(key: $0, name: a.profileName ?? "Baby") } }
            .distinctBy { $0 }
        for ref in referenced where profileIdByKey[ref.key] == nil {
            let matched = NaraProfileMatcher.match(ref.name, nil, knownProfiles)
            let id = matched?.id ?? NaraIds.profile(ref.key)
            profileIdByKey[ref.key] = id
            if matched == nil {
                let created = ProfileEntity(id: id, familyId: familyId, name: ref.name, profileType: .CHILD, createdAt: now, updatedAt: now)
                try await target.importProfile(created)
                knownProfiles.append(created)
            }
        }

        // Caregivers: reuse by normalized name, else create name-only rows.
        var caregiverIdByName: [String: String] = [:]
        for c in try await target.fetchCaregivers(familyId) {
            caregiverIdByName[NaraIds.normalizeName(c.name)] = c.id
        }
        let caregiverNames = naraActivities
            .flatMap { [$0.createdBy, $0.updatedBy].compactMap { $0 } }
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .distinctBy(NaraIds.normalizeName)
        for name in caregiverNames {
            let key = NaraIds.normalizeName(name)
            if caregiverIdByName[key] == nil {
                let caregiver = CaregiverEntity(id: NaraIds.caregiver(familyId, name), familyId: familyId, name: name, createdAt: now, updatedAt: now)
                try await target.importCaregiver(caregiver)
                caregiverIdByName[key] = caregiver.id
            }
        }
        func caregiverId(_ name: String?) -> String? {
            guard let t = name?.trimmed, !t.isEmpty else { return nil }
            return caregiverIdByName[NaraIds.normalizeName(t)]
        }

        // Activities: deterministic ids, target family, remapped references.
        try await target.importActivities(naraActivities.map { a in
            ActivityEntity(
                id: NaraIds.activity(a.activityKey),
                familyId: familyId,
                profileId: a.profileKey.flatMap { profileIdByKey[$0] },
                type: a.type,
                startTime: a.startTime,
                endTime: a.endTime,
                timeZone: a.timeZone,
                note: a.note,
                createdById: caregiverId(a.createdBy),
                updatedById: caregiverId(a.updatedBy),
                bottle: a.bottle,
                pump: a.pump,
                breastfeed: a.breastfeed,
                diaper: a.diaper,
                growth: a.growth,
                milestone: a.milestone,
                createdAt: a.startTime,
                updatedAt: now
            )
        })

        return ImportResult(
            activityCounts: Dictionary(grouping: naraActivities, by: \.type).mapValues(\.count),
            profiles: profileIdByKey.count,
            caregivers: caregiverNames.count,
            skippedRows: rows.count - records.count
        )
    }
}
