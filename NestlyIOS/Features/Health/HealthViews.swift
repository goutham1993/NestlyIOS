import NestlyCore
import SwiftUI

// MARK: - Milestones (spec §16.2)

struct MilestonesView: View {
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    @State private var entries: [ActivityEntity]?
    @State private var expanded: Set<String>?

    var body: some View {
        let profile = family.selectedProfile
        let done = doneMap()
        List {
            ForEach(MilestoneCatalog.groups, id: \.label) { group in
                let count = group.items.filter { done[$0.key] != nil }.count
                Section {
                    if isExpanded(group) {
                        ForEach(group.items, id: \.key) { item in
                            let entry = done[item.key]
                            Button {
                                if let entry { app.openEntry(.edit(activityId: entry.id)) } else { app.openEntry(.new(kind: .MILESTONE, milestone: item)) }
                            } label: {
                                HStack(spacing: Space.m) {
                                    Image(systemName: entry == nil ? "circle" : "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(entry == nil ? Color(.tertiaryLabel) : tint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title).foregroundStyle(Color.primary)
                                        if let entry {
                                            Text(Format.date(LocalDate.of(ms: entry.startTime))).font(.footnote).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if entry == nil {
                                        Text("Log").font(.subheadline.weight(.medium)).foregroundStyle(tint)
                                    }
                                }
                                .foregroundStyle(Color.primary)
                            }
                            .accessibilityValue(entry == nil ? "Not yet" : "Done")
                        }
                    }
                } header: {
                    Button {
                        var set = expanded ?? defaultExpanded(profile)
                        if set.contains(group.label) { set.remove(group.label) } else { set.insert(group.label) }
                        withAnimation(.snappy) { expanded = set }
                    } label: {
                        VStack(alignment: .leading, spacing: Space.s) {
                            HStack {
                                Text(group.label).font(.rounded(.headline)).foregroundStyle(Color.primary)
                                Spacer()
                                Text("\(count) of \(group.items.count)").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                                Image(systemName: "chevron.down")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(isExpanded(group) ? 180 : 0))
                            }
                            ProgressView(value: Double(count), total: Double(max(group.items.count, 1)))
                                .tint(tint)
                        }
                        .foregroundStyle(Color.primary)
                        .textCase(nil)
                        .padding(.top, Space.s)
                    }
                    .sensoryFeedback(.selection, trigger: isExpanded(group))
                    .accessibilityValue(isExpanded(group) ? "Expanded" : "Collapsed")
                }
            }
        }
        .navigationTitle("Milestones")
        .live([.activity], id: profile?.id ?? "", into: $entries) { [profile] in
            guard let profile else { return [] }
            return try await Repositories.shared.activities.ofTypes(familyId: profile.familyId, profileId: profile.id, [.MILESTONE])
        }
    }

    private var tint: Color { EntryKind.MILESTONE.color }

    private func isExpanded(_ group: MilestoneGroup) -> Bool {
        (expanded ?? defaultExpanded(family.selectedProfile)).contains(group.label)
    }

    /// The last group whose age is within the child's age (at least 2 months).
    private func defaultExpanded(_ profile: ProfileEntity?) -> Set<String> {
        let age = profile?.birthDate.map { LocalDate.monthsBetween($0, .today()) } ?? 0
        let limit = max(age, 2)
        let group = MilestoneCatalog.groups.last { $0.ageMonths <= limit } ?? MilestoneCatalog.groups.first
        return Set([group?.label].compactMap { $0 })
    }

    /// Milestone key → logging entry, matched by key or normalized title.
    private func doneMap() -> [String: ActivityEntity] {
        var out: [String: ActivityEntity] = [:]
        for entry in (entries ?? []).sorted(by: { $0.startTime < $1.startTime }) {
            guard let details = entry.milestone else { continue }
            if let key = details.milestoneKey, MilestoneCatalog.byKey(key) != nil {
                out[key] = out[key] ?? entry
            } else if let item = MilestoneCatalog.findByTitle(details.title) {
                out[item.key] = out[item.key] ?? entry
            }
        }
        return out
    }
}

// MARK: - Vaccinations (spec §16.3)

struct VaccinationsView: View {
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    @State private var entries: [ActivityEntity]?

    var body: some View {
        let profile = family.selectedProfile
        List {
            if let entries, let profile {
                content(entries, profile)
            } else {
                HStack(spacing: Space.m) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Vaccinations")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { app.openEntry(.new(kind: .VACCINE)) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add vaccination")
            }
        }
        .live([.activity, .profile], id: profile?.id ?? "", into: $entries) { [profile] in
            guard let profile else { return [] }
            return try await Repositories.shared.activities.ofTypes(familyId: profile.familyId, profileId: profile.id, [.VACCINE])
        }
    }

