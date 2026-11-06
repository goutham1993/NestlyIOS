import NestlyCore
import PhotosUI
import SwiftUI
import UIKit

// MARK: - Live data

extension View {
    /// Streams `fetch` into `value` now and on every tick of `tables`, restarting when `id` changes.
    func live<T: Sendable, ID: Equatable>(
        _ tables: [NestlyCore.Table],
        id: ID,
        into value: Binding<T?>,
        fetch: @escaping @Sendable () async throws -> T
    ) -> some View {
        task(id: id) {
            for await next in refetch(tables, fetch: fetch) { value.wrappedValue = next }
        }
    }
}

/// Current time that ticks every `interval` seconds.
struct Clock<Content: View>: View {
    var interval: TimeInterval = 30
    @ViewBuilder let content: (EpochMs) -> Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { context in
            content(context.date.epochMs)
        }
    }
}

// MARK: - Rows

/// One activity row: time, label, bar, detail and note/photo indicators (spec §11.7).
struct ActivityRow: View {
    let entry: ActivityEntity
    var barFraction: Double?
    var showDay: Bool = false
    var now: EpochMs = nowMs()
    @Environment(Preferences.self) private var prefs

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.type.symbol)
                .foregroundStyle(entry.type.color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(showDay ? Format.dayAndTime(entry.startTime, now: now) : Format.time(entry.startTime))
                    .font(.caption).foregroundStyle(.secondary)
                Text(entry.label.isEmpty ? entry.type.displayName : entry.label)
                    .font(.subheadline.weight(.medium))
            }
            .frame(minWidth: 90, alignment: .leading)
            if let barFraction {
                GeometryReader { geo in
                    Capsule().fill(entry.type.color.opacity(0.75))
                        .frame(width: max(geo.size.width * 0.08, geo.size.width * barFraction), height: 8)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 20)
            } else {
                Spacer(minLength: 0)
            }
            if let detail = entry.detailText(prefs.units), !detail.isEmpty {
                Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            if entry.hasNote { Image(systemName: "note.text").font(.caption).foregroundStyle(.secondary) }
            if entry.hasPhoto { Image(systemName: "photo").font(.caption).foregroundStyle(.secondary) }
        }
        .contentShape(Rectangle())
    }
}

enum Bars {
    /// value / max of that type that day (spec §11.7).
    static func fractions(_ entries: [ActivityEntity]) -> [String: Double] {
        var maxByKey: [String: Double] = [:]
        func key(_ e: ActivityEntity) -> String { "\(e.type.rawValue)-\(LocalDate.of(ms: e.startTime))" }
        for e in entries { if let v = e.barValue { maxByKey[key(e)] = max(maxByKey[key(e)] ?? 0, v) } }
        var out: [String: Double] = [:]
        for e in entries {
            if let v = e.barValue, let m = maxByKey[key(e)], m > 0 { out[e.id] = v / m }
        }
        return out
    }
}

struct SectionCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Inputs

/// Optional decimal field. Shows `placeholder` when nil.
struct DecimalField: View {
    let title: String
    @Binding var value: Double?
    var unit: String?
    var decimals = 2

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("Add", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .frame(maxWidth: 120)
            if let unit { Text(unit).foregroundStyle(.secondary) }
        }
        .onAppear { text = value.map { Format.number($0, maxDecimals: decimals) } ?? "" }
        .onChange(of: value) { _, v in
            if !focused { text = v.map { Format.number($0, maxDecimals: decimals) } ?? "" }
        }
        .onChange(of: text) { _, t in
            let parsed = Double(t.replacingOccurrences(of: ",", with: "."))
            if t.isBlank { if value != nil { value = nil } } else if let parsed, parsed != value { value = parsed }
        }
    }
}

/// Value stored in a base unit, displayed and entered in the display unit.
struct UnitField: View {
    let title: String
    @Binding var base: Double?
    let toDisplay: (Double) -> Double
    let fromDisplay: (Double) -> Double
    let unit: String
    var decimals = 2
    var onUserEdit: (() -> Void)?

    var body: some View {
        DecimalField(
            title: title,
            value: Binding(
                get: { base.map(toDisplay).map { ($0 * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals)) } },
                set: { newValue in
                    let converted = newValue.map(fromDisplay)
                    if let converted, let base, abs(toDisplay(base) - toDisplay(converted)) < pow(10, -Double(decimals)) / 2 { return }
                    base = converted
                    onUserEdit?()
                }
            ),
            unit: unit,
            decimals: decimals
        )
    }
}

