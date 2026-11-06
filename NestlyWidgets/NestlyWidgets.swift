import ActivityKit
import AppIntents
import NestlyCore
import SwiftUI
import WidgetKit

@main
struct NestlyWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickLogWidget()
        NextFeedWidget()
        TimerLiveActivity()
    }
}

// MARK: - Timeline

struct FeedEntry: TimelineEntry {
    let date: Date
    let result: FeedSnapshotResult
    let status: String?
}

struct FeedProvider: TimelineProvider {
    /// Next Feed adds entries at the due time and one minute after, so the state flips on time.
    let followDueTime: Bool

    func placeholder(in context: Context) -> FeedEntry {
        FeedEntry(date: Date(), result: .ready(.placeholder()), status: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (FeedEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task {
            let result = await FeedSnapshotLoader.load(sessionWait: 10)
            completion(FeedEntry(date: Date(), result: result, status: WidgetStatus.current()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FeedEntry>) -> Void) {
        Task {
            let now = Date()
            let result = await FeedSnapshotLoader.load(sessionWait: 10)
            let status = WidgetStatus.current(at: now)
            var dates = [now]
            let next = now.addingTimeInterval(15 * 60)
            if followDueTime, case let .ready(s) = result, let due = s.nextDueMs.map({ Date(epochMs: $0) }) {
                for d in [due, due.addingTimeInterval(60)] where d > now && d < next { dates.append(d) }
            }
            var entries = dates.sorted().map { FeedEntry(date: $0, result: result, status: status) }
            if status != nil {
                let expiry = now.addingTimeInterval(WidgetStatus.visibleFor)
                if expiry < next { entries.append(FeedEntry(date: expiry, result: result, status: nil)) }
            }
            completion(Timeline(entries: entries, policy: .after(next)))
        }
    }
}

private func unavailableText(_ result: FeedSnapshotResult) -> String? {
    switch result {
    case .notSignedIn: "Open Nestly and sign in"
    case .noChild: "Open Nestly to add a child"
    case .unavailable: "Couldn't reach Nestly"
    case .ready: nil
    }
}

private let feedColor = Color(red: 0.95, green: 0.55, blue: 0.35)

// MARK: - Quick Log (spec §21.2)

struct QuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NestlyQuickLog", provider: FeedProvider(followDueTime: false)) { entry in
            QuickLogView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Nestly Quick Log")
        .description("Log a bottle in one tap, or jump to a diaper, sleep or pump entry.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickLogView: View {
    let entry: FeedEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            if let status = entry.status {
                Text(status).font(.caption2).lineLimit(2).minimumScaleFactor(0.8)
            }
            if family == .systemMedium {
                HStack(spacing: 6) {
                    bottleButton
                    link("Diaper", "humidity.fill", "DIAPER")
                    link("Sleep", "moon.zzz.fill", "SLEEP")
                    link("Pump", "drop.triangle.fill", "PUMP")
                }
            } else {
                bottleButton
                HStack(spacing: 6) {
                    link(nil, "humidity.fill", "DIAPER")
                    link(nil, "moon.zzz.fill", "SLEEP")
                    link(nil, "drop.triangle.fill", "PUMP")
                }
            }
        }
    }

    @ViewBuilder private var header: some View {
        if case let .ready(s) = entry.result {
            Text(s.childName).font(.headline).lineLimit(1)
            if let last = s.lastFeed {
                Text("Last feed \(Format.ago(last.startTime, now: entry.date.epochMs))").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("Nestly").font(.headline)
            Text(unavailableText(entry.result) ?? "").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var bottleButton: some View {
        Button(intent: LogBottleIntent()) {
            Label("Bottle", systemImage: "waterbottle.fill").font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
        }
        .tint(feedColor)
    }

    private func link(_ title: String?, _ symbol: String, _ kind: String) -> some View {
        Link(destination: URL(string: "nestly://entry/\(kind)")!) {
            Group {
                if let title { Label(title, systemImage: symbol) } else { Image(systemName: symbol) }
            }
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(kind.capitalized)
    }
}

// MARK: - Next Feed / StandBy (spec §21.3)

struct NextFeedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NestlyNextFeed", provider: FeedProvider(followDueTime: true)) { entry in
            NextFeedView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "nestly://nightstand"))
        }
        .configurationDisplayName("Next feed")
        .description("When the next feed is due, with one-tap logging. Great in StandBy.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct NextFeedView: View {
    let entry: FeedEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if case let .ready(s) = entry.result {
            if family == .accessoryRectangular { rectangular(s) } else { small(s) }
        } else {
            VStack(alignment: .leading) {
                Text("NEXT FEED").font(.caption2.weight(.bold))
                Text(unavailableText(entry.result) ?? "").font(.caption)
            }
        }
    }

    private func rectangular(_ s: FeedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(s.childName) · NEXT FEED").font(.caption2.weight(.bold)).lineLimit(1)
            stateLine(s, font: .headline)
            if let last = s.lastFeed {
                Text("Last \(Format.time(last.startTime))").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func small(_ s: FeedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(s.childName).font(.caption.weight(.semibold)).lineLimit(1)
            Text("NEXT FEED").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            if let due = s.nextDueMs {
                Text(Format.time(due)).font(.title2.weight(.semibold)).minimumScaleFactor(0.7)
            }
            stateLine(s, font: .caption.weight(.semibold))
            if let last = s.lastFeed {
                Text("Last \(Format.time(last.startTime))\(last.detailText().map { " · \($0)" } ?? "")")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Button(intent: LogBottleIntent()) {
                    Text("Log feed").font(.caption2.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .tint(feedColor)
                if s.vitaminDGivenAt == nil {
                    Button(intent: LogVitaminDIntent()) {
                        Image(systemName: "sun.max.fill").font(.caption2)
                    }
                    .tint(.red)
                    .accessibilityLabel("Vitamin D given")
                }
            }
            Text(s.vitaminDGivenAt.map { "Vitamin D given at \(Format.time($0))" } ?? "Vitamin D due")
                .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    @ViewBuilder
    private func stateLine(_ s: FeedSnapshot, font: Font) -> some View {
        switch s.state(now: entry.date.epochMs) {
        case .noFeed:
            Text("No feeds yet").font(font)
        case let .upcoming(due, _):
            HStack(spacing: 3) {
                Text("in")
                Text(Date(epochMs: due), style: .relative)
            }
            .font(font).foregroundStyle(.orange)
        case .dueNow:
            Text("NOW").font(font).foregroundStyle(.orange)
        case let .overdue(due, _):
            HStack(spacing: 3) {
                Text("OVERDUE BY")
                Text(Date(epochMs: due), style: .relative)
            }
            .font(font).foregroundStyle(.red)
        }
    }
}

// MARK: - Live Activity (spec §21.5)

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            LockScreenTimerView(attributes: context.attributes, state: context.state)
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.6))
                .widgetURL(entryURL(context.attributes))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.childName, systemImage: symbol(context.attributes.group)).font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: context.state).font(.title3.monospacedDigit()).frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.title(context.state)).font(.subheadline)
                        Spacer()
                        TimerButtons(group: context.attributes.group, state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: symbol(context.attributes.group))
            } compactTrailing: {
                ElapsedText(state: context.state).monospacedDigit().frame(maxWidth: 56)
            } minimal: {
                Image(systemName: symbol(context.attributes.group))
            }
            .widgetURL(entryURL(context.attributes))
        }
    }

    private func entryURL(_ attributes: TimerActivityAttributes) -> URL? {
        URL(string: "nestly://entry/\(attributes.group.entryKind.rawValue)")
    }
}