    @ViewBuilder private func content(_ entries: [ActivityEntity], _ profile: ProfileEntity) -> some View {
        let statuses = VaccineSchedule.doseStatuses(profile.birthDate, entries, today: .today())
        let counted = statuses.filter(\.countsTowardCompletion)
        let given = counted.filter { $0.state == .GIVEN }.count
        if profile.birthDate == nil {
            Section {
                Text("Add \(profile.name)'s birth date (Account → Family → tap their name) to see due dates, recommendations and overdue doses. Vaccines you've logged still show below.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        Section {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.m) {
                    IconTile(icon: .vaccine, tint: Self.tint, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(given) of \(counted.count)").font(.rounded(.title2, weight: .bold)).monospacedDigit()
                        Text("scheduled doses given").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: Double(given), total: Double(max(counted.count, 1))).tint(Self.tint)
            }
            .padding(.vertical, Space.xs)
            .accessibilityElement(children: .combine)
            if entries.isEmpty {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("No vaccines logged yet").font(.subheadline.weight(.semibold))
                    Text("Log the vaccines \(profile.name) has already had and Nestly will track what's due next.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button { app.openEntry(.new(kind: .VACCINE)) } label: { Label("Add Vaccination", systemImage: "plus") }
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, Space.xs)
                }
            }
        }
        if profile.birthDate != nil {
            Section("Up next for \(profile.name)") {
                let recs = VaccineSchedule.recommendations(statuses)
                if recs.isEmpty { Text("All scheduled doses are up to date. Nice work!").foregroundStyle(.secondary) }
                ForEach(recs, id: \.dose.key) { doseRow($0) }
            }
        }
        Section("Vaccination chart") {
            ForEach(VaccineSchedule.groups, id: \.label) { group in
                let rows = statuses.filter { $0.groupLabel == group.label }
                let groupCounted = rows.filter(\.countsTowardCompletion)
                DisclosureGroup {
                    ForEach(rows, id: \.dose.key) { doseRow($0) }
                } label: {
                    HStack {
                        Text(group.label)
                        Spacer()
                        Text("\(groupCounted.filter { $0.state == .GIVEN }.count)/\(groupCounted.count)").foregroundStyle(.secondary)
                    }
                }
            }
        }
        Section("Also recommended") {
            ForEach(VaccineSchedule.alsoRecommended, id: \.title) { info in
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.title).font(.subheadline.weight(.semibold))
                    Text(info.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        if !entries.isEmpty {
            Section("History") {
                ForEach(entries.sorted { $0.startTime > $1.startTime }) { entry in
                    ActivityRow(entry: entry, showDay: true)
                        .onTapGesture { app.openEntry(.edit(activityId: entry.id)) }
                }
            }
        }
        Section {
            Text("Based on the CDC (US) immunization schedule for birth–6 years. Dose numbers are worked out from the order vaccines were logged. If a dose was late, catch-up timing can differ — this isn't medical advice, so confirm what's due with your pediatrician.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func doseRow(_ status: DoseStatus) -> some View {
        Button {
            if let id = status.givenEntryId { app.openEntry(.edit(activityId: id)) } else { app.openEntry(.new(kind: .VACCINE, vaccines: [status.dose.vaccineName])) }
        } label: {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: stateSymbol(status.state))
                    .font(.title3)
                    .foregroundStyle(stateColor(status.state))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(status.dose.vaccineName) · Dose \(status.dose.doseNumber)").foregroundStyle(Color.primary)
                    Text(subtitle(status)).font(.footnote).foregroundStyle(.secondary)
                    if let note = status.dose.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: Space.s)
                if status.state != .UPCOMING {
                    StatusPill(text: stateLabel(status.state), tint: stateColor(status.state))
                }
            }
            .foregroundStyle(Color.primary)
        }
    }

    private func stateSymbol(_ state: DoseState) -> String {
        switch state {
        case .GIVEN: "checkmark.circle.fill"
        case .OVERDUE: "exclamationmark.circle.fill"
        case .DUE: "clock.fill"
        case .UPCOMING: "circle"
        }
    }

    private static var tint: Color { EntryKind.VACCINE.color }

    private func subtitle(_ s: DoseStatus) -> String {
        switch s.state {
        case .GIVEN: s.givenDate.map { "Given \(Format.date($0))" } ?? "Given"
        case .OVERDUE: s.dueDate.map { "Was due \(Format.date($0)) · \(s.groupLabel)" } ?? "Overdue · \(s.groupLabel)"
        case .DUE: "Due now · recommended at \(s.groupLabel)"
        case .UPCOMING: s.dueDate.map { "Due \(Format.date($0)) · \(s.groupLabel)" } ?? "Recommended at \(s.groupLabel)"
        }
    }

    private func stateLabel(_ state: DoseState) -> String {
        switch state {
        case .GIVEN: "Given"
        case .OVERDUE: "Overdue"
        case .DUE: "Due now"
        case .UPCOMING: "Upcoming"
        }
    }

    private func stateColor(_ state: DoseState) -> Color {
        switch state {
        case .GIVEN: Self.tint
        case .OVERDUE: Palette.critical
        case .DUE: Palette.warning
        case .UPCOMING: Color(.tertiaryLabel)
        }
    }
}

// MARK: - Reminders (spec §16.4)

struct RemindersView: View {
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    @State private var reminders: [ReminderEntity]?
    @State private var editing: ReminderEntity?
    @State private var message: String?