/// Hours / minutes / seconds wheel editor.
struct DurationEditor: View {
    let title: String
    let initialSeconds: Int64
    var showSeconds = true
    let onDone: (Int64) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var h = 0
    @State private var m = 0
    @State private var s = 0

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                wheel($h, 0 ..< 24, "h")
                wheel($m, 0 ..< 60, "m")
                if showSeconds { wheel($s, 0 ..< 60, "s") }
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(Int64(h * 3600 + m * 60 + (showSeconds ? s : 0)))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(300)])
        .onAppear {
            h = Int(initialSeconds / 3600)
            m = Int(initialSeconds % 3600 / 60)
            s = Int(initialSeconds % 60)
        }
    }

    private func wheel(_ value: Binding<Int>, _ range: Range<Int>, _ suffix: String) -> some View {
        Picker(suffix, selection: value) {
            ForEach(range, id: \.self) { Text("\($0)\(suffix)").tag($0) }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
    }
}

/// Wrapping chips for single/multi choice.
struct ChipFlow<Item: Hashable>: View {
    let items: [Item]
    let label: (Item) -> String
    let isSelected: (Item) -> Bool
    var swatch: ((Item) -> Color)?
    let toggle: (Item) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { toggle(item) } label: {
                    HStack(spacing: 6) {
                        if let swatch {
                            Circle().fill(swatch(item)).frame(width: 12, height: 12)
                                .overlay(Circle().stroke(.secondary.opacity(0.4)))
                        }
                        Text(label(item)).font(.subheadline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(isSelected(item) ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill), in: Capsule())
                    .overlay(Capsule().stroke(isSelected(item) ? Color.accentColor : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Photos

/// Shows an activity photo from a storage path or a staged local file.
struct RemotePhoto: View {
    let uri: String
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                Image(systemName: "photo").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task(id: uri) {
            do {
                let data = try await PhotoStore(backend: .shared).data(uri)
                image = UIImage(data: data)
            } catch {
                failed = true
            }
        }
    }
}

enum PhotoEncoding {
    /// Re-encodes as JPEG (≈0.85, long edge ≤ 2048 px) — spec §3.6.
    static func jpeg(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxEdge: CGFloat = 2048
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

// MARK: - Add / edit child

struct ChildForm: View {
    let title: String
    var initial: ProfileEntity?
    var askCaregiverName: Bool
    let onSave: (_ name: String, _ sex: Sex?, _ birthDate: LocalDate?, _ caregiverName: String) async throws -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var sex: Sex? = nil
    @State private var hasBirthDate = true
    @State private var birthDate = Date()
    @State private var caregiverName = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("First Name", text: $name).textContentType(.givenName)
                Picker("Sex", selection: $sex) {
                    Text("Boy").tag(Sex?.some(.MALE))
                    Text("Girl").tag(Sex?.some(.FEMALE))
                    if sex == .OTHER { Text("Other").tag(Sex?.some(.OTHER)) }
                }
                .pickerStyle(.segmented)
                Toggle("Birthdate", isOn: $hasBirthDate)
                if hasBirthDate {
                    DatePicker("Birthdate", selection: $birthDate, in: ...Date().addingTimeInterval(270 * 86400), displayedComponents: .date)
                }
                if askCaregiverName {
                    TextField("Your Name", text: $caregiverName).textContentType(.name)
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(initial == nil ? "Add" : "Save") { save() }
                        .disabled(name.isBlank || saving)
                }
            }
            .onAppear {
                guard let initial else { return }
                name = initial.name
                sex = initial.sex
                hasBirthDate = initial.birthDate != nil
                if let b = initial.birthDate { birthDate = b.date() }
            }
        }
    }

    private func save() {
        saving = true
        error = nil
        let birth = hasBirthDate ? LocalDate.of(ms: birthDate.epochMs) : nil
        Task {
            do {
                try await onSave(name, sex, birth, caregiverName)
                dismiss()
            } catch {
                self.error = (error as? ConflictError)?.errorDescription ?? "Couldn't save. Check your connection and try again."
            }
            saving = false
        }
    }
}

extension Binding where Value == EpochMs {
    var date: Binding<Date> {
        Binding<Date>(get: { Date(epochMs: wrappedValue) }, set: { wrappedValue = $0.epochMs })
    }
}
