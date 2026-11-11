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
        HStack(spacing: Space.m) {
            IconTile(icon: entry.type.icon, tint: entry.type.color, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label.isEmpty ? entry.type.displayName : entry.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(showDay ? Format.dayAndTime(entry.startTime, now: now) : Format.time(entry.startTime))
                    if entry.hasNote { Image(systemName: "note.text").accessibilityLabel("Has note") }
                    if entry.hasPhoto { Image(systemName: "photo").accessibilityLabel("Has photo") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .frame(minWidth: 96, alignment: .leading)
            if let barFraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(entry.type.color.opacity(0.12))
                        Capsule().fill(entry.type.color.opacity(0.8))
                            .frame(width: max(geo.size.width * 0.08, geo.size.width * barFraction))
                    }
                    .frame(height: 6)
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 20)
                .accessibilityHidden(true)
            } else {
                Spacer(minLength: 0)
            }
            if let detail = entry.detailText(prefs.units), !detail.isEmpty {
                Text(detail).font(.subheadline.weight(.medium)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
        }
        .padding(.vertical, 2)
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
            ForEach(range, id: \.self) { Text("\($0) \(suffix)").font(.rounded(.title3, weight: .medium)).monospacedDigit().tag($0) }
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
    var tint: Color = Palette.accent
    let toggle: (Item) -> Void
    @State private var tapCount = 0

    var body: some View {
        FlowLayout(spacing: Space.s) {
            ForEach(items, id: \.self) { item in
                let selected = isSelected(item)
                Button {
                    tapCount += 1
                    withAnimation(.snappy) { toggle(item) }
                } label: {
                    HStack(spacing: 6) {
                        if let swatch {
                            Circle().fill(swatch(item)).frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                        }
                        Text(label(item)).font(.subheadline.weight(selected ? .semibold : .regular))
                    }
                    .foregroundStyle(selected ? tint : .primary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(selected ? tint.opacity(0.16) : Color(.tertiarySystemFill), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: tapCount)
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
    /// Upright image for the crop screen. Long edge is capped so a camera original stays easy to pan.
    static func image(from data: Data, maxEdge: CGFloat = 3072) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        return scaled(upright(image), maxEdge: maxEdge)
    }

    /// Re-encodes as JPEG (≈0.85, long edge ≤ 2048 px) — spec §3.6.
    static func jpeg(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return jpeg(from: image)
    }

    static func jpeg(from image: UIImage) -> Data? {
        scaled(upright(image), maxEdge: 2048).jpegData(compressionQuality: 0.85)
    }

    /// Visible square after the crop preview's cover-scale, pinch, and pan. `viewSize` is the square's side in points.
    static func cropSquare(image: UIImage, viewSize: CGFloat, scale: CGFloat, offset: CGSize) -> UIImage {
        guard viewSize > 0, let cg = image.cgImage else { return image }
        let srcW = image.size.width
        let srcH = image.size.height
        guard srcW > 1, srcH > 1 else { return image }
        let userScale = min(5, max(1, scale))
        let cover = max(viewSize / srcW, viewSize / srcH)
        let drawW = srcW * cover * userScale
        let drawH = srcH * cover * userScale
        let left = viewSize / 2 + offset.width - drawW / 2
        let top = viewSize / 2 + offset.height - drawH / 2
        let srcX = min(max(0, (0 - left) / drawW * srcW), srcW - 1)
        let srcY = min(max(0, (0 - top) / drawH * srcH), srcH - 1)
        let side = max(1, min(viewSize / drawW * srcW, viewSize / drawH * srcH, srcW - srcX, srcH - srcY))
        let pixelX = srcX * CGFloat(cg.width) / srcW
        let pixelY = srcY * CGFloat(cg.height) / srcH
        let pixelSide = side * min(CGFloat(cg.width) / srcW, CGFloat(cg.height) / srcH)
        let bounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let rect = CGRect(x: pixelX, y: pixelY, width: pixelSide, height: pixelSide).integral.intersection(bounds)
        let square = min(rect.width, rect.height)
        let squared = CGRect(x: rect.minX, y: rect.minY, width: square, height: square).intersection(bounds)
        guard squared.width >= 1, squared.height >= 1, let cropped = cg.cropping(to: squared) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    /// How far the photo can slide before the square shows empty space.
    static func clampOffset(_ offset: CGSize, scale: CGFloat, viewSize: CGFloat, imageSize: CGSize) -> CGSize {
        guard viewSize > 0, imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let userScale = min(5, max(1, scale))
        let cover = max(viewSize / imageSize.width, viewSize / imageSize.height)
        let maxX = max(0, (imageSize.width * cover * userScale - viewSize) / 2)
        let maxY = max(0, (imageSize.height * cover * userScale - viewSize) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, offset.width)),
            height: min(maxY, max(-maxY, offset.height))
        )
    }

    private static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func scaled(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let edge = max(image.size.width, image.size.height)
        guard edge > maxEdge else { return image }
        let ratio = maxEdge / edge
        let target = CGSize(width: (image.size.width * ratio).rounded(), height: (image.size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// Square crop. Drag and pinch to frame the photo; the circle is how the avatar will look.
struct PhotoCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onUse: (UIImage) -> Void

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var viewSize: CGFloat = 0
    @State private var baseScale: CGFloat = 1
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", action: onCancel)
                    .foregroundStyle(.white)
                Spacer()
                Text("Crop")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button("Use Photo") {
                    onUse(PhotoEncoding.cropSquare(image: image, viewSize: viewSize, scale: scale, offset: offset))
                }
                .fontWeight(.semibold)
                .foregroundStyle(Palette.accent)
            }
            .font(.body.weight(.semibold))
            .padding(.horizontal, Space.s)
            .frame(minHeight: 52)

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ZStack {
                    cropImage(side: side)
                    CropDim()
                        .frame(width: side, height: side)
                        .allowsHitTesting(false)
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(drag)
                .simultaneousGesture(magnify)
                .onAppear { viewSize = side }
                .onChange(of: side) { _, new in viewSize = new }
            }

            Text("Drag and pinch to frame the photo.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func cropImage(side: CGFloat) -> some View {
        let cover = max(side / image.size.width, side / image.size.height)
        let drawW = image.size.width * cover * scale
        let drawH = image.size.height * cover * scale
        return Image(uiImage: image)
            .resizable()
            .frame(width: drawW, height: drawH)
            .offset(offset)
            .frame(width: side, height: side)
            .clipped()
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = PhotoEncoding.clampOffset(
                    CGSize(width: baseOffset.width + value.translation.width, height: baseOffset.height + value.translation.height),
                    scale: scale,
                    viewSize: viewSize,
                    imageSize: image.size
                )
            }
            .onEnded { _ in baseOffset = offset }
    }

    private var magnify: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let next = min(5, max(1, baseScale * value))
                scale = next
                offset = PhotoEncoding.clampOffset(offset, scale: next, viewSize: viewSize, imageSize: image.size)
            }
            .onEnded { _ in
                baseScale = scale
                offset = PhotoEncoding.clampOffset(offset, scale: scale, viewSize: viewSize, imageSize: image.size)
                baseOffset = offset
            }
    }
}

/// Dims everything outside the circle the avatar will use.
private struct CropDim: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.addRect(CGRect(origin: .zero, size: size))
            path.addEllipse(in: CGRect(origin: .zero, size: size))
            context.fill(path, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
            context.stroke(Path(ellipseIn: CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.9)), lineWidth: 2)
        }
    }
}

