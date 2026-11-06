import Foundation

/// Nestly CSV export/import and the Nara import, against the signed-in user's data (spec §19).
public struct DataTransfer: Sendable {
    public let repos: Repositories

    public init(repos: Repositories = .shared) { self.repos = repos }

    public struct ExportResult: Sendable {
        public let csv: String
        public let filename: String
        public let activities: Int
        public let profiles: Int
        public let caregivers: Int

        public var message: String {
            "Exported \(activities) activities, \(profiles) profile(s), \(caregivers) caregiver(s)."
        }
    }

    public func exportCsv(today: LocalDate = .today()) async throws -> ExportResult {
        let families = try await repos.family.fetchFamilies()
        let ids = families.map(\.id)
        let caregivers = try await repos.family.fetchAllCaregivers(familyIds: ids)
        let profiles = try await repos.family.fetchProfiles()
        let activities = try await repos.activities.exportAll(familyIds: ids)
        let csv = NestlyCsv.document(families: families, caregivers: caregivers, profiles: profiles, activities: activities)
        return ExportResult(csv: csv, filename: "nestly_export_\(today).csv", activities: activities.count, profiles: profiles.count, caregivers: caregivers.count)
    }

    /// Upserts every record; caregivers are forced name-only.
    public func importNestly(_ data: Data, now: EpochMs = nowMs()) async throws -> ImportResult {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw ImportError("Could not open the selected file")
        }
        var families: [FamilyEntity] = []
        var caregivers: [CaregiverEntity] = []
        var profiles: [ProfileEntity] = []
        var activities: [ActivityEntity] = []
        var skipped = 0
        for row in CsvParser.parseRecords(text) {
            do {
                switch row["record"] {
                case "FAMILY": families.append(try NestlyCsv.parseFamily(row, now: now))
                case "CAREGIVER": caregivers.append(try NestlyCsv.parseCaregiver(row, now: now))
                case "PROFILE": profiles.append(try NestlyCsv.parseProfile(row, now: now))
                case "ACTIVITY": activities.append(try NestlyCsv.parseActivity(row, now: now))
                default: skipped += 1
                }
            } catch {
                skipped += 1
            }
        }
        try await repos.family.upsertFamilies(families)
        try await repos.family.upsertCaregivers(caregivers)
        try await repos.family.upsertProfiles(profiles)
        try await repos.activities.upsert(activities)
        repos.backend.bus.bumpAll()
        return ImportResult(
            activityCounts: Dictionary(grouping: activities, by: \.type).mapValues(\.count),
            profiles: profiles.count, caregivers: caregivers.count, skippedRows: skipped
        )
    }

    public func importNara(_ data: Data) async throws -> ImportResult {
        let result = try await NaraCsvImporter(target: NaraTarget(repos: repos)).importData(data)
        repos.backend.bus.bumpAll()
        return result
    }
}

struct NaraTarget: NaraImportTarget {
    let repos: Repositories

    func currentFamilyId() async throws -> String? { try await repos.family.currentFamilyId() }
    func fetchProfiles() async throws -> [ProfileEntity] { try await repos.family.fetchProfiles() }
    func fetchCaregivers(_ familyId: String) async throws -> [CaregiverEntity] { try await repos.family.fetchCaregivers(familyId: familyId) }
    func importProfile(_ profile: ProfileEntity) async throws { try await repos.family.upsertProfiles([profile]) }
    func importCaregiver(_ caregiver: CaregiverEntity) async throws { try await repos.family.upsertCaregivers([caregiver]) }
    func importActivities(_ activities: [ActivityEntity]) async throws { try await repos.activities.upsert(activities) }
}
