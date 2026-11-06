import NestlyCore
import SwiftUI

// MARK: - Appointments (spec §17.1–17.2)

struct AppointmentsView: View {
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    @State private var appointments: [AppointmentEntity]?

    var body: some View {
        let profile = family.selectedProfile
        List {
            if let appointments {
                Clock(interval: 60) { now in
                    let upcoming = appointments.filter { $0.startsAt >= now }.sorted { $0.startsAt < $1.startsAt }
                    let past = appointments.filter { $0.startsAt < now }.sorted { $0.startsAt > $1.startsAt }
                    if appointments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No appointments yet").font(.headline)
                            Text("Keep track of \(profile?.name ?? "your child")'s doctor visits, with questions to ask and a reminder before each one.")
                                .foregroundStyle(.secondary)
                            Button("Add appointment") { app.push(.appointment(id: nil)) }
                        }
                    }
                    if !upcoming.isEmpty {
                        Section("Upcoming") {
                            ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, a in
                                row(a, next: index == 0, now: now)
                            }
                        }
                    }
                    if !past.isEmpty {
                        Section("Past") {
                            ForEach(past) { row($0, next: false, now: now) }
                        }
                    }
                }
            } else {
                Text("Loading…").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Appointments")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { app.push(.appointment(id: nil)) } label: { Image(systemName: "plus") }.accessibilityLabel("Add appointment")
            }
        }
        .live([.appointment], id: profile?.id ?? "", into: $appointments) { [profile] in
            guard let profile else { return [] }
            return try await Repositories.shared.appointments.list(profileId: profile.id)
        }
    }

    private func row(_ a: AppointmentEntity, next: Bool, now: EpochMs) -> some View {
        Button { app.push(.appointment(id: a.id)) } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Text(Format.pattern("MMM", a.startsAt).uppercased()).font(.caption2.weight(.bold))
                    Text(Format.pattern("d", a.startsAt)).font(.title3.weight(.semibold))
                }
                .frame(width: 48, height: 48)
                .background(CardKind.HEALTH.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    if next {
                        Text("Next appointment").font(.caption2.weight(.bold)).foregroundStyle(CardKind.HEALTH.color)
                    }
                    Text(a.title).font(.headline)
                    let place = [a.doctorName, a.location].compactMap { $0?.trimmedNilIfEmpty }.joined(separator: " · ")
                    if !place.isEmpty { Text(place).font(.subheadline).foregroundStyle(.secondary) }
                    if let progress = NotesProgress(a.notes) {
                        Text(progress.done > 0 ? "\(progress.done)/\(progress.total) questions asked" : "\(progress.total) questions to ask")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if a.reminderLead != .NONE {
                        Text("Reminder: \(a.reminderLead.label)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(Format.countdown(a.startsAt, now: now)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .foregroundStyle(.primary)
    }
}

struct AppointmentDetailView: View {
    let appointmentId: String?
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AppointmentEntity?
    @State private var past: [AppointmentEntity] = []
    @State private var preview = false
    @State private var message: String?
    @State private var saving = false
    @State private var confirmDelete = false

    private var isNew: Bool { appointmentId == nil }

    var body: some View {
        Form {
            if let binding = Binding($draft) {
                Section {
                    TextField("Title", text: binding.title)
                    suggestions(titleSuggestions(binding.wrappedValue.title)) { binding.wrappedValue.title = $0 }
                    TextField("Doctor", text: optional(binding.doctorName))
                    suggestions(valueSuggestions(\.doctorName, binding.wrappedValue.doctorName)) { binding.wrappedValue.doctorName = $0 }
                    TextField("Location", text: optional(binding.location))
                    suggestions(valueSuggestions(\.location, binding.wrappedValue.location)) { binding.wrappedValue.location = $0 }
                    DatePicker("Date & Time", selection: binding.startsAt.date)
                    Picker("Reminder", selection: Binding(get: { binding.wrappedValue.reminderLead }, set: { lead in
                        binding.wrappedValue.reminderLead = lead
                        if lead != .NONE { Task { _ = await NotificationScheduler.requestAuthorization() } }
                    })) {
                        ForEach(AppointmentReminderLead.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                FormattedNotesSection(title: "Notes & questions", text: optional(binding.notes), preview: $preview) { _ in
                    if !isNew { Task { await save(dismissAfter: false) } }
                }
                if let message {
                    Section { Text(message).foregroundStyle(.red) }
                }
                if !isNew {
                    Section {
                        Button("Delete appointment", role: .destructive) { confirmDelete = true }
                    }
                }
            } else if let message {
                Text(message).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(isNew ? "New appointment" : "Appointment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save(dismissAfter: true) } }.disabled(draft == nil || saving)
            }
        }
        .confirmationDialog("Delete appointment?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: {
            Text("This removes the appointment, its notes and its reminder.")
        }
        .task { await load() }
    }

    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0 })
    }

    @ViewBuilder
    private func suggestions(_ items: [String], pick: @escaping (String) -> Void) -> some View {
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(items, id: \.self) { item in
                        Button(item) { pick(item) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private func matching(_ candidates: [String], _ typed: String?) -> [String] {
        let typed = (typed ?? "").trimmed.lowercased()
        var seen = Set<String>()
        return candidates.filter { c in
            let key = c.lowercased()
            guard !c.isBlank, key != typed, seen.insert(key).inserted else { return false }
            return typed.isEmpty || key.contains(typed)
        }
        .prefix(8).map { $0 }
    }

    private func titleSuggestions(_ typed: String) -> [String] {
        matching(past.map(\.title) + Catalogs.appointmentTitleHints, typed)
    }

    private func valueSuggestions(_ key: KeyPath<AppointmentEntity, String?>, _ typed: String?) -> [String] {
        matching(past.compactMap { $0[keyPath: key] }, typed)
    }

    private func load() async {
        guard let profile = family.selectedProfile else { return }
        past = (try? await app.repos.appointments.list(profileId: profile.id).sorted { $0.startsAt > $1.startsAt }) ?? []
        if let appointmentId {
            do {
                if let row = try await app.repos.appointments.get(appointmentId) { draft = row } else { message = "This appointment was deleted." }
            } catch {
                message = FriendlyError.message(error)
            }
        } else if draft == nil {
            let now = nowMs()
            let tomorrow = LocalDate.today().plusDays(1).startOfDayMs() + 9 * 3_600_000
            draft = AppointmentEntity(
                id: newUUID(), familyId: profile.familyId, profileId: profile.id, title: "",
                startsAt: tomorrow, timeZone: TimeZone.current.identifier, reminderLead: .ONE_DAY,
                createdAt: now, updatedAt: now
            )
        }
    }

    private func save(dismissAfter: Bool) async {
        guard var row = draft, !saving else { return }
        row.title = row.title.trimmed
        row.doctorName = row.doctorName?.trimmedNilIfEmpty
        row.location = row.location?.trimmedNilIfEmpty
        row.notes = row.notes?.isBlank == true ? nil : row.notes
        guard !row.title.isEmpty else {
            message = "Give the appointment a title — pick a hint or type your own."
            return
        }
        saving = true
        defer { saving = false }
        do {
            let saved = try await app.repos.appointments.save(row, isNew: isNew)
            await NotificationScheduler.schedule(saved)
            message = nil
            if dismissAfter { dismiss() } else { draft = saved }
        } catch let conflict as ConflictError {
            if let latest = try? await app.repos.appointments.get(row.id) { draft = latest }
            message = conflict.errorDescription
        } catch {
            message = FriendlyError.message(error)
        }
    }

    private func delete() async {
        guard let row = draft else { return }
        do {
            try await app.repos.appointments.delete(row)
            NotificationScheduler.cancel(appointmentId: row.id)
            dismiss()
        } catch {
            message = (error as? ConflictError)?.errorDescription ?? FriendlyError.message(error)
        }
    }
}

// MARK: - Notes (spec §17.4)

struct NotesView: View {
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    @State private var notes: [NoteEntity]?

    var body: some View {
        let profile = family.selectedProfile
        List {
            if let notes {
                if notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No notes yet").font(.headline)
                        Text("Notes are shared with everyone in your family — routines, things to remember, questions and checklists.")
                            .foregroundStyle(.secondary)
                        Button("New note") { app.push(.note(id: nil)) }
                    }
                }
                Clock(interval: 60) { now in
                    ForEach(notes) { note in
                        Button { app.push(.note(id: note.id)) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(note.title.isBlank ? "Untitled" : note.title).font(.headline)
                                if let first = note.body.components(separatedBy: "\n").first(where: { !$0.isBlank }) {
                                    Text(first).lineLimit(1).foregroundStyle(.secondary)
                                }
                                let progress = NotesProgress(note.body).map { " · \($0.done) of \($0.total) done" } ?? ""
                                Text("Edited \(Format.relativeDay(note.updatedAt, now: now))\(progress)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            } else {
                Text("Loading…").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Notes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { app.push(.note(id: nil)) } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("New note")
            }
        }
        .live([.note], id: profile?.id ?? "", into: $notes) { [profile] in
            guard let profile else { return [] }
            return try await Repositories.shared.notes.list(profileId: profile.id)
        }
    }
}

struct NoteDetailView: View {
    let noteId: String?
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NoteEntity?
    @State private var preview = false
    @State private var message: String?
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var created = false

    private var isNew: Bool { noteId == nil && !created }

    var body: some View {
        Form {
            if let binding = Binding($draft) {
                Section("Header") {
                    TextField("e.g. Bedtime routine", text: binding.title)
                }
                FormattedNotesSection(title: "Note", text: binding.body, preview: $preview) { _ in
                    if !isNew { Task { await save(dismissAfter: false) } }
                }
                if let message {
                    Section { Text(message).foregroundStyle(.red) }
                }
                if !isNew {
                    Section {
                        Button("Delete note", role: .destructive) { confirmDelete = true }
                    }
                }
            } else if let message {
                Text(message).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(isNew ? "New note" : "Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save(dismissAfter: true) } }.disabled(draft == nil || saving)
            }
        }
        .confirmationDialog("Delete note?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: {
            Text("This removes the note for everyone in your family.")
        }
        .task { await load() }
    }

    private func load() async {
        if let noteId {
            do {
                if let row = try await app.repos.notes.get(noteId) {
                    draft = row
                    preview = NotesProgress(row.body) != nil
                } else {
                    message = "This note was deleted."
                }
            } catch {
                message = FriendlyError.message(error)
            }
        } else if draft == nil, let profile = family.selectedProfile {
            let now = nowMs()
            draft = NoteEntity(id: newUUID(), familyId: profile.familyId, profileId: profile.id, createdAt: now, updatedAt: now)
        }
    }

    private func save(dismissAfter: Bool) async {
        guard var row = draft, !saving else { return }
        row.title = row.title.trimmed
        guard !row.title.isEmpty || !row.body.isBlank else {
            message = "Add a header or some text."
            return
        }
        saving = true
        defer { saving = false }
        do {
            let saved = try await app.repos.notes.save(row, isNew: isNew)
            created = true
            message = nil
            if dismissAfter { dismiss() } else { draft = saved }
        } catch let conflict as ConflictError {
            if let latest = try? await app.repos.notes.get(row.id) { draft = latest }
            message = conflict.errorDescription
        } catch {
            message = FriendlyError.message(error)
        }
    }

    private func delete() async {
        guard let row = draft else { return }
        do {
            try await app.repos.notes.delete(row)
            dismiss()
        } catch {
            message = (error as? ConflictError)?.errorDescription ?? FriendlyError.message(error)
        }
    }
}