/// Full-screen child photo, like a WhatsApp profile picture, with a way through to the editor.
struct ProfilePhotoViewer: View {
    let name: String
    var photoPath: String?
    let onChange: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width - 64, geo.size.height * 0.72)
            ZStack {
                Color.black
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }
                VStack(spacing: 0) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Close")
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                        Color.clear.frame(width: 44, height: 44)
                    }
                    Spacer()
                    ChildAvatar(name: name, photoPath: photoPath, size: max(side, 1))
                    Spacer()
                    Button(photoPath == nil ? "Add photo" : "Change photo", action: onChange)
                        .font(.headline)
                        .foregroundStyle(Palette.accent)
                        .padding(.bottom, Space.xl)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// MARK: - Add / edit child

struct ChildForm: View {
    let title: String
    var initial: ProfileEntity?
    var askCaregiverName: Bool
    let onSave: (_ name: String, _ sex: Sex?, _ birthDate: LocalDate?, _ caregiverName: String, _ photoPath: String?) async throws -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var sex: Sex? = nil
    @State private var hasBirthDate = true
    @State private var birthDate = Date()
    @State private var caregiverName = ""
    @State private var photoPath: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var cropImage: UIImage?
    @State private var readingPhoto = false
    @State private var didLoad = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: Space.m) {
                        ChildAvatar(name: name, photoPath: photoPath, size: 72)
                        Text(name.isBlank ? "Your little one" : name)
                            .font(.rounded(.title3, weight: .bold))
                            .foregroundStyle(name.isBlank ? .secondary : .primary)
                            .contentTransition(.opacity)
                        photoActions
                        Text("Optional. Anyone in the family can change this later.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s)
                    .listRowBackground(Color.clear)
                }
                Section {
                    TextField("First Name", text: $name).textContentType(.givenName)
                    Picker("Sex", selection: $sex) {
                        Text("Boy").tag(Sex?.some(.MALE))
                        Text("Girl").tag(Sex?.some(.FEMALE))
                        if sex == .OTHER { Text("Other").tag(Sex?.some(.OTHER)) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle("Birthdate", isOn: $hasBirthDate.animation(.snappy))
                    if hasBirthDate {
                        DatePicker("Birthdate", selection: $birthDate, in: ...Date().addingTimeInterval(270 * 86400), displayedComponents: .date)
                    }
                }
                if askCaregiverName {
                    Section {
                        TextField("Your Name", text: $caregiverName).textContentType(.name)
                    } footer: {
                        Text("Shown to other caregivers next to the entries you log.")
                    }
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.critical).font(.footnote) }
                }
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
                guard !didLoad else { return }
                didLoad = true
                guard let initial else { return }
                name = initial.name
                sex = initial.sex
                hasBirthDate = initial.birthDate != nil
                if let b = initial.birthDate { birthDate = b.date() }
                photoPath = initial.photoPath
            }
            .onChange(of: photoItem) { _, picked in
                guard let picked else { return }
                readingPhoto = true
                Task {
                    defer {
                        photoItem = nil
                        readingPhoto = false
                    }
                    guard let data = try? await picked.loadTransferable(type: Data.self), let image = PhotoEncoding.image(from: data) else {
                        error = "Couldn't read that photo."
                        return
                    }
                    cropImage = image
                }
            }
            .fullScreenCover(isPresented: cropPresented) {
                if let cropImage {
                    PhotoCropView(image: cropImage, onCancel: { self.cropImage = nil }) { cropped in
                        applyCrop(cropped)
                    }
                }
            }
        }
    }

    private var cropPresented: Binding<Bool> {
        Binding(get: { cropImage != nil }, set: { if !$0 { cropImage = nil } })
    }

    private func applyCrop(_ image: UIImage) {
        guard let jpeg = PhotoEncoding.jpeg(from: image) else {
            error = "Couldn't read that photo."
            cropImage = nil
            return
        }
        do {
            photoPath = try PhotoStore.stageLocal(jpeg)
            error = nil
        } catch {
            self.error = "Couldn't read that photo."
        }
        cropImage = nil
    }

    @ViewBuilder private var photoActions: some View {
        if readingPhoto {
            ProgressView()
        } else if photoPath == nil {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Add Photo", systemImage: "camera")
            }
            .buttonStyle(.borderless)
            .disabled(saving)
        } else {
            HStack(spacing: Space.l) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Change Photo", systemImage: "camera")
                }
                .buttonStyle(.borderless)
                Button(role: .destructive) {
                    withAnimation(.snappy) { photoPath = nil }
                } label: {
                    Label("Remove Photo", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
            .disabled(saving)
        }
    }

    private func save() {
        saving = true
        error = nil
        let birth = hasBirthDate ? LocalDate.of(ms: birthDate.epochMs) : nil
        Task {
            do {
                try await onSave(name, sex, birth, caregiverName, photoPath)
                Haptics.success()
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
