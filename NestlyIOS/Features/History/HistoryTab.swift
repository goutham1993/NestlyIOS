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
                VStack(alignment: .leading, spacing: 12) {
                    weekStrip(start)
                    TimelineGrid(weekStart: start, entries: filtered, selected: selected, now: now) { day in
                        selected = day
                    } onEntry: { app.openEntry(.edit(activityId: $0.id)) }
                        .frame(height: 420)
                    dayList(filtered, now)
                }
                .padding(.horizontal, 16)
            }
            .gesture(DragGesture(minimumDistance: 40).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0 { nextWeek() } else { selected = selected.minusDays(7) }
            })
        }
        .navigationTitle(Format.dateText(selected, "EEE, MMM d"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showFilters = true } label: {
                    Label(prefs.filters.isEmpty ? "Filters" : "Filters (\(prefs.filters.count))", systemImage: "line.3.horizontal.decrease.circle")
                        .labelStyle(.titleAndIcon)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Set Reminders") { app.push(.reminders) }
                } label: { Image(systemName: "ellipsis.circle") }
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
        let next = selected.plusDays(7)
        selected = min(next, LocalDate.today(zone))
    }

    private func weekStrip(_ start: LocalDate) -> some View {
        let days = (0 ..< 7).map { start.plusDays($0) }
        let months = Array(NSOrderedSet(array: days.map { Format.dateText($0, "MMMM") })) as? [String] ?? []
        return VStack(spacing: 8) {
            HStack {
                Button { selected = selected.minusDays(7) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous week")
                Spacer()
                Text(months.joined(separator: " / ")).font(.headline)
                Spacer()
                Button { nextWeek() } label: { Image(systemName: "chevron.right") }
                    .disabled(isCurrentWeek)
                    .accessibilityLabel("Next week")
            }
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let isSelected = day == selected
                    let future = LocalDate.today(zone) < day
                    Button { selected = day } label: {
                        VStack(spacing: 2) {
                            Text(Format.dateText(day, "EEEEE")).font(.caption2)
                            Text("\(day.day)").font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isSelected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(isSelected ? .white : future ? .secondary : .primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(future)
                }
            }
        }
    }

    @ViewBuilder private func dayList(_ all: [ActivityEntity], _ now: EpochMs) -> some View {
        let from = selected.startOfDayMs(zone), to = selected.plusDays(1).startOfDayMs(zone)
        let rows = all.filter { $0.startTime >= from && $0.startTime < to }.sorted { $0.startTime > $1.startTime }
        let bars = Bars.fractions(rows)
        HStack {
            Text(Format.dateText(selected, "EEEE, MMM d")).font(.headline)
            Spacer()
            Text(rows.isEmpty ? "" : rows.count == 1 ? "1 entry" : "\(rows.count) entries").foregroundStyle(.secondary)
        }
        if entries == nil {
            ProgressView().frame(maxWidth: .infinity)
        } else if rows.isEmpty {
            Text("Nothing logged.").foregroundStyle(.secondary)
        }
        ForEach(rows) { entry in
            ActivityRow(entry: entry, barFraction: bars[entry.id])
                .padding(.vertical, 6)
                .onTapGesture { app.openEntry(.edit(activityId: entry.id)) }
            Divider()
        }
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
                Rectangle().fill(Color.indigo.opacity(0.08)).frame(height: height / 4).offset(x: labelWidth)
                Rectangle().fill(Color.indigo.opacity(0.08)).frame(height: height / 4).offset(x: labelWidth, y: height * 0.75)
                ForEach(0 ..< 9) { i in
                    let y = height * CGFloat(i) / 8
                    Path { p in
                        p.move(to: CGPoint(x: labelWidth, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                }
                ForEach(Array(["12\nAM", "6\nAM", "12\nPM", "6\nPM"].enumerated()), id: \.offset) { i, label in
                    Text(label).font(.system(size: 9)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .frame(width: labelWidth)
                        .offset(y: height * CGFloat(i) / 4)
                }
                ForEach(0 ..< 7) { i in
                    let day = weekStart.plusDays(i)
                    Rectangle()
                        .fill(day == selected ? Color.accentColor.opacity(0.08) : Color.clear)
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
                        let h = max(4, min(height - y, CGFloat(durationMs) * perMs))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(entry.type.color)
                            .frame(width: colWidth - 6, height: h)
                            .offset(x: labelWidth + colWidth * CGFloat(col) + 3, y: y)
                            .onTapGesture { onEntry(entry) }
                    }
                }
                let today = LocalDate.of(ms: now, zone: zone)
                let todayCol = LocalDate.daysBetween(weekStart, today)
                if todayCol >= 0, todayCol < 7 {
                    let y = CGFloat(now - today.startOfDayMs(zone)) * perMs
                    Rectangle().fill(Color.red).frame(width: colWidth, height: 2)
                        .offset(x: labelWidth + colWidth * CGFloat(todayCol), y: y)
                }
            }
        }
    }
}
