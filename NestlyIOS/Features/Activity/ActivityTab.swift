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

// MARK: - Activity tab

struct ActivityTab: View {
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    @Environment(Preferences.self) private var prefs
    @State private var data: DashboardData?
    @State private var timers: [TimerKey: TimerState] = TimerControl.store.timers()
    @State private var showSummary = false

    private var visibleCards: [CardKind] { prefs.cardOrder.filter(prefs.isCardVisible) }

    var body: some View {
        Group {
            if let profile = family.selectedProfile {
                Clock(interval: timers.values.contains(where: \.isRunning) ? 1 : 30) { now in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.xl) {
                            ChildHeader(profile: profile, now: now)
                            TimerBanners(timers: timers, now: now)
                            QuickLogRow(cards: visibleCards)
                            if let data {
                                AtAGlance(cards: visibleCards, data: data, timers: timers, now: now)
                                TodayCard(cards: visibleCards, data: data, now: now)
                                if visibleCards.contains(.GROWTH) { GrowthCard(data: data) }
                                if visibleCards.contains(.HEALTH) { HealthCard(data: data, now: now) }
                            } else {
                                ProgressView().frame(maxWidth: .infinity).padding(40)
                            }
                            Button { app.push(.editActivities) } label: {
                                Label("Edit Activities", systemImage: "slider.horizontal.3")
                            }
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, Space.l)
                        }
                        .padding(.horizontal, Space.l)
                        .padding(.top, Space.s)
                        .animation(.snappy, value: timers)
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
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .hiddenNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSummary = true } label: { Image(systemName: "list.bullet.rectangle.portrait") }
                    .accessibilityLabel("Summary")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { app.push(.reminders) } label: { Label("Set Reminders", systemImage: "bell") }
                    Button { app.push(.appointments) } label: { Label("Doctor Appointments", systemImage: "calendar") }
                    Button { app.push(.notes) } label: { Label("Notes", systemImage: "note.text") }
                    Button { app.push(.editActivities) } label: { Label("Edit Activities", systemImage: "slider.horizontal.3") }
                    Divider()
                    Button { app.showNightstand = true } label: { Label("Nightstand Mode", systemImage: "moon.stars") }
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
}

// MARK: - Header

private struct ChildHeader: View {
    let profile: ProfileEntity
    let now: EpochMs
    @Environment(FamilyStore.self) private var family

