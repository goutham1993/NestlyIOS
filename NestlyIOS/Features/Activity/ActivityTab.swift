import NestlyCore
import SwiftUI

struct DashboardData: Sendable, Equatable {
    var recent: [ActivityEntity] = []
    var latest: [CardKind: ActivityEntity] = [:]
    var growth: [ActivityEntity] = []
    var latestMedical: ActivityEntity?
    var latestVaccine: ActivityEntity?
    var feedInterval = ReminderLogic.defaultIntervalMinutes(.FEED)

    static let feedTypes: [ActivityType] = [.BOTTLE_FEED, .BREASTFEED, .SOLIDS]

    static func load(_ repos: Repositories, _ profile: ProfileEntity) async throws -> DashboardData {
        let a = repos.activities
        let f = profile.familyId, p = profile.id
        let zone = TimeZone.current
        let yesterday = LocalDate.today(zone).minusDays(1).startOfDayMs(zone)
        async let recent = a.range(familyId: f, profileId: p, from: yesterday, to: nowMs() + 86_400_000)
        async let feed = a.latestOf(familyId: f, profileId: p, feedTypes)
        async let pump = a.latestOf(familyId: f, profileId: nil, [.PUMP])
        async let diaper = a.latestOf(familyId: f, profileId: p, [.DIAPER])
        async let sleep = a.latestOf(familyId: f, profileId: p, [.SLEEP])
        async let routine = a.latestOf(familyId: f, profileId: p, [.ROUTINE])
        async let first = a.latestOf(familyId: f, profileId: p, [.BABY_FIRST])
        async let growth = a.ofTypes(familyId: f, profileId: p, [.GROWTH, .MILESTONE])
        async let medical = a.latestOf(familyId: f, profileId: p, [.MEDICAL])
        async let vaccine = a.latestOf(familyId: f, profileId: p, [.VACCINE])
        async let reminders = repos.reminders.fetchMine()
        var latest: [CardKind: ActivityEntity] = [:]
        latest[.FEED] = try await feed
        latest[.PUMP] = try await pump
        latest[.DIAPER] = try await diaper
        latest[.SLEEP] = try await sleep
        latest[.ROUTINE] = try await routine
        latest[.BABY_FIRSTS] = try await first
        let interval = (try? await reminders)?.first { $0.kind == .FEED && $0.profileId == p }?.intervalMinutes
        return DashboardData(
            recent: try await recent, latest: latest, growth: try await growth.filter { $0.profileId == p },
            latestMedical: try await medical, latestVaccine: try await vaccine,
            feedInterval: interval ?? ReminderLogic.defaultIntervalMinutes(.FEED)
        )
    }
}

struct ActivityTab: View {
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    @Environment(Preferences.self) private var prefs
    @State private var data: DashboardData?
    @State private var timers: [TimerKey: TimerState] = TimerControl.store.timers()
    @State private var showSummary = false

    var body: some View {
        Group {
            if let profile = family.selectedProfile {
                Clock(interval: timers.values.contains(where: \.isRunning) ? 1 : 30) { now in
                    ScrollView {
                        VStack(spacing: 14) {
                            header(profile, now)
                            if let data {
                                ForEach(prefs.cardOrder.filter(prefs.isCardVisible), id: \.self) { card in
                                    DashboardCard(card: card, data: data, timers: timers, now: now)
                                }
                            } else {
                                ProgressView().padding(40)
                            }
                            Button("Edit Activities") { app.push(.editActivities) }
                                .buttonStyle(.bordered)
                                .padding(.vertical, 8)
                        }
                        .padding(.horizontal, 16)
                    }
                    .background(Color(.systemGroupedBackground))
                }
                .live([.activity, .reminder], id: profile.id, into: $data) {
                    try await DashboardData.load(.shared, profile)
                }
            } else {
                WelcomeView()
            }
        }
        .navigationTitle("Nestly")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Summary") { showSummary = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Set Reminders") { app.push(.reminders) }
                    Button("Doctor Appointments") { app.push(.appointments) }
                    Button("Notes") { app.push(.notes) }
                    Button("Edit Activities") { app.push(.editActivities) }
                    Button("Nightstand Mode") { app.showNightstand = true }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("More")
            }
        }
        .sheet(isPresented: $showSummary) { SummarySheet(entries: data?.recent ?? []) }
        .onReceive(NotificationCenter.default.publisher(for: ActiveTimerStore.didChange)) { _ in
            timers = TimerControl.store.timers()
        }
        .onAppear { timers = TimerControl.store.timers() }
    }

    private func header(_ profile: ProfileEntity, _ now: EpochMs) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.name).font(.largeTitle.bold())
            HStack {
                if let birth = profile.birthDate, let age = Format.age(birth) { Text(age) }
                Spacer()
                Text(Format.headerDate(now))
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    @State private var adding = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to Nestly").font(.title.bold())
            Text("Track feeds, pumping, diapers, sleep and more. Add your child to get started, or bring your history over from Nara Baby.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Add Child") { adding = true }.buttonStyle(.borderedProminent)
            Button("Import from Nara") { app.push(.importExport) }.buttonStyle(.bordered)
        }
        .padding(32)
        .sheet(isPresented: $adding) {
            ChildForm(title: "Add child", askCaregiverName: true) { name, sex, birth, caregiver in
                try await app.repos.family.addChild(name: name, sex: sex, birthDate: birth, caregiverName: caregiver)
            }
        }
    }
}