private func symbol(_ group: TimerGroup) -> String {
    switch group {
    case .BREASTFEED: "figure.and.child.holdinghands"
    case .PUMP: "drop.triangle.fill"
    case .SLEEP: "moon.zzz.fill"
    }
}

struct ElapsedText: View {
    let state: TimerGroupState

    var body: some View {
        if let start = state.timerStart {
            Text(timerInterval: start ... Date.distantFuture, countsDown: false)
        } else {
            Text(Format.stopwatch(state.accumulatedSeconds))
        }
    }
}

struct TimerButtons: View {
    let group: TimerGroup
    let state: TimerGroupState

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: PauseResumeTimerIntent(group: group)) {
                Label(state.isPaused ? "Resume" : "Pause", systemImage: state.isPaused ? "play.fill" : "pause.fill")
                    .font(.caption.weight(.semibold))
            }
            .tint(.orange)
            if group == .BREASTFEED {
                Button(intent: SwitchSideIntent()) {
                    Label("Switch side", systemImage: "arrow.left.arrow.right").font(.caption.weight(.semibold))
                }
                .tint(.gray)
            }
        }
    }
}

struct LockScreenTimerView: View {
    let attributes: TimerActivityAttributes
    let state: TimerGroupState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol(attributes.group)).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(attributes.childName).font(.caption).foregroundStyle(.secondary)
                Text(attributes.title(state)).font(.headline)
                ElapsedText(state: state).font(.title2.monospacedDigit())
                if state.isPaused { Text("Paused").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            TimerButtons(group: attributes.group, state: state)
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
        }
        .foregroundStyle(.white)
    }
}
