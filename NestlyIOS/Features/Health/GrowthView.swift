import Charts
import NestlyCore
import SwiftUI

/// WHO percentile chart / list per metric (spec §16.1).
struct GrowthView: View {
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    @Environment(Preferences.self) private var prefs
    @State private var metric: GrowthMetric
    @State private var showList = false
    @State private var entries: [ActivityEntity]?
    @State private var selectedPoint: GrowthPoint?

    init(initialMetric: GrowthMetric) { _metric = State(initialValue: initialMetric) }

    struct GrowthPoint: Identifiable, Equatable {
        let entry: ActivityEntity
        let date: LocalDate
        let value: Double
        let ageMonths: Double?
        let percentile: Double?
        var id: String { entry.id }
    }

    var body: some View {
        let profile = family.selectedProfile
        let points = points(profile)
        List {
            Picker("Metric", selection: $metric) {
                ForEach(GrowthMetric.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            if entries == nil {
                HStack(spacing: Space.m) { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
            } else if points.isEmpty {
                EmptyStateView(
                    icon: metric.icon,
                    tint: tint,
                    title: "No \(metric.label.lowercased()) yet",
                    message: "Log a measurement to see how \(profile?.name ?? "your child") is growing."
                ) {
                    Button { app.openEntry(.new(kind: .GROWTH)) } label: { Label("Log Growth", systemImage: "plus") }
                        .buttonStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            } else if showList {
                ForEach(points.reversed()) { point in
                    Button { app.openEntry(.edit(activityId: point.entry.id)) } label: { listRow(point, profile) }
                        .foregroundStyle(Color.primary)
                }
            } else if let profile, let birth = profile.adjustedBirthDate ?? profile.birthDate {
                chart(points, profile: profile, birth: birth)
                    .frame(height: 360)
                    .padding(.vertical, Space.s)
                if let point = selectedPoint { pointCard(point, profile, birth) }
            } else {
                Text("Add \(profile?.name ?? "your child")'s birth date to see the growth chart.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Growth")
        .animation(.snappy, value: selectedPoint)
        .animation(.snappy, value: showList)
        .sensoryFeedback(.selection, trigger: selectedPoint)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showList.toggle() } label: {
                    Image(systemName: showList ? "chart.xyaxis.line" : "list.bullet")
                }
                .accessibilityLabel(showList ? "Show chart" : "Show list")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { app.openEntry(.new(kind: .GROWTH)) } label: { Image(systemName: "plus") }.accessibilityLabel("Log growth")
            }
        }
        .onChange(of: metric) { _, _ in selectedPoint = nil }
        .live([.activity], id: profile?.id ?? "", into: $entries) { [profile] in
            guard let profile else { return [] }
            return try await Repositories.shared.activities.ofTypes(familyId: profile.familyId, profileId: profile.id, [.GROWTH])
                .filter { $0.profileId == profile.id }
        }
    }

    private func points(_ profile: ProfileEntity?) -> [GrowthPoint] {
        let birth = profile?.adjustedBirthDate ?? profile?.birthDate
        return (entries ?? []).compactMap { entry -> GrowthPoint? in
            guard let value = metric.valueOf(entry.growth) else { return nil }
            let date = LocalDate.of(ms: entry.startTime)
            let age = birth.map { GrowthPercentiles.ageMonths($0, date) }
            let pct = age.flatMap { $0 >= 0 ? GrowthPercentiles.percentile(metric, profile?.sex, $0, value) : nil }
            return GrowthPoint(entry: entry, date: date, value: value, ageMonths: age, percentile: pct)
        }
        .sorted { $0.date < $1.date }
    }

    private func display(_ value: Double) -> Double {
        switch metric {
        case .WEIGHT: Units.kgToDisplay(value, prefs.units.weight)
        case .HEIGHT, .HEAD: Units.cmToDisplay(value, prefs.units.length)
        }
    }

    private func formatted(_ value: Double) -> String {
        switch metric {
        case .WEIGHT: Format.weight(value, prefs.units)
        case .HEIGHT, .HEAD: Format.length(value, prefs.units)
        }
    }

    private func sexLabel(_ sex: Sex?) -> String? {
        switch sex {
        case .MALE: "Boys"
        case .FEMALE: "Girls"
        default: nil
        }
    }

    private var tint: Color { CardKind.GROWTH.color }

    private func percentileText(_ pct: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return "\(formatter.string(from: NSNumber(value: Int(pct.rounded()))) ?? "\(Int(pct.rounded()))") percentile"
    }

    private func listRow(_ point: GrowthPoint, _ profile: ProfileEntity?) -> some View {
        let birth = profile?.adjustedBirthDate ?? profile?.birthDate
        return HStack(spacing: Space.m) {
            IconTile(icon: metric.icon, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.date(point.date))
                let details = [
                    birth.map { "Age \(GrowthPercentiles.ageLabel($0, point.date))" },
                    point.percentile.flatMap { pct in sexLabel(profile?.sex).map { _ in percentileText(pct) } },
                ].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(formatted(point.value)).font(.rounded(.headline)).monospacedDigit()
        }
    }

    private func chart(_ points: [GrowthPoint], profile: ProfileEntity, birth: LocalDate) -> some View {
        let maxAge = points.compactMap(\.ageMonths).max() ?? 0
        let xMax = Double(min(60, max(6, Int(ceil(maxAge + 1)))))
        let curves: [Double] = [2, 5, 10, 25, 50, 75, 90, 95, 98]
        let hasCurves = profile.sex == .MALE || profile.sex == .FEMALE
        return Chart {
            if hasCurves {
                ForEach(curves, id: \.self) { pct in
                    ForEach(Array(stride(from: 0.0, through: xMax, by: 0.5)), id: \.self) { month in
                        if let v = GrowthPercentiles.valueAtPercentile(metric, profile.sex, month, pct) {
                            LineMark(x: .value("Age", month), y: .value("Value", display(v)), series: .value("Percentile", "\(Int(pct))%"))
                                .foregroundStyle(pct == 50 ? tint.opacity(0.45) : Color(.tertiaryLabel).opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: pct == 50 ? 1.5 : 0.7, dash: pct == 50 ? [] : [2, 3]))
                        }
                    }
                }
            }
            let plotted = points.filter { ($0.ageMonths ?? -1) >= 0 }
            ForEach(plotted) { point in
                LineMark(x: .value("Age", point.ageMonths ?? 0), y: .value("Value", display(point.value)), series: .value("Percentile", "Child"))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Age", point.ageMonths ?? 0), y: .value("Value", display(point.value)))
                    .foregroundStyle(tint)
                    .symbolSize(selectedPoint == point ? 160 : 50)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel()
            }
        }
        .chartXScale(domain: 0 ... xMax)
        .chartXAxisLabel("Age (months)")
        .chartYAxisLabel(metric == .WEIGHT ? Units.weightLabel(prefs.units.weight) : Units.lengthLabel(prefs.units.length))
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame else { return }
                        let origin = geo[plot].origin
                        guard let age: Double = proxy.value(atX: location.x - origin.x) else { return }
                        selectedPoint = points.min { abs(($0.ageMonths ?? 999) - age) < abs(($1.ageMonths ?? 999) - age) }
                    }
            }
        }
    }

    private func pointCard(_ point: GrowthPoint, _ profile: ProfileEntity, _ birth: LocalDate) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                IconTile(icon: metric.icon, tint: tint, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatted(point.value)).font(.rounded(.title2, weight: .bold)).monospacedDigit()
                    Text("\(metric.label) at \(GrowthPercentiles.ageLabel(birth, point.date))").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { selectedPoint = nil } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
            }
            if let pct = point.percentile, let label = sexLabel(profile.sex) {
                StatusPill(text: "\(percentileText(pct)) · \(label)", tint: tint)
            }
            HStack {
                Button { app.openEntry(.edit(activityId: point.entry.id)) } label: { Label("Edit", systemImage: "pencil") }
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Source: WHO").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Space.xs)
    }
}