// MARK: - Cards

struct DashboardCard: View {
    let card: CardKind
    let data: DashboardData
    let timers: [TimerKey: TimerState]
    let now: EpochMs
    @Environment(AppModel.self) private var app
    @Environment(Preferences.self) private var prefs
    @State private var expanded: Bool?

    var body: some View {
        SectionCard {
            HStack {
                Label(card.title, systemImage: card.symbol)
                    .font(.headline).foregroundStyle(card.color)
                Spacer()
                addButton
            }
            summary
            if card != .HEALTH && card != .GROWTH { todayList }
        }
    }

    // MARK: Header actions

    @ViewBuilder private var addButton: some View {
        let disabled = prefs.disabledToggles
        switch card {
        case .FEED:
            Menu {
                if !disabled.contains(.BREASTFEEDING) { entryButton(.BREASTFEED) }
                if !disabled.contains(.BOTTLE_FEEDING) { entryButton(.BOTTLE) }
                if !disabled.contains(.SOLID_FEEDING) { entryButton(.SOLIDS) }
                if !disabled.contains(.COMBO_FEEDING) { entryButton(.COMBO) }
                entryButton(.VITAMIN_D)
            } label: { addLabel }
        case .PUMP: Button { app.openEntry(.new(kind: .PUMP)) } label: { addLabel }
        case .DIAPER: Button { app.openEntry(.new(kind: .DIAPER)) } label: { addLabel }
        case .SLEEP: Button { app.openEntry(.new(kind: .SLEEP)) } label: { addLabel }
        case .ROUTINE: Button { app.openEntry(.new(kind: .ROUTINE)) } label: { addLabel }
        case .BABY_FIRSTS: Button { app.openEntry(.new(kind: .BABY_FIRST)) } label: { addLabel }
        case .GROWTH:
            Menu {
                entryButton(.GROWTH)
                entryButton(.MILESTONE)
            } label: { addLabel }
        case .HEALTH: EmptyView()
        }
    }

    private var addLabel: some View {
        Label("Add", systemImage: "plus.circle.fill").labelStyle(.iconOnly).font(.title2).foregroundStyle(card.color)
            .accessibilityLabel("Add \(card.title)")
    }

    private func entryButton(_ kind: EntryKind) -> some View {
        Button { app.openEntry(.new(kind: kind)) } label: { Label(kind.title, systemImage: kind.symbol) }
    }

    // MARK: Summary rows

    @ViewBuilder private var summary: some View {
        let latest = data.latest[card]
        switch card {
        case .FEED:
            if let breast = runningElapsed([.BREAST_LEFT, .BREAST_RIGHT]) {
                infoRow("Breastfeeding", Format.duration(breast), highlight: true)
                    .onTapGesture { app.openEntry(.new(kind: .BREASTFEED)) }
            }
            if let latest {
                infoRow("Last feeding", "\(Format.ago(latest.startTime, now: now))  \(feedValue(latest))")
                if let text = Format.nextFeeding(ReminderLogic.nextFeedState(latest.startTime, data.feedInterval, now: now)) {
                    Text(text).font(.subheadline).foregroundStyle(.secondary)
                }
            } else if runningElapsed([.BREAST_LEFT, .BREAST_RIGHT]) == nil {
                empty("Track a feeding")
            }
        case .PUMP:
            if let pump = runningElapsed([.PUMP]) {
                infoRow("Pumping", Format.duration(pump), highlight: true).onTapGesture { app.openEntry(.new(kind: .PUMP)) }
            }
            if let latest {
                infoRow("Last session", "\(Format.ago(latest.startTime, now: now))  \(latest.pump?.totalMl.map { Format.volume($0, prefs.units) } ?? "")")
            } else if runningElapsed([.PUMP]) == nil {
                empty("Track a pumping session")
            }
        case .DIAPER:
            if let latest { infoRow("Last change", "\(Format.ago(latest.startTime, now: now))  \(latest.label)") } else { empty("Track a diaper change") }
        case .SLEEP:
            let sleep = timers[.SLEEP] ?? TimerState()
            if !sleep.isIdle {
                infoRow("Sleeping", "since \(Format.time(sleep.sessionStart ?? now))  \(Format.duration(sleep.elapsedMs(now) / 1000))", highlight: true)
                    .onTapGesture { app.openEntry(.new(kind: .SLEEP)) }
            } else if let latest {
                infoRow("Last sleep", "\(Format.ago(latest.endTime ?? latest.startTime, now: now))  \(latest.durationSec.map(Format.duration) ?? "")")
            } else {
                empty("Track a sleep session")
            }
        case .ROUTINE:
            if let latest { infoRow(latest.label, Format.ago(latest.startTime, now: now)) } else { empty("Track a routine or create your own") }
        case .BABY_FIRSTS:
            if let latest { infoRow(latest.label, Format.relativeDay(latest.startTime, now: now)) } else { empty("Track memorable moments") }
        case .GROWTH:
            growthRows
        case .HEALTH:
            healthRows
        }
    }

