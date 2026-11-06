import NestlyCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Account tab (spec §18)

struct AccountTab: View {
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family

    var body: some View {
        List {
            Section {
                NavigationLink(value: Route.family) { familyHeader }
            }
            Section {
                link("Settings", .system("gearshape.fill"), .settings)
                link("Subscription", .system("star.fill"), .subscription)
                link("Help", .system("questionmark.circle.fill"), .help)
            }
            Section("Data") {
                link("Import / Export CSV", .system("arrow.up.arrow.down"), .importExport)
            }
            Section("Share & Social") {
                Button {} label: { IconRow(title: "Share Nestly with Friends", icon: .system("square.and.arrow.up.fill"), chevron: false) }
                Button {} label: { IconRow(title: "Rate Nestly", icon: .system("hand.thumbsup.fill"), chevron: false) }
            }
        }
        .navigationTitle("Account")
    }

    private var familyHeader: some View {
        let profiles = family.profiles ?? []
        let caregivers = family.caregivers.count
        return HStack(spacing: Space.m) {
            HStack(spacing: -10) {
                ForEach(profiles.prefix(3)) { child in
                    ChildAvatar(name: child.name, size: 48)
                        .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(profiles.isEmpty ? "Family" : ListFormatter.localizedString(byJoining: profiles.map(\.name)))
                    .font(.rounded(.headline))
                    .lineLimit(1)
                Text(caregivers == 1 ? "1 caregiver" : "\(caregivers) caregivers")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Manage children, caregivers and invites")
    }

    private func link(_ title: String, _ icon: NestlyIcon, _ route: Route) -> some View {
        NavigationLink(value: route) { IconRow(title: title, icon: icon, chevron: false) }
    }
}

// MARK: - Family (spec §18.1)

struct FamilyView: View {
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    @State private var editingChild: ProfileEntity?
    @State private var addingChild = false
    @State private var addingCaregiver = false
    @State private var caregiverName = ""
    @State private var invite: String?
    @State private var message: String?
    @State private var working = false

    var body: some View {
        let profiles = family.profiles ?? []
        List {
            Section("Children") {
                ForEach(profiles) { child in
                    Button { editingChild = child } label: {
                        HStack(spacing: Space.m) {
                            ChildAvatar(name: child.name, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(child.name).foregroundStyle(Color.primary)
                                if let birth = child.birthDate, let age = Format.age(birth) {
                                    Text(age).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if child.id == family.selectedProfile?.id {
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Palette.accent)
                                    .accessibilityLabel("Selected")
                            }
                        }
                        .foregroundStyle(Color.primary)
                    }
                    .accessibilityHint("Edit child")
                }
                Button { addingChild = true } label: { Label("Add Child", systemImage: "plus") }
            }
            Section("Caregivers") {
                ForEach(family.caregivers) { caregiver in
                    let isMe = caregiver.id == family.currentCaregiver?.id
                    Button {
                        if !isMe { app.repos.family.setCurrentCaregiver(caregiver.id) }
                    } label: {
                        HStack(spacing: Space.m) {
                            IconTile(icon: .family, tint: isMe ? Palette.accent : .secondary, size: 32)
                            Text(caregiver.name).foregroundStyle(Color.primary)
                            Spacer()
                            if isMe {
                                StatusPill(text: "You", tint: Palette.accent)
                            } else {
                                Text("Tap if this is you").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(Color.primary)
                    }
                }
                Button { caregiverName = ""; addingCaregiver = true } label: { Label("Add Caregiver", systemImage: "plus") }
            }
            Section {
                Button { Task { await createInvite() } } label: {
                    Label(working ? "Creating…" : "Create Invite Code", systemImage: "envelope.badge.person.crop")
                }
                .disabled(working || family.currentFamilyId == nil)
                if let invite {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(invite)
                            .font(.rounded(.title2, weight: .bold))
                            .monospaced()
                            .textSelection(.enabled)
                        Text("Share this code with another caregiver.").font(.footnote).foregroundStyle(.secondary)
                        HStack(spacing: Space.m) {
                            Button { UIPasteboard.general.string = invite; Haptics.success() } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            ShareLink(item: "Join our family on Nestly with invite code \(invite)") {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, Space.xs)
                    }
                    .padding(.vertical, Space.xs)
                }
            } header: {
                Text("Invite")
            }
            if let message {
                Section { Text(message).foregroundStyle(Palette.critical) }
            }
        }
        .navigationTitle("Family")
        .sheet(item: $editingChild) { child in
            ChildForm(title: "Edit child", initial: child, askCaregiverName: false) { name, sex, birth, _ in
                var row = child
                row.name = name
                row.sex = sex
                row.birthDate = birth
                try await app.repos.family.updateChild(row)
            }
        }
        .sheet(isPresented: $addingChild) {
            ChildForm(title: "Add child", askCaregiverName: family.caregivers.isEmpty) { name, sex, birth, caregiver in
                let child = try await app.repos.family.addChild(name: name, sex: sex, birthDate: birth, caregiverName: caregiver)
                app.prefs.setSelectedProfile(child.id)
            }
        }
        .alert("Add caregiver", isPresented: $addingCaregiver) {
            TextField("Name", text: $caregiverName)
            Button("Cancel", role: .cancel) {}
            Button("Add") { Task { await addCaregiver() } }
        }
    }

    private func createInvite() async {
        guard let familyId = family.currentFamilyId else { return }
        working = true
        defer { working = false }
        do {
            invite = try await app.repos.family.createInvite(familyId: familyId)
            message = nil
        } catch {
            message = FriendlyError.message(error)
        }
    }

    private func addCaregiver() async {
        let name = caregiverName.trimmed
        guard !name.isEmpty, let familyId = family.currentFamilyId else { return }
        do {
            _ = try await app.repos.family.addCaregiver(familyId: familyId, name: name)
            message = nil
        } catch {
            message = FriendlyError.message(error)
        }
    }
}

// MARK: - Settings (spec §18.2)

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    @Environment(Preferences.self) private var prefs
    @State private var editingDefault = false
    @State private var defaultText = ""
    #if DEBUG
    @State private var confirmClear = false
    @State private var clearMessage: String?
    #endif

    var body: some View {
        List {
            Section {
                NavigationLink(value: Route.email) { IconRow(title: "Email & Password", icon: .system("envelope.fill"), chevron: false) }
                NavigationLink(value: Route.units) { IconRow(title: "Units", icon: .system("ruler.fill"), chevron: false) }
                NavigationLink(value: Route.communication) { IconRow(title: "Communication", icon: .system("bell.fill"), chevron: false) }
                Button { app.showNightstand = true } label: {
                    IconRow(title: "Nightstand Mode", icon: .system("moon.fill"), tint: Palette.sleep)
                }
            }
            Section {
                Button {
                    defaultText = prefs.defaultBottleMl.map { Format.number(Units.mlToDisplay($0, prefs.units.volume), maxDecimals: 1) } ?? ""
                    editingDefault = true
                } label: {
                    IconRow(
                        title: "Default Bottle Amount",
                        icon: .bottle,
                        tint: Palette.feed,
                        value: prefs.defaultBottleMl.map { Format.volume($0, prefs.units) } ?? "Off",
                        chevron: false
                    )
                }
            } footer: {
                Text("Used by the widget, Siri and the Nightstand Log Feed button.")
            }
            Section {
                Button(role: .destructive) { Task { await app.signOut() } } label: {
                    Text("Log Out").frame(maxWidth: .infinity)
                }
            }
            #if DEBUG
            Section("Debug") {
                Button("Clear all data", role: .destructive) { confirmClear = true }
                if let clearMessage { Text(clearMessage).font(.footnote) }
            }
            #endif
        }
        .navigationTitle("Settings")
        .alert("Default bottle amount", isPresented: $editingDefault) {
            TextField(Units.volumeLabel(prefs.units.volume), text: $defaultText).keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("OK") {
                let value = Double(defaultText.replacingOccurrences(of: ",", with: ".").trimmed)
                prefs.setDefaultBottleMl(value.flatMap { $0 > 0 ? Units.displayToMl($0, prefs.units.volume) : nil })
                WidgetRefresher.reloadAll()
            }
        } message: {
            Text("Tap to change it. Leave the amount empty and tap OK to turn the default off.")
        }
        #if DEBUG
        .confirmationDialog("Clear all data?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear all data", role: .destructive) { Task { await clearAll() } }
        } message: {
            Text("Deletes this family's children, activities, reminders, appointments, notes and photos for everyone.")
        }
        #endif
    }

    #if DEBUG
    private func clearAll() async {
        guard let familyId = family.currentFamilyId else { return }
        do {
            try? await app.repos.photos.deleteAll(familyId: familyId)
            try await app.repos.family.clearFamilyData(familyId: familyId)
            TimerGroup.allCases.forEach(TimerControl.clear)
            clearMessage = "Cleared."
        } catch {
            clearMessage = FriendlyError.message(error)
        }
    }
    #endif
}

struct UnitsView: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        let units = prefs.units
        Form {
            Section {
                picker("Volume", units.volume, VolumeUnit.allCases, Units.volumeLabel) { u in prefs.setUnits(units.with { $0.volume = u }) }
                picker("Weight", units.weight, WeightUnit.allCases, Units.weightLabel) { u in prefs.setUnits(units.with { $0.weight = u }) }
                picker("Length", units.length, LengthUnit.allCases, Units.lengthLabel) { u in prefs.setUnits(units.with { $0.length = u }) }
                picker("Temperature", units.temp, TempUnit.allCases, Units.tempLabel) { u in prefs.setUnits(units.with { $0.temp = u }) }
            } footer: {
                Text("Storage stays metric. These settings only change what you see and enter.")
            }
        }
        .navigationTitle("Units")
        .onChange(of: prefs.units) { _, _ in WidgetRefresher.reloadAll() }
    }

    private func picker<U: Hashable>(_ title: String, _ value: U, _ all: [U], _ label: @escaping (U) -> String, set: @escaping (U) -> Void) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            Picker(title, selection: Binding(get: { value }, set: set)) {
                ForEach(all, id: \.self) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

extension UnitPrefs {
    func with(_ change: (inout UnitPrefs) -> Void) -> UnitPrefs {
        var copy = self
        change(&copy)
        return copy
    }
}

struct EmailView: View {
    @State private var email: String?

    var body: some View {
        Form {
            Section("Email") {
                Text(email ?? "—").textSelection(.enabled)
            }
            Section {
                Text("Your account is used to share this family's data with other caregivers through Supabase. Data is stored online only; there is no local copy on this device.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Email & password")
        .task { email = Backend.shared.currentEmail }
    }
}

/// Parity stub: toggles are not persisted.
struct CommunicationView: View {
    @State private var reminders = true
    @State private var updates = false

    var body: some View {
        Form {
            Toggle(isOn: $reminders) { IconRow(title: "Reminders", icon: .reminder, chevron: false) }
            Toggle(isOn: $updates) { IconRow(title: "Product Updates", icon: .system("sparkles"), chevron: false) }
        }
        .tint(Palette.accent)
        .navigationTitle("Communication")
    }
}

struct SubscriptionView: View {
    var body: some View {
        Form {
            Section("Current Plan") {
                IconRow(title: "Nestly Free", icon: .system("star.fill"), subtitle: "All tracking features included", chevron: false)
            }
        }
        .navigationTitle("Subscription")
    }
}

struct HelpView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        Form {
            Section {
                Link(destination: URL(string: "mailto:help@nestly.app")!) {
                    IconRow(title: "Contact Support", icon: .system("envelope.fill"), subtitle: "help@nestly.app", chevron: false)
                }
                Button {} label: { IconRow(title: "FAQs", icon: .system("questionmark.bubble.fill")) }
                Button {} label: { IconRow(title: "Legal", icon: .system("doc.text.fill")) }
                Button {} label: { IconRow(title: "Advanced Settings", icon: .system("slider.horizontal.3")) }
            }
            Section {
                IconRow(title: "Version", icon: .system("info.circle.fill"), tint: .secondary, value: version, chevron: false)
            }
            Section("Acknowledgements") {
                Text("Activity icons from Material Symbols by Google, via Streamline. Licensed under the Apache License 2.0.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Help")
    }
}

// MARK: - Import / Export (spec §19)

struct CsvDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    let text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct ImportExportView: View {
    enum ImportKind { case nara, nestly }

    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    @State private var importKind: ImportKind?
    @State private var exportDoc: CsvDocument?
    @State private var exportName = "nestly_export.csv"
    @State private var exporting = false
    @State private var busy = false
    @State private var message: String?
    @State private var counts: [ActivityType: Int]?

    var body: some View {
        List {
            Section {
                Button { importKind = .nara } label: { IconRow(title: "Import from Nara", icon: .system("square.and.arrow.down.fill"), chevron: false) }
                Button { Task { await export() } } label: { IconRow(title: "Export Nestly CSV", icon: .system("square.and.arrow.up.fill"), chevron: false) }
                Button { importKind = .nestly } label: { IconRow(title: "Import Nestly CSV", icon: .system("tray.and.arrow.down.fill"), chevron: false) }
            }
            .disabled(busy)
            if busy || message != nil {
                Section {
                    HStack(spacing: Space.m) {
                        if busy { ProgressView() }
                        Text(message ?? "Working…").font(.subheadline)
                    }
                }
            }
            Section("Activities in Nestly") {
                if let counts {
                    if counts.isEmpty { Text("No activities yet.").foregroundStyle(.secondary) }
                    ForEach(ActivityType.allCases.filter { (counts[$0] ?? 0) > 0 }, id: \.self) { type in
                        IconRow(title: type.displayName, icon: type.icon, tint: type.color, value: "\(counts[type] ?? 0)", chevron: false)
                    }
                } else {
                    HStack(spacing: Space.m) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Import / Export")
        .fileImporter(isPresented: Binding(get: { importKind != nil }, set: { if !$0 { importKind = nil } }),
                      allowedContentTypes: importKind == .nestly ? [.commaSeparatedText, .plainText, .data] : ImportTypes.all) { result in
            let kind = importKind
            importKind = nil
            if let kind { run(kind, result) }
        }
        .fileExporter(isPresented: $exporting, document: exportDoc, contentType: .commaSeparatedText, defaultFilename: exportName) { result in
            if case let .failure(error) = result { message = error.localizedDescription }
        }
        .live([.activity], id: family.currentFamilyId ?? "", into: $counts) { [familyId = family.currentFamilyId] in
            guard let familyId else { return [:] }
            return try await Repositories.shared.activities.fetchCountsByType(familyId: familyId)
        }
    }

    private func export() async {
        busy = true
        message = "Exporting…"
        defer { busy = false }
        do {
            let result = try await DataTransfer(repos: app.repos).exportCsv()
            exportDoc = CsvDocument(text: result.csv)
            exportName = result.filename
            message = result.message
            exporting = true
        } catch {
            message = "Export failed. Check your connection and try again."
        }
    }

    private func run(_ kind: ImportKind, _ result: Result<URL, Error>) {
        guard case let .success(url) = result, let data = ImportTypes.read(url) else {
            message = "Could not open the selected file"
            return
        }
        busy = true
        message = kind == .nara ? "Importing your Nara history…" : "Importing…"
        Task {
            defer { busy = false }
            do {
                let transfer = DataTransfer(repos: app.repos)
                let imported = kind == .nara ? try await transfer.importNara(data) : try await transfer.importNestly(data)
                message = imported.importScreenMessage(source: kind == .nara ? "Nara" : "Nestly CSV")
                app.scheduleReschedule()
            } catch let error as ImportError {
                message = error.message
            } catch {
                message = "Import failed. Check your connection and try again."
            }
        }
    }
}