    var body: some View {
        HStack(spacing: Space.m) {
            ChildAvatar(name: profile.name, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                let profiles = family.profiles ?? []
                if profiles.count > 1 {
                    Menu {
                        ForEach(profiles) { child in
                            Button { family.select(child) } label: {
                                if child.id == profile.id { Label(child.name, systemImage: "checkmark") } else { Text(child.name) }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            name
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.title3).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("\(profile.name), switch child")
                } else {
                    name
                }
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var name: some View {
        Text(profile.name)
            .font(.rounded(.largeTitle, weight: .bold))
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var subtitle: String {
        let age = profile.birthDate.flatMap { Format.age($0) }
        return [age, Format.headerDate(now)].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Running timers

private struct TimerBanners: View {
    let timers: [TimerKey: TimerState]
    let now: EpochMs

    var body: some View {
        let active = TimerGroup.allCases.compactMap { group in
            TimerControl.state(group, now: now).map { (group, $0) }
        }
        if !active.isEmpty {
            VStack(spacing: Space.s) {
                ForEach(active, id: \.0) { group, state in
                    TimerBanner(group: group, state: state, sessionStart: group.keys.compactMap { timers[$0]?.sessionStart }.min(), now: now)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
}

private struct TimerBanner: View {
    let group: TimerGroup
    let state: TimerGroupState
    let sessionStart: EpochMs?
    let now: EpochMs
    @Environment(AppModel.self) private var app

    var body: some View {
        let running = !state.isPaused
        HStack(spacing: Space.m) {
            Button { app.openEntry(.new(kind: group.entryKind)) } label: {
                HStack(spacing: Space.m) {
                    IconTile(icon: group.icon, tint: group.color, size: 44, filled: true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if running { LiveDot(tint: group.color) }
                            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                        }
                        Text(Format.stopwatch(state.elapsedSeconds(at: Date(epochMs: now))))
                            .font(.rounded(.title2, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(Color.primary)
                        if let sessionStart, group == .SLEEP {
                            Text("Since \(Format.time(sessionStart))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.pressable)
            Button { TimerControl.pauseResume(group) } label: {
                Image(systemName: running ? "pause.fill" : "play.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(group.color)
                    .frame(width: 48, height: 48)
                    .background(group.color.opacity(0.16), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(running ? "Pause" : "Resume")
        }
        .padding(Space.m)
        .background(group.color.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .sensoryFeedback(.impact(weight: .light), trigger: running)
    }

    private var title: String {
        let base: String
        switch group {
        case .BREASTFEED: base = "Breastfeeding" + (state.side.map { $0 == .LEFT ? " · Left" : " · Right" } ?? "")
        case .PUMP: base = "Pumping"
        case .SLEEP: base = "Sleeping"
        }
        return state.isPaused ? "\(base) · Paused" : base
    }
}

// MARK: - Quick log

private struct QuickLogRow: View {
    let cards: [CardKind]
    @Environment(AppModel.self) private var app
    @Environment(Preferences.self) private var prefs

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionTitle("Log")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.m) {
                    ForEach(cards.filter { $0 != .HEALTH }, id: \.self) { card in tile(card) }
                }
                .padding(.horizontal, Space.l)
            }
            .padding(.horizontal, -Space.l)
        }
    }

    @ViewBuilder private func tile(_ card: CardKind) -> some View {
        let disabled = prefs.disabledToggles
        switch card {
        case .FEED:
            Menu {
                if !disabled.contains(.BREASTFEEDING) { entryButton(.BREASTFEED) }
                if !disabled.contains(.BOTTLE_FEEDING) { entryButton(.BOTTLE) }
                if !disabled.contains(.SOLID_FEEDING) { entryButton(.SOLIDS) }
                if !disabled.contains(.COMBO_FEEDING) { entryButton(.COMBO) }
                entryButton(.VITAMIN_D)
            } label: { QuickLogTile(card: card) }
                .buttonStyle(.pressable)
        case .GROWTH:
            Menu {
                entryButton(.GROWTH)
                entryButton(.MILESTONE)
            } label: { QuickLogTile(card: card) }
                .buttonStyle(.pressable)
        case .PUMP: open(.PUMP, card)
        case .DIAPER: open(.DIAPER, card)
        case .SLEEP: open(.SLEEP, card)
        case .ROUTINE: open(.ROUTINE, card)
        case .BABY_FIRSTS: open(.BABY_FIRST, card)
        case .HEALTH: EmptyView()
        }
    }

    private func open(_ kind: EntryKind, _ card: CardKind) -> some View {
        Button {
            Haptics.tap()
            app.openEntry(.new(kind: kind))
        } label: { QuickLogTile(card: card) }
            .buttonStyle(.pressable)
    }

    private func entryButton(_ kind: EntryKind) -> some View {
        Button { app.openEntry(.new(kind: kind)) } label: {
            Label { Text(kind.title) } icon: { kind.icon.image }
        }
    }
}

private struct QuickLogTile: View {
    let card: CardKind

    var body: some View {
        VStack(spacing: Space.s) {
            IconTile(icon: card.icon, tint: card.color, size: 56)
            Text(card.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 76)
        .padding(.vertical, Space.m)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Log \(card.title)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - At a glance

private struct AtAGlance: View {
    let cards: [CardKind]
    let data: DashboardData
    let timers: [TimerKey: TimerState]
    let now: EpochMs
    @Environment(AppModel.self) private var app
    @Environment(Preferences.self) private var prefs

    private static let glanceable: Set<CardKind> = [.FEED, .PUMP, .DIAPER, .SLEEP, .ROUTINE, .BABY_FIRSTS]

    var body: some View {
        let shown = cards.filter(Self.glanceable.contains)
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                SectionTitle("At a glance")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m), GridItem(.flexible(), spacing: Space.m)], spacing: Space.m) {
                    ForEach(shown, id: \.self) { card in
                        Button { open(card) } label: { StatusCard(card: card, status: status(card)) }
                            .buttonStyle(.pressable)
                    }
                }
            }
        }
    }

    /// Edits the latest entry; starts a new one when there is none yet.
    private func open(_ card: CardKind) {
        if let latest = data.latest[card] {
            app.openEntry(.edit(activityId: latest.id))
        } else {
            app.openEntry(.new(kind: defaultKind(card)))
        }
    }

    private func defaultKind(_ card: CardKind) -> EntryKind {
        switch card {
        case .FEED:
            let disabled = prefs.disabledToggles
            if !disabled.contains(.BOTTLE_FEEDING) { return .BOTTLE }
            if !disabled.contains(.BREASTFEEDING) { return .BREASTFEED }
            return .SOLIDS
        case .PUMP: return .PUMP
        case .DIAPER: return .DIAPER
        case .SLEEP: return .SLEEP
        case .ROUTINE: return .ROUTINE
        case .BABY_FIRSTS: return .BABY_FIRST
        case .GROWTH: return .GROWTH
        case .HEALTH: return .MEDICAL
        }
    }

    private func status(_ card: CardKind) -> StatusCard.Status {
        let latest = data.latest[card]
        switch card {
        case .FEED:
            guard let latest else { return .empty("Track a feeding") }
            var footnote: String?
            var footnoteTint: Color = .secondary
            let next = ReminderLogic.nextFeedState(latest.startTime, data.feedInterval, now: now)
            if let text = Format.nextFeeding(next) {
                footnote = text.replacingOccurrences(of: "Next feeding", with: "Next")
                if case .overdue = next { footnoteTint = Palette.warning }
                if case .dueNow = next { footnoteTint = Palette.warning }
            }
            return .value(Format.ago(latest.startTime, now: now), detail: feedValue(latest), footnote: footnote, footnoteTint: footnoteTint)
        case .PUMP:
            guard let latest else { return .empty("Track a pumping session") }
            return .value(Format.ago(latest.startTime, now: now), detail: latest.pump?.totalMl.map { Format.volume($0, prefs.units) })
        case .DIAPER:
            guard let latest else { return .empty("Track a diaper change") }
            return .value(Format.ago(latest.startTime, now: now), detail: latest.label)
        case .SLEEP:
            let sleep = timers[.SLEEP] ?? TimerState()
            if !sleep.isIdle {
                return .value(Format.duration(sleep.elapsedMs(now) / 1000), detail: "Sleeping since \(Format.time(sleep.sessionStart ?? now))", live: true)
            }
            guard let latest else { return .empty("Track a sleep session") }
            return .value(Format.ago(latest.endTime ?? latest.startTime, now: now), detail: latest.durationSec.map { "Slept \(Format.duration($0))" })
        case .ROUTINE:
            guard let latest else { return .empty("Track a routine or create your own") }
            return .value(latest.label, detail: Format.ago(latest.startTime, now: now))
        case .BABY_FIRSTS:
            guard let latest else { return .empty("Track memorable moments") }
            return .value(latest.label, detail: Format.relativeDay(latest.startTime, now: now))
        case .GROWTH, .HEALTH:
            return .empty("")
        }
    }

    private func feedValue(_ a: ActivityEntity) -> String? {
        let value: String
        switch a.type {
        case .BOTTLE_FEED: value = a.bottle?.totalMl.map { Format.volume($0, prefs.units) } ?? ""
        case .BREASTFEED: value = a.durationSec.map(Format.duration) ?? ""
        default: value = a.label
        }
        let parts = [a.type.displayName, value].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}

private struct StatusCard: View {
    enum Status {
        case value(String, detail: String? = nil, footnote: String? = nil, footnoteTint: Color = .secondary, live: Bool = false)
        case empty(String)
    }

    let card: CardKind
    let status: Status

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                IconTile(icon: card.icon, tint: card.color, size: 28)
                Text(card.title).font(.subheadline.weight(.semibold)).foregroundStyle(card.color)
                Spacer(minLength: 0)
                if case .value(_, _, _, _, true) = status { LiveDot(tint: card.color) }
            }
            Spacer(minLength: 0)
            switch status {
            case let .value(primary, detail, footnote, footnoteTint, _):
                Text(primary)
                    .font(.rounded(.title3, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                if let detail, !detail.isEmpty {
                    Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                if let footnote {
                    Text(footnote).font(.caption.weight(.medium)).foregroundStyle(footnoteTint).lineLimit(2)
                }
            case let .empty(text):
                Text(text).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                Label("Add", systemImage: "plus").font(.caption.weight(.semibold)).foregroundStyle(card.color)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .padding(Space.m)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Today

private struct TodayCard: View {
    let cards: [CardKind]
    let data: DashboardData
    let now: EpochMs
    @Environment(AppModel.self) private var app
    @Environment(Preferences.self) private var prefs
    @State private var expanded = false

    private static let collapsedCount = 4

    var body: some View {
        let zone = TimeZone.current
        let start = LocalDate.of(ms: now, zone: zone).startOfDayMs(zone)
        let listed = Set(cards.filter { $0 != .HEALTH && $0 != .GROWTH }.flatMap(\.types))
        let rows = ActivityFilters.filter(data.recent.filter { $0.startTime >= start && listed.contains($0.type) }, prefs.filters)
            .sorted { $0.startTime > $1.startTime }
        let shown = expanded ? rows : Array(rows.prefix(Self.collapsedCount))
        let bars = Bars.fractions(rows)

        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Today")
                Spacer()
                if !rows.isEmpty {
                    Text(rows.count == 1 ? "1 entry" : "\(rows.count) entries").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Card(padding: Space.m) {
                if rows.isEmpty {
                    HStack(spacing: Space.m) {
                        IconTile(icon: .stroller, tint: .secondary, size: 34)
                        Text("Nothing logged yet today. Tap a tile above to start.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Divider().padding(.leading, 46) }
                            Button { app.openEntry(.edit(activityId: entry.id)) } label: {
                                ActivityRow(entry: entry, barFraction: bars[entry.id], now: now)
                                    .padding(.vertical, Space.s)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    Divider()
                    HStack {
                        if rows.count > Self.collapsedCount {
                            Button {
                                withAnimation(.snappy) { expanded.toggle() }
                            } label: {
                                Label(expanded ? "Show Less" : "Show All", systemImage: expanded ? "chevron.up" : "chevron.down")
                            }
                        }
                        Spacer()
                        Button { app.tab = .history } label: {
                            HStack(spacing: 4) {
                                Text("History")
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            }
                        }
                    }
                    .font(.subheadline.weight(.medium))
                }
            }
        }
    }
}

// MARK: - Growth & Health

private struct GrowthCard: View {
    let data: DashboardData
    @Environment(AppModel.self) private var app
    @Environment(Preferences.self) private var prefs

    var body: some View {
        let growth = data.growth.filter { $0.type == .GROWTH }.sorted { $0.startTime > $1.startTime }
        let milestones = Set(data.growth.filter { $0.type == .MILESTONE }.map { $0.milestone?.milestoneKey ?? MilestoneCatalog.normalizeTitle($0.milestone?.title ?? "") })
        VStack(alignment: .leading, spacing: Space.m) {
            SectionTitle("Growth")
            Card(padding: Space.m) {
                VStack(spacing: 0) {
                    ForEach(Array(GrowthMetric.allCases.enumerated()), id: \.element) { index, metric in
                        if index > 0 { Divider().padding(.leading, 42) }
                        let value = growth.lazy.compactMap { metric.valueOf($0.growth) }.first
                        Button { app.push(.growth(metric)) } label: {
                            IconRow(title: metric.label, icon: metric.icon, tint: CardKind.GROWTH.color, value: value.map { format(metric, $0) } ?? "—")
                                .padding(.vertical, Space.s)
                        }
                        .buttonStyle(.pressable)
                    }
                    Divider().padding(.leading, 42)
                    Button { app.push(.milestones) } label: {
                        IconRow(title: "Milestones", icon: .milestone, tint: CardKind.GROWTH.color, value: "\(milestones.count) of \(MilestoneCatalog.totalCount)")
                            .padding(.vertical, Space.s)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    private func format(_ metric: GrowthMetric, _ value: Double) -> String {
        switch metric {
        case .WEIGHT: Format.weight(value, prefs.units)
        case .HEIGHT, .HEAD: Format.length(value, prefs.units)
        }
    }
}

extension GrowthMetric {
    var icon: NestlyIcon {
        switch self {
        case .WEIGHT: .weight
        case .HEIGHT: .height
        case .HEAD: .child
        }
    }
}

private struct HealthCard: View {
    let data: DashboardData
    let now: EpochMs
    @Environment(AppModel.self) private var app
    @Environment(Preferences.self) private var prefs

    var body: some View {
        let zone = TimeZone.current
        let today = LocalDate.of(ms: now, zone: zone)
        let given = DailyDose.givenAt(data.recent, startOfToday: today.startOfDayMs(zone), startOfTomorrow: today.plusDays(1).startOfDayMs(zone))
        let givenEntry = given.flatMap { t in data.recent.first { $0.type == .VITAMIN_D && $0.startTime == t } }
        let tint = CardKind.HEALTH.color
        VStack(alignment: .leading, spacing: Space.m) {
            SectionTitle("Health")
            Card(padding: Space.m) {
                VStack(spacing: 0) {
                    Button {
                        if let givenEntry { app.openEntry(.edit(activityId: givenEntry.id)) } else { app.openEntry(.new(kind: .VITAMIN_D)) }
                    } label: {
                        HStack {
                            IconRow(title: "Vitamin D", icon: .vitaminD, tint: Palette.firsts, subtitle: given.map { "Given today at \(Format.time($0))" } ?? "Not given today", chevron: false)
                            if given != nil {
                                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Palette.routine)
                                    .accessibilityLabel("Given")
                            } else {
                                StatusPill(text: "Log", systemImage: "plus", tint: Palette.firsts)
                            }
                        }
                        .padding(.vertical, Space.s)
                    }
                    .buttonStyle(.pressable)
                    Divider().padding(.leading, 48)
                    Button { app.openEntry(.new(kind: .MEDICAL)) } label: {
                        IconRow(title: "Medical", icon: .thermometer, tint: tint, subtitle: data.latestMedical.map(medicalText) ?? "Temperature and medication")
                            .padding(.vertical, Space.s)
                    }
                    .buttonStyle(.pressable)
                    Divider().padding(.leading, 48)
                    Button { app.push(.vaccinations) } label: {
                        IconRow(title: "Vaccines", icon: .vaccine, tint: tint, subtitle: data.latestVaccine.map(vaccineText) ?? "Schedule and records")
                            .padding(.vertical, Space.s)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    private func medicalText(_ a: ActivityEntity) -> String {
        let detail = a.medical?.temperatureC.map { Format.temp($0, prefs.units) } ?? a.medical?.medicationName ?? ""
        return [Format.dayAndTime(a.startTime, now: now), detail].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func vaccineText(_ a: ActivityEntity) -> String {
        let n = a.vaccine?.vaccines.count ?? 0
        return "\(Format.relativeDay(a.startTime, now: now)) · \(n == 1 ? "1 vaccine" : "\(n) vaccines")"
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.rounded(.title3, weight: .bold)).accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    @State private var adding = false

    var body: some View {
        EmptyStateView(
            icon: .stroller,
            title: "Welcome to Nestly",
            message: "Track feeds, pumping, diapers, sleep and more. Add your child to get started, or bring your history over from Nara Baby."
        ) {
            Button("Add Child") { adding = true }.buttonStyle(.primary)
            Button("Import from Nara") { app.push(.importExport) }.buttonStyle(.secondary)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $adding) {
            ChildForm(title: "Add child", askCaregiverName: true) { name, sex, birth, caregiver in
                try await app.repos.family.addChild(name: name, sex: sex, birthDate: birth, caregiverName: caregiver)
            }
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
                Picker("Range", selection: $last24.animation(.snappy)) {
                    Text("Today").tag(false)
                    Text("Last 24 Hours").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                if lines.isEmpty {
                    Text("Nothing logged yet.").foregroundStyle(.secondary)
                }
                ForEach(lines, id: \.type) { line in
                    HStack(alignment: .top, spacing: Space.m) {
                        IconTile(icon: line.type.icon, tint: line.type.color, size: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.type.displayName).font(.headline)
                            ForEach(line.details, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text("\(line.count)")
                            .font(.rounded(.title2, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(line.type.color)
                            .contentTransition(.numericText())
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Radius.l)
    }
}

struct FiltersSheet: View {
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<FilterOption> = []

    var body: some View {
        NavigationStack {
            List(FilterOption.allCases, id: \.self) { option in
                Toggle(isOn: Binding(
                    get: { selection.contains(option) },
                    set: { if $0 { selection.insert(option) } else { selection.remove(option) } }
                )) {
                    HStack(spacing: Space.m) {
                        IconTile(icon: option.icon, tint: option.tint, size: 30)
                        Text(option.label)
                    }
                }
                .tint(Palette.accent)
            }
            .sensoryFeedback(.selection, trigger: selection)
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
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear All") { selection = [] }.disabled(selection.isEmpty)
                }
            }
        }
        .onAppear { selection = prefs.filters }
        .presentationDetents([.medium, .large])
    }
}

extension FilterOption {
    var icon: NestlyIcon {
        switch self {
        case .NOTES: .note
        case .PHOTOS: .system("photo.fill")
        case .FEED: CardKind.FEED.icon
        case .PUMP: CardKind.PUMP.icon
        case .DIAPER: CardKind.DIAPER.icon
        case .SLEEP: CardKind.SLEEP.icon
        case .ROUTINE: CardKind.ROUTINE.icon
        case .HEALTH: CardKind.HEALTH.icon
        }
    }

    var tint: Color {
        switch self {
        case .NOTES, .PHOTOS: Palette.accent
        case .FEED: CardKind.FEED.color
        case .PUMP: CardKind.PUMP.color
        case .DIAPER: CardKind.DIAPER.color
        case .SLEEP: CardKind.SLEEP.color
        case .ROUTINE: CardKind.ROUTINE.color
        case .HEALTH: CardKind.HEALTH.color
        }
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
            Section {
                ForEach(order, id: \.self) { card in
                    let visible = ActivityToggle.isCardVisible(card, disabled: disabled)
                    HStack(spacing: Space.m) {
                        IconTile(icon: card.icon, tint: visible ? card.color : .secondary, size: 30)
                        Text(card.title).foregroundStyle(visible ? .primary : .secondary)
                    }
                }
                .onMove { order.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Order")
            } footer: {
                Text("Drag to change the order of tiles and cards on the Activity tab.")
            }
            ForEach(Self.groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1, id: \.0) { toggle, isSub in
                        Toggle(toggle.label, isOn: Binding(
                            get: { !disabled.contains(toggle) },
                            set: { if $0 { disabled.remove(toggle) } else { disabled.insert(toggle) } }
                        ))
                        .tint(Palette.accent)
                        .padding(.leading, isSub ? 24 : 0)
                        .disabled(isSub && disabled.contains(.BOTTLE_FEEDING))
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: disabled)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Edit Activities")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    prefs.setCardOrder(order)
                    prefs.setDisabledToggles(disabled)
                    Haptics.success()
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
