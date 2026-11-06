import NestlyCore
import PhotosUI
import SwiftUI

/// Create / edit sheet for every entry kind (spec §12).
struct EntrySheet: View {
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @State private var c: EntryController
    @State private var confirmDelete = false
    @State private var confirmDiscard = false

    init(request: EntryRequest) {
        _c = State(initialValue: EntryController(request: request, repos: .shared))
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: c.anyTimerRunning ? 1 : 30)) { context in
                let now = context.date.epochMs
                Form {
                    if !c.loaded {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else {
                        EntryForm(c: c, now: now)
                        Section {
                            TextField("Notes", text: $c.draft.note, axis: .vertical).lineLimit(3 ... 8)
                        }
                        PhotoSection(path: $c.draft.photoPath)
                        if c.isEditing {
                            Section {
                                Button("Delete", role: .destructive) { confirmDelete = true }
                            }
                        }
                    }
                    if let error = c.error {
                        Section { Text(error).foregroundStyle(.red) }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            if c.anyTimerActive { confirmDiscard = true } else { dismiss() }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(!c.canSave(now) || c.saving)
                    }
                }
            }
            .navigationTitle(c.kind.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await c.load(profile: family.selectedProfile) }
        .onReceive(NotificationCenter.default.publisher(for: ActiveTimerStore.didChange)) { _ in c.refreshTimers() }
        .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { if await c.delete() { dismiss() } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Discard this timer?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                c.discardTimers()
                dismiss()
            }
            Button("Keep running") { dismiss() }
            Button("Cancel", role: .cancel) {}
        }
        .alert(defaultPromptTitle, isPresented: Binding(get: { c.defaultPrompt != nil }, set: { if !$0 { c.defaultPrompt = nil; dismiss() } })) {
            Button(c.defaultBottleMl == nil ? "Yes, set default" : "Yes, update default") {
                prefs.setDefaultBottleMl(c.defaultPrompt)
                c.defaultPrompt = nil
                dismiss()
            }
            Button(c.defaultBottleMl == nil ? "Not now" : "No, keep default", role: .cancel) {
                c.defaultPrompt = nil
                dismiss()
            }
        } message: {
            Text(defaultPromptMessage)
        }
    }

    private var defaultPromptTitle: String { c.defaultBottleMl == nil ? "Set as default amount?" : "Update default amount?" }

    private var defaultPromptMessage: String {
        guard let pending = c.defaultPrompt else { return "" }
        let p = Format.volume(pending, prefs.units)
        if let current = c.defaultBottleMl {
            return "Your default bottle amount is \(Format.volume(current, prefs.units)). Change it to \(p) for future feeds? This feed will use \(p) either way."
        }
        return "Use \(p) as your default bottle amount? It will pre-fill future bottle feeds. This feed will use \(p) either way."
    }

    private func save() {
        Task {
            if await c.save(profile: family.selectedProfile, caregiverId: family.currentCaregiver?.id) { dismiss() }
        }
    }
}

/// The kind-specific fields.
struct EntryForm: View {
    @Bindable var c: EntryController
    let now: EpochMs
    @Environment(Preferences.self) private var prefs

