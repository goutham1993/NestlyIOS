import NestlyCore
import SwiftUI

/// Week strip + 7×24 timeline + selected-day list (spec §14).
struct HistoryTab: View {
    @Environment(AppModel.self) private var app
    @Environment(FamilyStore.self) private var family
    @Environment(Preferences.self) private var prefs
    @State private var selected = LocalDate.today()
    @State private var entries: [ActivityEntity]?
    @State private var showFilters = false
    @State private var weekDirection: Edge = .trailing
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var zone: TimeZone { .current }

    private var weekStart: LocalDate {
        let firstWeekday = Calendar.current.firstWeekday
        let offset = (selected.calendarWeekday - firstWeekday + 7) % 7
        return selected.minusDays(offset)
    }

    private var isCurrentWeek: Bool { LocalDate.today(zone) < weekStart.plusDays(7) }

    var body: some View {
        let start = weekStart
        let filtered = ActivityFilters.filter(entries ?? [], prefs.filters)
        Clock(interval: 60) { now in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    weekStrip(start)
                    Card(padding: Space.m) {
                        TimelineGrid(weekStart: start, entries: filtered, selected: selected, now: now) { day in
                            withAnimation(.snappy) { selected = day }
                        } onEntry: { app.openEntry(.edit(activityId: $0.id)) }
                            .frame(height: 420)
                            .id(start)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .move(edge: weekDirection).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                    .clipped()
                    dayList(filtered, now)
                }
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.l)
            }
            .background(Color(.systemGroupedBackground))
            .gesture(DragGesture(minimumDistance: 40).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0 { nextWeek() } else { previousWeek() }
            })
            .sensoryFeedback(.selection, trigger: selected)
        }
        .navigationTitle(Format.dateText(selected, "EEE, MMM d"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showFilters = true } label: {
                    Image(systemName: prefs.filters.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel(prefs.filters.isEmpty ? "Filters" : "Filters, \(prefs.filters.count) on")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { app.push(.reminders) } label: { Label("Set Reminders", systemImage: "bell") }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("More")
            }
        }
        .sheet(isPresented: $showFilters) { FiltersSheet() }
        .live([.activity], id: "\(family.selectedProfile?.id ?? "")-\(start)", into: $entries) { [profile = family.selectedProfile] in
            guard let profile else { return [] }
            return try await Repositories.shared.activities.range(
                familyId: profile.familyId, profileId: profile.id,
                from: start.startOfDayMs(.current), to: start.plusDays(7).startOfDayMs(.current)
            )
        }
    }

    private func nextWeek() {
        guard !isCurrentWeek else { return }
        weekDirection = .trailing
        withAnimation(.snappy) { selected = min(selected.plusDays(7), LocalDate.today(zone)) }
    }

    private func previousWeek() {
        weekDirection = .leading
        withAnimation(.snappy) { selected = selected.minusDays(7) }
    }

    private func weekStrip(_ start: LocalDate) -> some View {
        let days = (0 ..< 7).map { start.plusDays($0) }
        let months = Array(NSOrderedSet(array: days.map { Format.dateText($0, "MMMM") })) as? [String] ?? []
        let today = LocalDate.today(zone)
        return VStack(spacing: Space.m) {
            HStack {
                Button { previousWeek() } label: { chevron("chevron.left") }
                    .accessibilityLabel("Previous week")
                Spacer()
                Text(months.joined(separator: " / ")).font(.rounded(.headline)).contentTransition(.opacity)
                Spacer()
                Button { nextWeek() } label: { chevron("chevron.right") }
                    .disabled(isCurrentWeek)
                    .accessibilityLabel("Next week")
            }
            HStack(spacing: Space.xs) {
                ForEach(days, id: \.self) { day in
                    let isSelected = day == selected
                    let future = today < day
                    Button { withAnimation(.snappy) { selected = day } } label: {
                        VStack(spacing: 4) {
                            Text(Format.dateText(day, "EEEEE")).font(.caption2.weight(.medium))
                                .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                            Text("\(day.day)").font(.rounded(.body, weight: .bold)).monospacedDigit()
                            Circle().fill(day == today ? (isSelected ? Color.white : Palette.accent) : .clear)
                                .frame(width: 4, height: 4)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .foregroundStyle(isSelected ? .white : future ? Color(.tertiaryLabel) : .primary)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                                    .fill(Palette.accent)
                                    .matchedGeometryEffect(id: "day", in: selection)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .disabled(future)
                    .accessibilityLabel(Format.dateText(day, "EEEE, MMMM d"))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .padding(Space.m)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.subheadline.weight(.semibold))
            .frame(width: 36, height: 36)
            .background(Color(.tertiarySystemFill), in: Circle())
    }

    @ViewBuilder private func dayList(_ all: [ActivityEntity], _ now: EpochMs) -> some View {
        let from = selected.startOfDayMs(zone), to = selected.plusDays(1).startOfDayMs(zone)
        let rows = all.filter { $0.startTime >= from && $0.startTime < to }.sorted { $0.startTime > $1.startTime }
        let bars = Bars.fractions(rows)
        let summaryLines = prefs.filters.isEmpty || rows.isEmpty
            ? []
            : Summary.summarize(rows, from: from, to: to, prefs: prefs.units)
        HStack(alignment: .firstTextBaseline) {
            SectionTitle(Format.dateText(selected, "EEEE, MMM d"))
            Spacer()
            Text(rows.isEmpty ? "" : rows.count == 1 ? "1 entry" : "\(rows.count) entries")
                .font(.subheadline).foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(.top, Space.s)
        if !summaryLines.isEmpty {
            DayFilterSummary(lines: summaryLines)
        }
        Card(padding: Space.m) {
            if entries == nil {
                ProgressView().frame(maxWidth: .infinity).padding(Space.l)
            } else if rows.isEmpty {
                HStack(spacing: Space.m) {
                    IconTile(icon: .crib, tint: .secondary, size: 34)
                    Text(prefs.filters.isEmpty ? "Nothing logged this day." : "Nothing matches your filters this day.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().padding(.leading, 46) }
                        Button { app.openEntry(.edit(activityId: entry.id)) } label: {
                            ActivityRow(entry: entry, barFraction: bars[entry.id], now: now)
                                .padding(.vertical, Space.s)
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
        }
        .animation(.snappy, value: selected)
    }
}

/// Per-type counts + totals for the filtered selected day (spec §14).
private struct DayFilterSummary: View {
    let lines: [SummaryLine]

    var body: some View {
        Card(padding: Space.m) {
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.type) { index, line in
                    if index > 0 { Divider().padding(.vertical, Space.s) }
                    HStack(alignment: .top, spacing: Space.m) {
                        IconTile(icon: line.type.icon, tint: line.type.color, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.type.displayName).font(.subheadline.weight(.semibold))
                            if !line.details.isEmpty {
                                Text(line.details.joined(separator: " · "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Text("\(line.count)")
                            .font(.rounded(.title3, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(line.type.color)
                            .contentTransition(.numericText())
                            .accessibilityLabel(line.count == 1 ? "1 entry" : "\(line.count) entries")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// 7 day columns × 24 hour rows; each entry is a bar at its start time spanning its duration.
struct TimelineGrid: View {
    let weekStart: LocalDate
    let entries: [ActivityEntity]
    let selected: LocalDate
    let now: EpochMs
    let onDay: (LocalDate) -> Void
    let onEntry: (ActivityEntity) -> Void

    private let labelWidth: CGFloat = 34

    var body: some View {
        GeometryReader { geo in
            let zone = TimeZone.current
            let colWidth = (geo.size.width - labelWidth) / 7
            let height = geo.size.height
            let perMs = height / 86_400_000
            ZStack(alignment: .topLeading) {
                // Night bands before 06:00 and after 18:00.
                let nightWidth = geo.size.width - labelWidth
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.sleep.opacity(0.07))
                    .frame(width: nightWidth, height: height / 4).offset(x: labelWidth)
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.sleep.opacity(0.07))
                    .frame(width: nightWidth, height: height / 4).offset(x: labelWidth, y: height * 0.75)
                ForEach(0 ..< 9) { i in
                    let y = height * CGFloat(i) / 8
                    Path { p in
                        p.move(to: CGPoint(x: labelWidth, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.secondary.opacity(i % 2 == 0 ? 0.22 : 0.1), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                }
                ForEach(Array(["12a", "6a", "12p", "6p"].enumerated()), id: \.offset) { i, label in
                    Text(label).font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
                        .frame(width: labelWidth - 4, alignment: .leading)
                        .offset(y: height * CGFloat(i) / 4 + 2)
                }
                .accessibilityHidden(true)
                ForEach(0 ..< 7) { i in
                    let day = weekStart.plusDays(i)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(day == selected ? Palette.accent.opacity(0.10) : Color.clear)
                        .contentShape(Rectangle())
                        .frame(width: colWidth, height: height)
                        .offset(x: labelWidth + colWidth * CGFloat(i))
                        .onTapGesture { onDay(day) }
                }
                ForEach(entries) { entry in
                    let day = LocalDate.of(ms: entry.startTime, zone: zone)
                    let col = LocalDate.daysBetween(weekStart, day)
                    if col >= 0, col < 7 {
                        let dayStart = day.startOfDayMs(zone)
                        let y = CGFloat(entry.startTime - dayStart) * perMs
                        let durationMs = (entry.durationSec ?? 0) * 1000
                        let h = max(5, min(height - y, CGFloat(durationMs) * perMs))
                        Capsule(style: .continuous)
                            .fill(entry.type.color.opacity(day == selected ? 1 : 0.8))
                            .frame(width: colWidth - 10, height: h)
                            .offset(x: labelWidth + colWidth * CGFloat(col) + 5, y: min(y, height - h))
                            .onTapGesture { onEntry(entry) }
                            .accessibilityLabel("\(entry.type.displayName), \(Format.dayAndTime(entry.startTime, now: now))")
                            .accessibilityAddTraits(.isButton)
                    }
                }
                let today = LocalDate.of(ms: now, zone: zone)
                let todayCol = LocalDate.daysBetween(weekStart, today)
                if todayCol >= 0, todayCol < 7 {
                    let y = CGFloat(now - today.startOfDayMs(zone)) * perMs
                    let x = labelWidth + colWidth * CGFloat(todayCol)
                    Capsule().fill(Palette.accent).frame(width: colWidth - 4, height: 2)
                        .offset(x: x + 2, y: y - 1)
                    Circle().fill(Palette.accent).frame(width: 7, height: 7)
                        .offset(x: x - 1, y: y - 3.5)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}