    private var growthRows: some View {
        let growth = data.growth.filter { $0.type == .GROWTH }.sorted { $0.startTime > $1.startTime }
        let milestones = Set(data.growth.filter { $0.type == .MILESTONE }.map { $0.milestone?.milestoneKey ?? MilestoneCatalog.normalizeTitle($0.milestone?.title ?? "") })
        return VStack(spacing: 8) {
            ForEach(GrowthMetric.allCases) { metric in
                let value = growth.lazy.compactMap { metric.valueOf($0.growth) }.first
                Button { app.push(.growth(metric)) } label: {
                    infoRow(metric.label, value.map { format(metric, $0) } ?? "—", chevron: true)
                }
                .buttonStyle(.plain)
            }
            Button { app.push(.milestones) } label: {
                infoRow("Milestones", "\(milestones.count) of \(MilestoneCatalog.totalCount)", chevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var healthRows: some View {
        let zone = TimeZone.current
        let today = LocalDate.of(ms: now, zone: zone)
        let given = DailyDose.givenAt(data.recent, startOfToday: today.startOfDayMs(zone), startOfTomorrow: today.plusDays(1).startOfDayMs(zone))
        let givenEntry = given.flatMap { t in data.recent.first { $0.type == .VITAMIN_D && $0.startTime == t } }
        return VStack(spacing: 8) {
            Button {
                if let givenEntry { app.openEntry(.edit(activityId: givenEntry.id)) } else { app.openEntry(.new(kind: .VITAMIN_D)) }
            } label: {
                infoRow("Vitamin D", given.map { "Given today at \(Format.time($0))" } ?? "Not given today", chevron: true)
            }
            .buttonStyle(.plain)
            Button { app.openEntry(.new(kind: .MEDICAL)) } label: {
                infoRow("Medical", data.latestMedical.map(medicalText) ?? "—", chevron: true)
            }
            .buttonStyle(.plain)
            Button { app.push(.vaccinations) } label: {
                infoRow("Vaccine", data.latestVaccine.map(vaccineText) ?? "—", chevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func medicalText(_ a: ActivityEntity) -> String {
        let detail = a.medical?.temperatureC.map { Format.temp($0, prefs.units) } ?? a.medical?.medicationName ?? ""
        return "\(Format.dayAndTime(a.startTime, now: now))  \(detail)"
    }

    private func vaccineText(_ a: ActivityEntity) -> String {
        let n = a.vaccine?.vaccines.count ?? 0
        return "\(Format.relativeDay(a.startTime, now: now))  \(n == 1 ? "1 vaccine" : "\(n) vaccines")"
    }

    private func format(_ metric: GrowthMetric, _ value: Double) -> String {
        switch metric {
        case .WEIGHT: Format.weight(value, prefs.units)
        case .HEIGHT, .HEAD: Format.length(value, prefs.units)
        }
    }

    private func feedValue(_ a: ActivityEntity) -> String {
        switch a.type {
        case .BOTTLE_FEED: a.bottle?.totalMl.map { Format.volume($0, prefs.units) } ?? ""
        case .BREASTFEED: a.durationSec.map(Format.duration) ?? ""
        default: a.label
        }
    }

    private func runningElapsed(_ keys: [TimerKey]) -> Int64? {
        let states = keys.compactMap { timers[$0] }
        guard states.contains(where: { !$0.isIdle }) else { return nil }
        return states.reduce(0) { $0 + $1.elapsedMs(now) } / 1000
    }

    private func infoRow(_ title: String, _ value: String, highlight: Bool = false, chevron: Bool = false) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            Text(value).font(.subheadline).foregroundStyle(highlight ? card.color : .secondary).monospacedDigit()
            if chevron { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
        }
        .contentShape(Rectangle())
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
    }

    // MARK: Today list

    @ViewBuilder private var todayList: some View {
        let zone = TimeZone.current
        let start = LocalDate.of(ms: now, zone: zone).startOfDayMs(zone)
        let rows = ActivityFilters.filter(data.recent.filter { $0.startTime >= start && card.types.contains($0.type) }, prefs.filters)
            .sorted { $0.startTime > $1.startTime }
        if !rows.isEmpty {
            let isExpanded = expanded ?? (card == .FEED)
            let shown = isExpanded ? rows : Array(rows.prefix(3))
            let bars = Bars.fractions(rows)
            Divider()
            ForEach(shown) { entry in
                ActivityRow(entry: entry, barFraction: bars[entry.id])
                    .onTapGesture { app.openEntry(.edit(activityId: entry.id)) }
            }
            HStack {
                if rows.count > 3 {
                    Button(isExpanded ? "Show Less" : "Show More") { expanded = !isExpanded }
                }
                Spacer()
                Button("View History") { app.tab = .history }
            }
            .font(.footnote)
        }
    }
}

// MARK: - Sheets

struct SummarySheet: View {
    let entries: [ActivityEntity]
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @State private var last24 = false

    var body: some View {
        NavigationStack {
            let now = nowMs()
            let zone = TimeZone.current
            let from = last24 ? now - 86_400_000 : LocalDate.today(zone).startOfDayMs(zone)
            let lines = Summary.summarize(entries, from: from, to: now + 1, prefs: prefs.units)
            List {
                Picker("Range", selection: $last24) {
                    Text("Today").tag(false)
                    Text("Last 24 Hours").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                if lines.isEmpty {
                    Text("Nothing logged yet.").foregroundStyle(.secondary)
                }
                ForEach(lines, id: \.type) { line in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(line.type.displayName, systemImage: line.type.symbol).foregroundStyle(line.type.color)
                            Spacer()
                            Text("\(line.count)").font(.headline)
                        }
                        ForEach(line.details, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct FiltersSheet: View {
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<FilterOption> = []

    var body: some View {
        NavigationStack {
            List(FilterOption.allCases, id: \.self) { option in
                Toggle(option.label, isOn: Binding(
                    get: { selection.contains(option) },
                    set: { if $0 { selection.insert(option) } else { selection.remove(option) } }
                ))
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        prefs.setFilters(selection)
                        dismiss()
                    }
                }
            }
        }
        .onAppear { selection = prefs.filters }
        .presentationDetents([.medium, .large])
    }
}

struct EditActivitiesView: View {
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @State private var order: [CardKind] = []
    @State private var disabled: Set<ActivityToggle> = []

    private static let groups: [(String, [(ActivityToggle, Bool)])] = [
        ("Feed", [(.BREASTFEEDING, false), (.BOTTLE_FEEDING, false), (.BOTTLE_BREAST_MILK, true), (.BOTTLE_FORMULA, true), (.SOLID_FEEDING, false), (.COMBO_FEEDING, false)]),
        ("Other", [(.PUMPING, false), (.DIAPER_CHANGES, false), (.SLEEP, false), (.ROUTINES, false), (.BABY_FIRSTS, false), (.GROWTH, false), (.HEALTH, false)]),
    ]

    var body: some View {
        List {
            Section("Reorder") {
                ForEach(order, id: \.self) { card in
                    Label(card.title, systemImage: card.symbol).foregroundStyle(ActivityToggle.isCardVisible(card, disabled: disabled) ? .primary : .secondary)
                }
                .onMove { order.move(fromOffsets: $0, toOffset: $1) }
            }
            ForEach(Self.groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1, id: \.0) { toggle, isSub in
                        Toggle(toggle.label, isOn: Binding(
                            get: { !disabled.contains(toggle) },
                            set: { if $0 { disabled.remove(toggle) } else { disabled.insert(toggle) } }
                        ))
                        .padding(.leading, isSub ? 24 : 0)
                        .disabled(isSub && disabled.contains(.BOTTLE_FEEDING))
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Edit Activities")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    prefs.setCardOrder(order)
                    prefs.setDisabledToggles(disabled)
                    dismiss()
                }
            }
        }
        .onAppear {
            order = prefs.cardOrder
            disabled = prefs.disabledToggles
        }
    }
}