    var body: some View {
        let d = c.effectiveDraft(now)
        switch c.kind {
        case .BREASTFEED:
            BreastfeedFields(c: c, d: d)
        case .BOTTLE:
            BottleFields(c: c)
        case .COMBO:
            Section {
                Picker("Part", selection: $c.draft.comboTab) {
                    Text("Breastfeed").tag(0)
                    Text("Bottle Feed").tag(1)
                }
                .pickerStyle(.segmented)
            }
            if c.draft.comboTab == 0 { BreastfeedFields(c: c, d: d) } else { BottleFields(c: c) }
        case .SOLIDS:
            SolidsFields(c: c)
        case .PUMP:
            PumpFields(c: c, d: d)
        case .DIAPER:
            DiaperFields(c: c)
        case .SLEEP:
            SleepFields(c: c, d: d)
        case .ROUTINE:
            RoutineFields(c: c)
        case .BABY_FIRST:
            Section {
                StartRow(c: c, title: "Date", dateOnly: true)
                TextField("Baby First", text: $c.draft.babyFirstTitle)
            }
        case .GROWTH:
            Section {
                StartRow(c: c, title: "Date", dateOnly: true)
                UnitField(title: "Weight", base: $c.draft.weightKg, toDisplay: { Units.kgToDisplay($0, prefs.units.weight) }, fromDisplay: { Units.displayToKg($0, prefs.units.weight) }, unit: Units.weightLabel(prefs.units.weight))
                UnitField(title: "Height", base: $c.draft.heightCm, toDisplay: { Units.cmToDisplay($0, prefs.units.length) }, fromDisplay: { Units.displayToCm($0, prefs.units.length) }, unit: Units.lengthLabel(prefs.units.length), decimals: 1)
                UnitField(title: "Head Size", base: $c.draft.headCm, toDisplay: { Units.cmToDisplay($0, prefs.units.length) }, fromDisplay: { Units.displayToCm($0, prefs.units.length) }, unit: Units.lengthLabel(prefs.units.length), decimals: 1)
            }
        case .MILESTONE:
            Section {
                if MilestoneCatalog.byKey(c.draft.milestoneKey) != nil {
                    Text(c.draft.milestoneTitle).font(.headline)
                } else {
                    TextField("Milestone", text: $c.draft.milestoneTitle)
                }
                StartRow(c: c, title: "Date", dateOnly: true)
            }
        case .MEDICAL:
            MedicalFields(c: c)
        case .VACCINE:
            VaccineFields(c: c)
        case .VITAMIN_D:
            Section {
                StartRow(c: c, title: "Time")
                DecimalField(title: "Dose", value: $c.draft.dose)
                ChipFlow(items: Catalogs.vitaminDDoseUnits, label: { $0 }, isSelected: { c.draft.doseUnit == $0 }) { c.draft.doseUnit = $0 }
            }
        }
    }
}

/// Start time with separate date/time targets; timed kinds show "Add" until set.
struct StartRow: View {
    @Bindable var c: EntryController
    var title = "Start Time"
    var dateOnly = false
    var shownMs: EpochMs?

    var body: some View {
        if !c.draft.startTimeSet, shownMs == nil {
            HStack {
                Text(title)
                Spacer()
                Button("Add") { c.setStart(nowMs()) }
            }
        } else {
            DatePicker(
                title,
                selection: Binding(get: { Date(epochMs: shownMs ?? c.draft.startTime) }, set: { c.setStart($0.epochMs) }),
                in: ...Date().addingTimeInterval(dateOnly ? 0 : 3600),
                displayedComponents: dateOnly ? [.date] : [.date, .hourAndMinute]
            )
        }
    }
}

private struct TimerKeyEdit: Identifiable {
    let key: TimerKey
    let seconds: Int64
    var id: String { key.rawValue }
}

struct BreastfeedFields: View {
    @Bindable var c: EntryController
    let d: EntryDraft
    @State private var editing: TimerKeyEdit?

    var body: some View {
        Section {
            HStack(spacing: 16) {
                side(.BREAST_LEFT, "Left", d.leftSec, .LEFT)
                side(.BREAST_RIGHT, "Right", d.rightSec, .RIGHT)
            }
            .padding(.vertical, 6)
            StartRow(c: c, shownMs: c.draft.startTimeSet ? nil : (d.leftSec + d.rightSec > 0 ? d.startTime : nil))
            LabeledContent("Total Time", value: Format.duration(d.leftSec + d.rightSec))
        }
        .sheet(item: $editing) { edit in
            DurationEditor(title: "Edit time", initialSeconds: edit.seconds) { c.setDuration(edit.key, seconds: $0) }
        }
    }

