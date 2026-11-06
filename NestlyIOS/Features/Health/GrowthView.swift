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
                Text("Loading…").foregroundStyle(.secondary)
            } else if points.isEmpty {
                Text("No \(metric.label.lowercased()) measurements yet.").foregroundStyle(.secondary)
                Button("Log growth") { app.openEntry(.new(kind: .GROWTH)) }
            } else if showList {
                ForEach(points.reversed()) { point in
                    Button { app.openEntry(.edit(activityId: point.entry.id)) } label: { listRow(point, profile) }
                        .foregroundStyle(.primary)
                }
            } else if let profile, let birth = profile.adjustedBirthDate ?? profile.birthDate {
                chart(points, profile: profile, birth: birth).frame(height: 360)
                if let point = selectedPoint { pointCard(point, profile, birth) }
            } else {
                Text("Add \(profile?.name ?? "your child")'s birth date to see the growth chart.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Growth")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(showList ? "Show chart" : "Show list") { showList.toggle() }
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

    private func listRow(_ point: GrowthPoint, _ profile: ProfileEntity?) -> some View {
        let birth = profile?.adjustedBirthDate ?? profile?.birthDate
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(Format.date(point.date))
                Spacer()
                Text(formatted(point.value)).font(.headline)
            }
            if let pct = point.percentile, let label = sexLabel(profile?.sex) {
                Text("\(label) Percentile \(Int(pct.rounded()))%").font(.caption).foregroundStyle(.secondary)
            }
            if let birth {
                Text("Age \(GrowthPercentiles.ageLabel(birth, point.date))").font(.caption).foregroundStyle(.secondary)
            }
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
                                .foregroundStyle(pct == 50 ? Color.green.opacity(0.8) : Color.secondary.opacity(0.35))
                                .lineStyle(StrokeStyle(lineWidth: pct == 50 ? 1.5 : 0.8))
                        }
                    }
                }
            }
            ForEach(points.filter { ($0.ageMonths ?? -1) >= 0 }) { point in
                PointMark(x: .value("Age", point.ageMonths ?? 0), y: .value("Value", display(point.value)))
                    .foregroundStyle(CardKind.GROWTH.color)
                    .symbolSize(selectedPoint == point ? 140 : 60)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("\(metric.label) \(formatted(point.value))").font(.headline)
            if let pct = point.percentile, let label = sexLabel(profile.sex) {
                Text("\(label) Percentile \(Int(pct.rounded()))%")
            }
            Text("Age \(GrowthPercentiles.ageLabel(birth, point.date))").foregroundStyle(.secondary)
            HStack {
                Button("Edit") { app.openEntry(.edit(activityId: point.entry.id)) }
                Spacer()
                Button("Dismiss") { selectedPoint = nil }
            }
            .buttonStyle(.borderless)
            Text("Source: WHO").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