    var body: some View {
        let profile = family.selectedProfile
        let caregiverId = family.currentCaregiver?.id
        List {
            Section {
                if let reminders {
                    ForEach(reminders) { reminder in
                        let label = ReminderLogic.label(reminder.kind)
                        let card = Self.card(reminder.kind)
                        VStack(alignment: .leading, spacing: Space.s) {
                            Toggle(isOn: Binding(get: { reminder.enabled }, set: { setEnabled(reminder, $0) })) {
                                HStack(spacing: Space.m) {
                                    IconTile(icon: card.icon, tint: card.color, size: 32)
                                    Text(label)
                                }
                            }
                            .tint(card.color)
                            Button { editing = reminder } label: {
                                HStack(spacing: Space.xs) {
                                    Text("Every \(Format.duration(Int64(reminder.intervalMinutes) * 60)) after last \(label.lowercased())")
                                    Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                                }
                                .font(.subheadline)
                                .foregroundStyle(reminder.enabled ? card.color : .secondary)
                            }
                            .buttonStyle(.borderless)
                            .padding(.leading, 32 + Space.m)
                        }
                        .padding(.vertical, Space.xs)
                    }
                } else {
                    HStack(spacing: Space.m) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
                }
            } footer: {
                Text("Get an alert after a set time since the last activity of each type.")
            }
            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(Palette.critical) }
            }
        }
        .navigationTitle("Reminders")
        .sheet(item: $editing) { reminder in
            DurationEditor(title: "\(ReminderLogic.label(reminder.kind)) interval", initialSeconds: Int64(reminder.intervalMinutes) * 60, showSeconds: false) { seconds in
                let minutes = max(1, Int(seconds / 60))
                if reminder.kind == .FEED { app.repos.prefs.setDefaultFeedIntervalMinutes(minutes) }
                update(reminder.with { $0.intervalMinutes = minutes })
            }
        }
        .live([.reminder], id: "\(profile?.id ?? "")-\(caregiverId ?? "")", into: $reminders) { [profile, caregiverId] in
            guard let profile, let caregiverId else { return [] }
            var rows: [ReminderEntity] = []
            for kind in ReminderKind.allCases {
                rows.append(try await Repositories.shared.reminders.getOrCreate(familyId: profile.familyId, caregiverId: caregiverId, profileId: profile.id, kind: kind))
            }
            return rows
        }
    }

    private static func card(_ kind: ReminderKind) -> CardKind {
        switch kind {
        case .FEED: .FEED
        case .PUMP: .PUMP
        case .DIAPER: .DIAPER
        case .SLEEP: .SLEEP
        }
    }

    private func setEnabled(_ reminder: ReminderEntity, _ enabled: Bool) {
        Task {
            if enabled {
                guard await NotificationScheduler.requestAuthorization() else {
                    message = "Notifications are off for Nestly. Turn them on in Settings → Notifications to get reminders."
                    return
                }
            }
            message = nil
            update(reminder.with { $0.enabled = enabled })
        }
    }

    private func update(_ reminder: ReminderEntity) {
        Task {
            do {
                try await app.repos.reminders.update(reminder)
                app.scheduleReschedule()
            } catch {
                message = (error as? ConflictError)?.errorDescription ?? "Couldn't save. Check your connection and try again."
            }
        }
    }
}