    private func side(_ key: TimerKey, _ label: String, _ seconds: Int64, _ breast: BreastSide) -> some View {
        let running = c.usesTimers && c.timers[key]?.isRunning == true
        return VStack(spacing: 6) {
            Button {
                if c.usesTimers { c.toggle(key) } else { editing = TimerKeyEdit(key: key, seconds: seconds) }
            } label: {
                VStack(spacing: 4) {
                    Text(label).font(.headline)
                    Text(Format.stopwatch(seconds)).font(.title2.monospacedDigit())
                    if c.usesTimers {
                        Image(systemName: running ? "pause.fill" : "play.fill").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 96)
                .background(running ? CardKind.FEED.color.opacity(0.25) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Edit time") { editing = TimerKeyEdit(key: key, seconds: seconds) }
            }
            Text(c.lastSide == breast ? "last side" : " ").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct BottleFields: View {
    @Bindable var c: EntryController
    @Environment(Preferences.self) private var prefs

    var body: some View {
        let disabled = prefs.disabledToggles
        Section {
            HStack {
                if !disabled.contains(.BOTTLE_BREAST_MILK) || c.draft.milkType == .BREAST_MILK { milk(.BREAST_MILK, "Breast Milk") }
                if !disabled.contains(.BOTTLE_FORMULA) || c.draft.milkType == .FORMULA { milk(.FORMULA, "Formula") }
            }
            StartRow(c: c)
            UnitField(
                title: "Amount", base: $c.draft.bottleMl,
                toDisplay: { Units.mlToDisplay($0, prefs.units.volume) }, fromDisplay: { Units.displayToMl($0, prefs.units.volume) },
                unit: Units.volumeLabel(prefs.units.volume), decimals: prefs.units.volume == .OZ ? 1 : 0,
                onUserEdit: { c.amountTypedManually = true }
            )
            if c.draft.bottleMl == nil, let last = c.lastBottleMl {
                HStack {
                    Text("Use last amount: \(Format.volume(last, prefs.units))?")
                    Spacer()
                    Button("Yes") { c.draft.bottleMl = last }
                }
            }
            if c.draft.milkType == .FORMULA {
                TextField("Formula", text: Binding(get: { c.draft.formulaName ?? "" }, set: { c.draft.formulaName = $0.isEmpty ? nil : $0 }))
            }
        }
    }

    private func milk(_ type: MilkType, _ label: String) -> some View {
        let selected = c.draft.milkType == type
        return Button {
            c.draft.milkType = selected ? nil : type
        } label: {
            Text(label).frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? CardKind.FEED.color.opacity(0.25) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct SolidsFields: View {
    @Bindable var c: EntryController
    @State private var adding = false
    @State private var newFood = ""

    var body: some View {
        Section {
            ChipFlow(items: MealType.allCases, label: \.label, isSelected: { c.draft.mealType == $0 }) { meal in
                c.draft.mealType = c.draft.mealType == meal ? nil : meal
            }
            StartRow(c: c)
        }
        Section("Food") {
            let custom = c.draft.foods.filter { !Catalogs.foods.contains($0) }
            ChipFlow(items: Catalogs.foods + custom, label: { $0 }, isSelected: { c.draft.foods.contains($0) }) { food in
                if let i = c.draft.foods.firstIndex(of: food) { c.draft.foods.remove(at: i) } else { c.draft.foods.append(food) }
            }
            Button("+ Add your own") { adding = true }
        }
        .alert("Food", isPresented: $adding) {
            TextField("Food", text: $newFood)
            Button("Add") {
                if let food = newFood.trimmedNilIfEmpty, !c.draft.foods.contains(food) { c.draft.foods.append(food) }
                newFood = ""
            }
            Button("Cancel", role: .cancel) { newFood = "" }
        }
    }
}

struct PumpFields: View {
    @Bindable var c: EntryController
    let d: EntryDraft
    @Environment(Preferences.self) private var prefs
    @State private var editingTotal = false

    var body: some View {
        let t = c.timers[.PUMP] ?? TimerState()
        Section {
            Picker("Mode", selection: $c.draft.pumpMode) {
                Text("Left / Right").tag(PumpMode.LEFT_RIGHT)
                Text("Total").tag(PumpMode.TOTAL)
            }
            .pickerStyle(.segmented)
            VStack(spacing: 10) {
                Text(Format.stopwatch(d.pumpSec)).font(.system(size: 44, weight: .semibold).monospacedDigit())
                if c.usesTimers {
                    HStack {
                        Button(t.isRunning ? "Pause Timer" : t.isIdle ? "Start Timer" : "Resume Timer") { c.toggle(.PUMP) }
                            .buttonStyle(.borderedProminent)
                        Button("Reset") { c.reset(.PUMP) }.buttonStyle(.bordered).disabled(t.isIdle)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            StartRow(c: c, shownMs: !c.draft.startTimeSet && !t.isIdle ? d.startTime : nil)
            Button { editingTotal = true } label: {
                LabeledContent("Total Time", value: d.pumpSec > 0 ? Format.duration(d.pumpSec) : "Add")
            }
            .foregroundStyle(.primary)
        }
        Section {
            let volume = prefs.units.volume
            let decimals = volume == .OZ ? 1 : 0
            if c.draft.pumpMode == .LEFT_RIGHT {
                UnitField(title: "Left Side Amount", base: $c.draft.pumpLeftMl, toDisplay: { Units.mlToDisplay($0, volume) }, fromDisplay: { Units.displayToMl($0, volume) }, unit: Units.volumeLabel(volume), decimals: decimals)
                UnitField(title: "Right Side Amount", base: $c.draft.pumpRightMl, toDisplay: { Units.mlToDisplay($0, volume) }, fromDisplay: { Units.displayToMl($0, volume) }, unit: Units.volumeLabel(volume), decimals: decimals)
                LabeledContent("Total", value: Format.volume(d.pumpTotalComputed ?? 0, prefs.units))
            } else {
                UnitField(title: "Total Amount", base: $c.draft.pumpTotalMl, toDisplay: { Units.mlToDisplay($0, volume) }, fromDisplay: { Units.displayToMl($0, volume) }, unit: Units.volumeLabel(volume), decimals: decimals)
            }
        }
        .sheet(isPresented: $editingTotal) {
            DurationEditor(title: "Total Time", initialSeconds: d.pumpSec) { c.setDuration(.PUMP, seconds: $0) }
        }
    }
}

struct DiaperFields: View {
    @Bindable var c: EntryController

    var body: some View {
        Section {
            StartRow(c: c, title: "Time")
            HStack {
                toggle("Wet", c.draft.wet) { c.draft.wet.toggle(); if c.draft.wet { c.draft.dry = false } }
                toggle("Dirty", c.draft.dirty) { c.draft.dirty.toggle(); if c.draft.dirty { c.draft.dry = false } }
                toggle("Dry", c.draft.dry) {
                    c.draft.dry.toggle()
                    if c.draft.dry { c.draft.wet = false; c.draft.dirty = false }
                }
            }
        }
        if c.draft.dirty {
            Section("Color") {
                ChipFlow(items: StoolColor.allCases, label: \.label, isSelected: { c.draft.stoolColor == $0 }, swatch: \.swatch) { color in
                    c.draft.stoolColor = c.draft.stoolColor == color ? nil : color
                }
            }
            Section("Texture") {
                ChipFlow(items: StoolTexture.allCases, label: \.label, isSelected: { c.draft.stoolTexture == $0 }) { texture in
                    c.draft.stoolTexture = c.draft.stoolTexture == texture ? nil : texture
                }
            }
        }
        Section { Toggle("Diaper Rash", isOn: $c.draft.rash) }
    }

    private func toggle(_ label: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? CardKind.DIAPER.color.opacity(0.3) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct SleepFields: View {
    @Bindable var c: EntryController
    let d: EntryDraft
    @State private var editingTotal = false

    var body: some View {
        let t = c.timers[.SLEEP] ?? TimerState()
        let total = d.endTime.map { max(0, ($0 - d.startTime) / 1000) } ?? 0
        Section {
            VStack(spacing: 10) {
                Text("Total Time").font(.caption).foregroundStyle(.secondary)
                Text(Format.stopwatch(total)).font(.system(size: 44, weight: .semibold).monospacedDigit())
                if c.usesTimers {
                    HStack {
                        Button(t.isRunning ? "Pause Timer" : t.isIdle ? "Start Timer" : "Resume Timer") { c.toggle(.SLEEP) }
                            .buttonStyle(.borderedProminent)
                        Button("Reset") { c.reset(.SLEEP) }.buttonStyle(.bordered).disabled(t.isIdle)
                    }
                } else {
                    Button("Edit time") { editingTotal = true }.font(.footnote)
                }
            }
            .frame(maxWidth: .infinity)
            StartRow(c: c, shownMs: !c.draft.startTimeSet && !t.isIdle ? d.startTime : nil)
            if c.usesTimers, !t.isIdle {
                LabeledContent("End Time", value: Format.time(d.endTime ?? d.startTime))
            } else if let end = c.draft.endTime {
                DatePicker("End Time", selection: Binding(get: { Date(epochMs: end) }, set: { c.draft.endTime = max($0.epochMs, c.draft.startTime) }), in: Date(epochMs: c.draft.startTime)..., displayedComponents: [.date, .hourAndMinute])
            } else {
                HStack {
                    Text("End Time")
                    Spacer()
                    Button("Add") {
                        if !c.draft.startTimeSet { c.setStart(nowMs() - 3_600_000) }
                        c.draft.endTime = max(nowMs(), c.draft.startTime)
                    }
                }
            }
        }
        .sheet(isPresented: $editingTotal) {
            DurationEditor(title: "Total Time", initialSeconds: total, showSeconds: false) { c.setDuration(.SLEEP, seconds: $0) }
        }
    }
}

struct RoutineFields: View {
    @Bindable var c: EntryController
    @State private var custom = ""

    var body: some View {
        Section {
            StartRow(c: c, title: "Time")
        }
        Section("Routine") {
            let current = c.draft.routineName
            let items = Catalogs.routines + (current.map { Catalogs.routines.contains($0) ? [] : [$0] } ?? [])
            ChipFlow(items: items, label: { $0 }, isSelected: { current == $0 }) { c.draft.routineName = current == $0 ? nil : $0 }
            HStack {
                TextField("Create your own", text: $custom)
                Button("Add") {
                    if let name = custom.trimmedNilIfEmpty { c.draft.routineName = name }
                    custom = ""
                }
                .disabled(custom.isBlank)
            }
        }
    }
}

struct MedicalFields: View {
    @Bindable var c: EntryController
    @Environment(Preferences.self) private var prefs

    var body: some View {
        let temp = prefs.units.temp
        Section {
            StartRow(c: c, title: "Time")
            UnitField(
                title: "Temperature", base: $c.draft.temperatureF,
                toDisplay: { temp == .F ? $0 : EntryBuilder.fahrenheitToCelsius($0) },
                fromDisplay: { temp == .F ? $0 : EntryBuilder.celsiusToFahrenheit($0) },
                unit: Units.tempLabel(temp), decimals: 1
            )
        }
        Section("Medication") {
            TextField("Name", text: Binding(get: { c.draft.medicationName ?? "" }, set: { c.draft.medicationName = $0.isEmpty ? nil : $0 }))
            DecimalField(title: "Dose", value: $c.draft.dose)
            ChipFlow(items: Catalogs.medicationDoseUnits, label: { $0 }, isSelected: { c.draft.doseUnit == $0 }) { unit in
                c.draft.doseUnit = c.draft.doseUnit == unit ? nil : unit
            }
        }
    }
}

struct VaccineFields: View {
    @Bindable var c: EntryController

    var body: some View {
        Section { StartRow(c: c, title: "Date", dateOnly: true) }
        Section("Vaccines") {
            let extra = c.draft.vaccines.filter { !Catalogs.vaccines.contains($0) }
            ForEach(Catalogs.vaccines + extra, id: \.self) { name in
                Button {
                    if let i = c.draft.vaccines.firstIndex(of: name) { c.draft.vaccines.remove(at: i) } else { c.draft.vaccines.append(name) }
                } label: {
                    HStack {
                        Text(name).foregroundStyle(.primary)
                        Spacer()
                        if c.draft.vaccines.contains(name) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                }
            }
        }
    }
}

struct PhotoSection: View {
    @Binding var path: String?
    @State private var item: PhotosPickerItem?
    @State private var error: String?

    var body: some View {
        Section {
            if let path {
                RemotePhoto(uri: path)
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Button("Remove Photo", role: .destructive) { self.path = nil }
            } else {
                PhotosPicker(selection: $item, matching: .images) { Label("Add Photo", systemImage: "camera") }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            Task {
                defer { item = nil }
                guard let data = try? await picked.loadTransferable(type: Data.self), let jpeg = PhotoEncoding.jpeg(from: data) else {
                    error = "Couldn't read that photo."
                    return
                }
                path = try? PhotoStore.stageLocal(jpeg)
            }
        }
    }
}
