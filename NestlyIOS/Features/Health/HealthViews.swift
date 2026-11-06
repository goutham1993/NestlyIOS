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
                                HStack {
                                    Image(systemName: entry == nil ? "circle" : "checkmark.circle.fill")
                                        .foregroundStyle(entry == nil ? Color.secondary : CardKind.GROWTH.color)
                                    Text(item.title).foregroundStyle(.primary)
                                    Spacer()
                                    Text(entry.map { Format.date(LocalDate.of(ms: $0.startTime)) } ?? "Log milestone")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Button {
                        var set = expanded ?? defaultExpanded(profile)
                        if set.contains(group.label) { set.remove(group.label) } else { set.insert(group.label) }
                        expanded = set
                    } label: {
                        HStack {
                            Text(group.label)
                            Spacer()
                            Text("\(count)/\(group.items.count)")
                            Image(systemName: isExpanded(group) ? "chevron.up" : "chevron.down")
                        }
                    }
                }
            }
        }
        .navigationTitle("Milestones")
        .live([.activity], id: profile?.id ?? "", into: $entries) { [profile] in
            guard let profile else { return [] }
            return try await Repositories.shared.activities.ofTypes(familyId: profile.familyId, profileId: profile.id, [.MILESTONE])
        }
    }

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
                Text("Loading…").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Vaccinations")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add") { app.openEntry(.new(kind: .VACCINE)) }
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
            Text("\(given) of \(counted.count) scheduled doses given").font(.headline)
            if entries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No vaccines logged yet").font(.subheadline.weight(.semibold))
                    Text("Log the vaccines \(profile.name) has already had and Nestly will track what's due next.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Add vaccination") { app.openEntry(.new(kind: .VACCINE)) }
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
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(stateColor(status.state)).frame(width: 10, height: 10).padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(status.dose.vaccineName) — dose \(status.dose.doseNumber)").foregroundStyle(.primary)
                    Text(subtitle(status)).font(.caption).foregroundStyle(.secondary)
                    if let note = status.dose.note { Text(note).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer()
                Text(stateLabel(status.state)).font(.caption.weight(.semibold)).foregroundStyle(stateColor(status.state))
            }
        }
    }

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
        case .GIVEN: .green
        case .OVERDUE: .red
        case .DUE: .orange
        case .UPCOMING: .secondary
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
                Text("Get an alert after a set time since the last activity of each type.").foregroundStyle(.secondary)
            }
            if let reminders {
                ForEach(reminders) { reminder in
                    let label = ReminderLogic.label(reminder.kind)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(label, isOn: Binding(get: { reminder.enabled }, set: { setEnabled(reminder, $0) }))
                        Button("Every \(Format.duration(Int64(reminder.intervalMinutes) * 60)) after last \(label.lowercased())") {
                            editing = reminder
                        }
                        .font(.subheadline)
                    }
                }
            } else if caregiverId == nil {
                Text("Loading…").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
            if let message { Text(message).font(.footnote).foregroundStyle(.red) }
        }
        .navigationTitle("Reminders")
        .sheet(item: $editing) { reminder in
            DurationEditor(title: "\(ReminderLogic.label(reminder.kind)) interval", initialSeconds: Int64(reminder.intervalMinutes) * 60, showSeconds: false) { seconds in
                update(reminder.with { $0.intervalMinutes = max(1, Int(seconds / 60)) })
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
