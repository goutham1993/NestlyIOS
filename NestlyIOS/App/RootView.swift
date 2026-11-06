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
            .animation(.snappy, value: app.toast)
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
            HStack(spacing: Space.m) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.critical)
                Text(message).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                Button("Retry") { app.repos.backend.bus.bumpAll() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.critical)
                Button { errors.clear() } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss")
            }
            .padding(.leading, Space.l)
            .padding(.trailing, Space.s)
            .padding(.vertical, Space.s)
            .background(Palette.critical.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .padding(.horizontal, Space.l)
            .padding(.bottom, Space.xs)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct LoadingView: View {
    let text: String

    var body: some View {
        VStack(spacing: Space.m) {
            ProgressView().controlSize(.large)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

struct ErrorScreen: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        EmptyStateView(icon: .system("wifi.exclamationmark"), tint: Palette.critical, title: "Couldn't reach Nestly", message: message) {
            Button("Try Again", action: retry).buttonStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
            Text(text).multilineTextAlignment(.leading)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
        .padding(.horizontal, Space.xl)
        .accessibilityElement(children: .combine)
    }
}
