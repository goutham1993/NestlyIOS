import NestlyCore
import Observation
import SwiftUI

enum AppTab: Hashable { case activity, history, trends, account }

/// Pushed routes (spec §9.3).
enum Route: Hashable {
    case growth(GrowthMetric)
    case trend(TrendMetric, TrendsWindow)
    case editActivities
    case milestones
    case vaccinations
    case reminders
    case appointments
    case appointment(id: String?)
    case notes
    case note(id: String?)
    case family
    case settings
    case units
    case email
    case communication
    case subscription
    case help
    case importExport
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let repos = Repositories.shared
    let auth = AuthModel.shared
    let family: FamilyStore
    var prefs: Preferences { repos.prefs }

    var tab: AppTab = .activity
    var paths: [AppTab: [Route]] = [:]
    var entryRequest: EntryRequest?
    var showNightstand = false
    var toast: String?

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var rescheduleTask: Task<Void, Never>?

    private init() {
        family = FamilyStore(repos: .shared, auth: .shared)
    }

    func start() {
        auth.start()
        family.start()
        RealtimeSync.shared.onChange = { table in
            guard [.activity, .reminder, .appointment].contains(table) else { return }
            Task { @MainActor in AppModel.shared.scheduleReschedule(debounce: 2) }
        }
    }

    func path(_ tab: AppTab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    func push(_ route: Route) {
        paths[tab, default: []].append(route)
    }

    func openEntry(_ request: EntryRequest) {
        entryRequest = request
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }

    /// Reschedules notifications in the background, coalescing bursts of changes.
    func scheduleReschedule(debounce: Double = 0) {
        rescheduleTask?.cancel()
        let repos = repos
        rescheduleTask = Task.detached {
            if debounce > 0 { try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000)) }
            if Task.isCancelled { return }
            await NotificationScheduler.rescheduleAll(repos: repos)
        }
    }

    /// `nestly://entry/{EntryKind}`, `nestly://appointment/{id}`, `nestly://nightstand`.
    func open(_ url: URL) {
        guard url.scheme == "nestly" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.host {
        case "entry":
            if let raw = parts.first, let kind = EntryKind(rawValue: raw.uppercased()) {
                tab = .activity
                entryRequest = .new(kind: kind)
            }
        case "appointment":
            if let id = parts.first { openAppointment(id) }
        case "nightstand":
            showNightstand = true
        default:
            tab = .activity
        }
    }

    func openAppointment(_ id: String) {
        tab = .activity
        paths[.activity] = [.appointments, .appointment(id: id)]
    }

    func quickBottleFromShortcut() {
        showToast(QuickBottleResult.alreadySaving.message(prefs.units))
        let repos = repos
        Task {
            let result = await QuickBottleLog.run(repos: repos)
            showToast(result.message(repos.prefs.units))
        }
    }

    func signOut() async {
        RealtimeSync.shared.stop()
        NotificationScheduler.cancelAll()
        LiveTimerActivities.endAll()
        prefs.clearSelection()
        paths = [:]
        tab = .activity
        await auth.signOut()
    }
}
