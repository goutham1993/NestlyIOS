import NestlyCore
import SwiftUI

/// Auth → family → tabs gate (spec §9.1), plus the global overlays.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    private var errors: DataErrors { .shared }

    var body: some View {
        @Bindable var app = app
        content
            .overlay(alignment: .bottom) {
                if let toast = app.toast {
                    ToastView(text: toast)
                        .padding(.bottom, 90)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onTapGesture { app.toast = nil }
                }
            }
            .animation(.easeInOut, value: app.toast)
            .sheet(item: $app.entryRequest) { request in
                EntrySheet(request: request)
                    .environment(app)
                    .environment(family)
                    .environment(app.prefs)
            }
            .fullScreenCover(isPresented: $app.showNightstand) {
                NightstandView()
                    .environment(app)
                    .environment(app.prefs)
            }
    }

    @ViewBuilder private var content: some View {
        switch app.auth.status {
        case .loading:
            LoadingView(text: "Loading…")
        case .signedOut:
            AuthView()
        case .signedIn:
            if let profiles = family.profiles {
                if !profiles.isEmpty {
                    MainTabs()
                } else if let hasFamily = family.hasFamily {
                    OnboardingView(hasFamily: hasFamily)
                } else {
                    LoadingView(text: "Loading your family…")
                }
            } else if let message = errors.message {
                ErrorScreen(message: message) { app.repos.backend.bus.bumpAll() }
            } else {
                LoadingView(text: "Loading your family…")
            }
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            tabStack(.activity) { ActivityTab() }
                .tabItem { Label("Activity", systemImage: "square.grid.2x2") }
                .tag(AppTab.activity)
            tabStack(.history) { HistoryTab() }
                .tabItem { Label("History", systemImage: "calendar") }
                .tag(AppTab.history)
            tabStack(.trends) { TrendsTab() }
                .tabItem { Label("Trends", systemImage: "chart.bar") }
                .tag(AppTab.trends)
            tabStack(.account) { AccountTab() }
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(AppTab.account)
        }
        .safeAreaInset(edge: .top, spacing: 0) { ErrorBanner() }
    }

    private func tabStack<Content: View>(_ tab: AppTab, @ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack(path: app.path(tab)) {
            content()
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case let .growth(metric): GrowthView(initialMetric: metric)
        case let .trend(metric, window): TrendDetailView(metric: metric, initialWindow: window)
        case .editActivities: EditActivitiesView()
        case .milestones: MilestonesView()
        case .vaccinations: VaccinationsView()
        case .reminders: RemindersView()
        case .appointments: AppointmentsView()
        case let .appointment(id): AppointmentDetailView(appointmentId: id)
        case .notes: NotesView()
        case let .note(id): NoteDetailView(noteId: id)
        case .family: FamilyView()
        case .settings: SettingsView()
        case .units: UnitsView()
        case .email: EmailView()
        case .communication: CommunicationView()
        case .subscription: SubscriptionView()
        case .help: HelpView()
        case .importExport: ImportExportView()
        }
    }
}

/// Global "couldn't reach the server" banner with Retry (spec §4.3).
struct ErrorBanner: View {
    @Environment(AppModel.self) private var app
    private var errors: DataErrors { .shared }

    var body: some View {
        if let message = errors.message {
            HStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                Text(message).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                Button("Retry") { app.repos.backend.bus.bumpAll() }.font(.footnote.bold())
                Button { errors.clear() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(Color.red.opacity(0.9))
        }
    }
}

struct LoadingView: View {
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorScreen: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Couldn't reach Nestly").font(.title2.bold())
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Retry", action: retry).buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: Capsule())
            .shadow(radius: 4)
            .padding(.horizontal, 24)
    }
}
