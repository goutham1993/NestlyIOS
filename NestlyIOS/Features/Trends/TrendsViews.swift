import Charts
import NestlyCore
import SwiftUI

/// Current vs previous window for one metric.
struct TrendRow: Sendable {
    let current: MetricResult
    let previous: MetricResult

    var delta: Double? {
        guard current.sampleCount > 0, previous.sampleCount > 0 else { return nil }
        return current.value - previous.value
    }

    func comparison(_ window: TrendsWindow) -> String? {
        guard let delta else { return nil }
        return current.metric.isMeaningful(delta) ? current.metric.comparison(delta, window) : "Same as \(TrendsWindow.periodText(window.days))"
    }

    /// `periodsBack` = 0 → window ending today.
    static func compute(_ metric: TrendMetric, _ entries: [ActivityEntity], window: TrendsWindow, periodsBack: Int = 0, today: LocalDate = .today()) -> TrendRow {
        let days = window.days
        let currentFrom = today.minusDays(days - 1 + periodsBack * days)
        return TrendRow(
            current: TrendsAggregator.compute(metric, entries, from: currentFrom, days: days),
            previous: TrendsAggregator.compute(metric, entries, from: currentFrom.minusDays(days), days: days)
        )
    }

    static func range(_ window: TrendsWindow, periodsBack: Int, today: LocalDate = .today()) -> (from: EpochMs, to: EpochMs) {
        let days = window.days
        let currentFrom = today.minusDays(days - 1 + periodsBack * days)
        return (currentFrom.minusDays(days).startOfDayMs(), currentFrom.plusDays(days).startOfDayMs())
    }
}

struct TrendsTab: View {
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    @Environment(Preferences.self) private var prefs
    @State private var window: TrendsWindow = .SEVEN_DAYS
    @State private var entries: [ActivityEntity]?

    private static let sections: [CardKind] = [.FEED, .PUMP, .DIAPER, .SLEEP]

