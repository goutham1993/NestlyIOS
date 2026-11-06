import NestlyCore
import Observation
import SwiftUI

/// Profiles, families and caregivers for the signed-in user, refetched on every relevant tick.
/// Restarts whenever the signed-in user changes; never fetches anonymously (spec §4.2).
@MainActor
@Observable
final class FamilyStore {
    private(set) var profiles: [ProfileEntity]?
    private(set) var families: [FamilyEntity]?
    private(set) var caregivers: [CaregiverEntity] = []

    @ObservationIgnored let repos: Repositories
    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var userId: String?

    init(repos: Repositories, auth: AuthModel) {
        self.repos = repos
        self.auth = auth
    }

    var selectedProfile: ProfileEntity? {
        guard let profiles else { return nil }
        _ = repos.prefs.selectedProfileId
        return repos.family.selectedProfile(in: profiles)
    }

    var currentCaregiver: CaregiverEntity? {
        _ = repos.prefs.currentCaregiverId
        return repos.family.currentCaregiver(in: caregivers)
    }

    var hasFamily: Bool? { families.map { !$0.isEmpty } }

    /// Selected profile's family, else the first family.
    var currentFamilyId: String? { selectedProfile?.familyId ?? families?.first?.id }

    func start() {
        observeAuth()
    }

    private func observeAuth() {
        withObservationTracking {
            _ = auth.status
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.authChanged()
                self?.observeAuth()
            }
        }
        authChanged()
    }

    private func authChanged() {
        let uid = auth.status.userId
        guard uid != userId else { return }
        userId = uid
        tasks.forEach { $0.cancel() }
        tasks = []
        profiles = nil
        families = nil
        caregivers = []
        guard uid != nil else { return }
        let repos = repos
        tasks.append(Task { [weak self] in
            for await value in refetch([.profile], fetch: { try await repos.family.fetchProfiles() }) {
                self?.profiles = value
                self?.afterProfilesChanged()
            }
        })
        tasks.append(Task { [weak self] in
            for await value in refetch([.family], fetch: { try await repos.family.fetchFamilies() }) {
                self?.families = value
                self?.afterProfilesChanged()
            }
        })
        tasks.append(Task { [weak self] in
            let stream = refetch([.caregiver, .profile, .family]) { () async throws -> [CaregiverEntity] in
                guard let familyId = try await repos.family.currentFamilyId() else { return [] }
                return try await repos.family.fetchCaregivers(familyId: familyId)
            }
            for await value in stream { self?.caregivers = value }
        })
        AppModel.shared.scheduleReschedule()
    }

    private func afterProfilesChanged() {
        if let familyId = currentFamilyId { RealtimeSync.shared.start(familyId: familyId) }
        TimerControl.setChildName(selectedProfile?.name)
    }

    /// Selecting a child (editing/saving it in Family, or adding one).
    func select(_ profile: ProfileEntity) {
        repos.prefs.setSelectedProfile(profile.id)
        repos.backend.bus.bump(.profile)
    }
}