    var body: some View {
        List {
            Picker("Window", selection: $window.animation(.snappy)) {
                ForEach(TrendsWindow.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            if let entries {
                ForEach(Self.sections, id: \.self) { section in
                    Section {
                        ForEach(TrendMetric.allCases.filter { $0.section == section }) { metric in
                            let row = TrendRow.compute(metric, entries, window: window)
                            Button { app.push(.trend(metric, window)) } label: { TrendRowView(row: row, window: window) }
                                .foregroundStyle(Color.primary)
                        }
                    } header: {
                        HStack(spacing: Space.s) {
                            IconTile(icon: section.icon, tint: section.color, size: 26)
                            Text(section.title).font(.rounded(.headline)).foregroundStyle(Color.primary)
                        }
                        .textCase(nil)
                        .padding(.bottom, 2)
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .sensoryFeedback(.selection, trigger: window)
        .navigationTitle("Trends")
        .live([.activity], id: "\(family.selectedProfile?.id ?? "")-\(window)", into: $entries) { [profile = family.selectedProfile, window] in
            guard let profile else { return [] }
            let r = TrendRow.range(window, periodsBack: 0)
            return try await Repositories.shared.activities.range(familyId: profile.familyId, profileId: profile.id, from: r.from, to: min(r.to, nowMs() + 1))
        }
    }
}

struct TrendRowView: View {
    let row: TrendRow
    let window: TrendsWindow
    @Environment(Preferences.self) private var prefs

    var body: some View {
        let metric = row.current.metric
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Text(row.current.sampleCount > 0 ? metric.summary(row.current.value, prefs.units) : "—")
                    .font(.rounded(.title3, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let text = row.comparison(window) {
                    Text(text).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let delta = row.delta, metric.isMeaningful(delta) {
                StatusPill(text: delta > 0 ? "Up" : "Down", systemImage: delta > 0 ? "arrow.up.right" : "arrow.down.right")
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

struct TrendDetailView: View {
    let metric: TrendMetric
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    @Environment(Preferences.self) private var prefs
    @State private var window: TrendsWindow
    @State private var periodsBack = 0
    @State private var tab = 1
    @State private var entries: [ActivityEntity]?

    init(metric: TrendMetric, initialWindow: TrendsWindow) {
        self.metric = metric
        _window = State(initialValue: initialWindow)
    }

    var body: some View {
        let row = entries.map { TrendRow.compute(metric, $0, window: window, periodsBack: periodsBack) }
        List {
            HStack {
                Button { withAnimation(.snappy) { periodsBack += 1 } } label: { periodChevron("chevron.left") }
                    .accessibilityLabel("Previous period")
                Spacer()
                Text(rangeText(row)).font(.rounded(.headline)).contentTransition(.opacity)
                Spacer()
                Button { withAnimation(.snappy) { periodsBack -= 1 } } label: { periodChevron("chevron.right") }
                    .disabled(periodsBack == 0)
                    .accessibilityLabel("Next period")
            }
            .buttonStyle(.borderless)
            .sensoryFeedback(.selection, trigger: periodsBack)
            if let row {
                summary(row)
                Picker("View", selection: $tab) {
                    Text("Calendar").tag(0)
                    Text("Graph").tag(1)
                    Text("Entries").tag(2)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                switch tab {
                case 0: MarksGrid(result: row.current) { id in app.openEntry(.edit(activityId: id)) }.frame(height: 360)
                case 1: TrendChart(result: row.current, prefs: prefs.units).frame(height: 260)
                default: entriesList(row.current)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Window", selection: $window) {
                        ForEach(TrendsWindow.allCases) { Text($0.label).tag($0) }
                    }
                } label: { Text(window.label) }
            }
            if let row {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: "\(family.selectedProfile?.name ?? "") · \(metric.title) (\(rangeText(row))): \(metric.summary(row.current.value, prefs.units))") {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
            }
        }
        .onChange(of: window) { _, _ in periodsBack = 0 }
        .live([.activity], id: "\(family.selectedProfile?.id ?? "")-\(window)-\(periodsBack)", into: $entries) { [profile = family.selectedProfile, window, periodsBack] in
            guard let profile else { return [] }
            let r = TrendRow.range(window, periodsBack: periodsBack)
            return try await Repositories.shared.activities.range(familyId: profile.familyId, profileId: profile.id, from: r.from, to: min(r.to, nowMs() + 1))
        }
    }

    private func periodChevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.subheadline.weight(.semibold))
            .frame(width: 36, height: 36)
            .background(Color(.tertiarySystemFill), in: Circle())
    }

    private func rangeText(_ row: TrendRow?) -> String {
        guard let days = row?.current.days, let first = days.first?.date, let last = days.last?.date else { return "" }
        return first == last ? Format.dateText(first, "MMM d") : "\(Format.dateText(first, "MMM d")) – \(Format.dateText(last, "MMM d"))"
    }

    private func summary(_ row: TrendRow) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                IconTile(icon: metric.section.icon, tint: metric.section.color, size: 40)
                Text(row.current.sampleCount > 0 ? metric.summary(row.current.value, prefs.units) : "Nothing logged in this period.")
                    .font(row.current.sampleCount > 0 ? .rounded(.title2, weight: .bold) : .headline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.bottom, Space.xs)
            if metric.showBreakdown || row.current.breakdown.count > 1 {
                ForEach(row.current.breakdown, id: \.series) { segment in
                    HStack {
                        RoundedRectangle(cornerRadius: 3).fill(TrendChart.color(segment.series, row.current)).frame(width: 10, height: 10)
                        Text(segment.series.label)
                        Spacer()
                        Text(metric.unit == .COUNT ? "\(Format.number(segment.value, maxDecimals: 1)) \(metric.noun)" : metric.formatValue(segment.value, prefs.units))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
            if let text = row.comparison(window) {
                Text(text).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func entriesList(_ result: MetricResult) -> some View {
        if result.entries.isEmpty {
            Text("No entries in this period.").foregroundStyle(.secondary)
        }
        ForEach(result.entries.sorted { $0.startTime > $1.startTime }) { entry in
            ActivityRow(entry: entry, showDay: true)
                .onTapGesture { app.openEntry(.edit(activityId: entry.id)) }
        }
    }
}

struct TrendChart: View {
    let result: MetricResult
    let prefs: UnitPrefs

    /// The first series shown takes the section's own color; the rest follow the palette.
    static func color(_ series: TrendSeries, _ result: MetricResult) -> Color {
        let palette: [Color] = [result.metric.section.color, Palette.diaper, Palette.firsts, Palette.health, Palette.sleep, Palette.growth, Palette.pump]
        let index = result.breakdown.firstIndex { $0.series == series } ?? series.rawValue
        return palette[index % palette.count]
    }

    private func display(_ value: Double) -> Double {
        switch result.metric.unit {
        case .COUNT: value
        case .VOLUME: Units.mlToDisplay(value, prefs.volume)
        case .DURATION: value / 3600
        }
    }

    private var floor: Double {
        switch result.metric.unit {
        case .COUNT: 5
        case .VOLUME: prefs.volume == .OZ ? 4 : 100
        case .DURATION: 1
        }
    }

    var body: some View {
        let maxDay = result.days.map { display($0.total) }.max() ?? 0
        let avg = display(result.value)
        Chart {
            ForEach(result.days, id: \.date) { day in
                ForEach(day.segments, id: \.series) { segment in
                    BarMark(x: .value("Day", day.date.date(), unit: .day), y: .value("Value", display(segment.value)), width: .ratio(0.6))
                        .foregroundStyle(by: .value("Series", segment.series.label))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            if result.sampleCount > 0 {
                RuleMark(y: .value("Average", avg))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .foregroundStyle(Color(.secondaryLabel))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Average").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: result.days.count > 14 ? 7 : 1)) { _ in
                AxisValueLabel(format: result.days.count > 7 ? .dateTime.day() : .dateTime.weekday(.narrow), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel()
            }
        }
        .chartLegend(result.breakdown.count > 1 ? .visible : .hidden)
        .chartYScale(domain: 0 ... max(floor, maxDay * 1.1, avg * 1.1))
        .chartForegroundStyleScale(domain: result.breakdown.map(\.series.label), range: result.breakdown.map { Self.color($0.series, result) })
        .chartYAxisLabel(axisLabel)
    }

    private var axisLabel: String {
        switch result.metric.unit {
        case .COUNT: result.metric.noun
        case .VOLUME: Units.volumeLabel(prefs.volume)
        case .DURATION: "hours"
        }
    }
}

/// One column per day of the window, marks at their time of day; tap → edit.
struct MarksGrid: View {
    let result: MetricResult
    let onTap: (String) -> Void

    var body: some View {
        GeometryReader { geo in
            let zone = TimeZone.current
            let labelWidth: CGFloat = 34
            let columns = max(1, result.days.count)
            let colWidth = (geo.size.width - labelWidth) / CGFloat(columns)
            let height = geo.size.height - 18
            let perMs = height / 86_400_000
            ZStack(alignment: .topLeading) {
                ForEach(Array(["12a", "6a", "12p", "6p"].enumerated()), id: \.offset) { i, label in
                    Text(label).font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
                        .frame(width: labelWidth - 4, alignment: .leading).offset(y: 20 + height * CGFloat(i) / 4)
                }
                ForEach(Array(result.days.enumerated()), id: \.offset) { i, day in
                    Text(columns > 7 ? "\(day.date.day)" : Format.dateText(day.date, "EEE d")).font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: colWidth).offset(x: labelWidth + colWidth * CGFloat(i))
                }
                ForEach(Array(result.marks.enumerated()), id: \.offset) { _, mark in
                    let day = LocalDate.of(ms: mark.startMs, zone: zone)
                    if let col = result.days.firstIndex(where: { $0.date == day }) {
                        let y = CGFloat(mark.startMs - day.startOfDayMs(zone)) * perMs
                        let h = max(4, min(height - y, CGFloat(mark.endMs - mark.startMs) * perMs))
                        Capsule(style: .continuous)
                            .fill(TrendChart.color(mark.series, result))
                            .frame(width: max(4, colWidth - 8), height: h)
                            .offset(x: labelWidth + colWidth * CGFloat(col) + 4, y: 18 + y)
                            .onTapGesture { onTap(mark.entryId) }
                    }
                }
            }
        }
    }
}
