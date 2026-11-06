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

// MARK: - Quick Log (spec §21.2)

struct QuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NestlyQuickLog", provider: FeedProvider(followDueTime: false)) { entry in
            QuickLogView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Nestly Quick Log")
        .description("Log a bottle in one tap, or jump to a diaper, sleep or pump entry.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickLogView: View {
    let entry: FeedEntry
    @Environment(\.widgetFamily) private var family

    private static let links: [(title: String, icon: NestlyIcon, tint: Color, kind: String)] = [
        ("Diaper", .diaper, Palette.diaper, "DIAPER"),
        ("Sleep", .sleep, Palette.sleep, "SLEEP"),
        ("Pump", .pump, Palette.pump, "PUMP"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Spacer(minLength: 0)
            if let status = entry.status {
                Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(2).minimumScaleFactor(0.8)
            }
            if family == .systemMedium {
                HStack(spacing: 8) {
                    bottleButton(compact: false)
                    ForEach(Self.links, id: \.kind) { link($0.title, $0.icon, $0.tint, $0.kind, compact: false) }
                }
            } else {
                bottleButton(compact: true)
                HStack(spacing: 6) {
                    ForEach(Self.links, id: \.kind) { link($0.title, $0.icon, $0.tint, $0.kind, compact: true) }
                }
            }
        }
    }

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            if case let .ready(s) = entry.result {
                Text(s.childName).font(.rounded(.headline)).lineLimit(1)
                if let last = s.lastFeed {
                    Text("Last feed \(Format.ago(last.startTime, now: entry.date.epochMs))").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Nestly").font(.rounded(.headline))
                Text(unavailableText(entry.result) ?? "").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func bottleButton(compact: Bool) -> some View {
        Button(intent: LogBottleIntent()) {
            Group {
                if compact {
                    HStack(spacing: 6) {
                        NestlyIcon.bottle.image.resizable().scaledToFit().frame(width: 16, height: 16)
                        Text("Log Bottle").font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                } else {
                    tileLabel("Bottle", .bottle)
                }
            }
            .foregroundStyle(.white)
            .background(Palette.feed, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log bottle")
    }

    private func link(_ title: String, _ icon: NestlyIcon, _ tint: Color, _ kind: String, compact: Bool) -> some View {
        Link(destination: URL(string: "nestly://entry/\(kind)")!) {
            Group {
                if compact {
                    icon.image.resizable().scaledToFit().frame(width: 16, height: 16)
                        .frame(maxWidth: .infinity, minHeight: 30)
                } else {
                    tileLabel(title, icon)
                }
            }
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel(title)
    }

    private func tileLabel(_ title: String, _ icon: NestlyIcon) -> some View {
        VStack(spacing: 6) {
            icon.image.resizable().scaledToFit().frame(width: 22, height: 22)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.85))
        }
        .frame(maxWidth: .infinity, minHeight: 64)
    }
}

// MARK: - Next Feed / StandBy (spec §21.3)

struct NextFeedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NestlyNextFeed", provider: FeedProvider(followDueTime: true)) { entry in
            NextFeedView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Next feed").font(.caption.weight(.semibold))
                Text(unavailableText(entry.result) ?? "").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func rectangular(_ s: FeedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                NestlyIcon.bottle.image.resizable().scaledToFit().frame(width: 11, height: 11)
                Text("\(s.childName) · Next feed").lineLimit(1)
            }
            .font(.caption2.weight(.semibold))
            .widgetAccentable()
            stateLine(s, font: .rounded(.headline), tinted: false)
            if let last = s.lastFeed {
                Text("Last \(Format.time(last.startTime))").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func small(_ s: FeedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                IconTile(icon: .bottle, tint: Palette.feed, size: 22)
                Text(s.childName).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .padding(.bottom, 4)
            Text("Next feed").font(.caption2).foregroundStyle(.secondary)
            if let due = s.nextDueMs {
                Text(Format.time(due))
                    .font(.rounded(.title, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            stateLine(s, font: .caption.weight(.semibold), tinted: true)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Button(intent: LogBottleIntent()) {
                    Text("Log Feed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(Palette.feed, in: Capsule())
                }
                .buttonStyle(.plain)
                if s.vitaminDGivenAt == nil {
                    Button(intent: LogVitaminDIntent()) {
                        NestlyIcon.vitaminD.image.resizable().scaledToFit()
                            .frame(width: 15, height: 15)
                            .foregroundStyle(Palette.warning)
                            .frame(width: 30, height: 30)
                            .background(Palette.warning.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Vitamin D due. Log as given")
                }
            }
        }
    }

    @ViewBuilder
    private func stateLine(_ s: FeedSnapshot, font: Font, tinted: Bool) -> some View {
        switch s.state(now: entry.date.epochMs) {
        case .noFeed:
            Text("No feeds yet").font(font)
        case let .upcoming(due, _):
            HStack(spacing: 3) {
                Text("in")
                Text(Date(epochMs: due), style: .relative)
            }
            .font(font).foregroundStyle(tinted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        case .dueNow:
            Text("Due now").font(font).foregroundStyle(tinted ? AnyShapeStyle(Palette.warning) : AnyShapeStyle(.primary))
        case let .overdue(due, _):
            HStack(spacing: 3) {
                Text("Overdue by")
                Text(Date(epochMs: due), style: .relative)
            }
            .font(font).foregroundStyle(tinted ? AnyShapeStyle(Palette.critical) : AnyShapeStyle(.primary))
        }
    }
}

// MARK: - Live Activity (spec §21.5)

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            LockScreenTimerView(attributes: context.attributes, state: context.state)
                .padding(16)
                .widgetURL(entryURL(context.attributes))
        } dynamicIsland: { context in
            let group = context.attributes.group
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        IconTile(icon: group.icon, tint: group.color, size: 36, filled: true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(context.attributes.title(context.state)).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(context.attributes.childName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: context.state)
                        .font(.rounded(.title2, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(group.color)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if context.state.isPaused {
                            Text("Paused").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        TimerButtons(group: group, state: context.state)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                group.icon.image.resizable().scaledToFit().frame(width: 16, height: 16).foregroundStyle(group.color)
            } compactTrailing: {
                ElapsedText(state: context.state).monospacedDigit().foregroundStyle(group.color).frame(maxWidth: 56)
            } minimal: {
                group.icon.image.resizable().scaledToFit().frame(width: 16, height: 16).foregroundStyle(group.color)
            }
            .keylineTint(group.color)
            .widgetURL(entryURL(context.attributes))
        }
    }

    private func entryURL(_ attributes: TimerActivityAttributes) -> URL? {
        URL(string: "nestly://entry/\(attributes.group.entryKind.rawValue)")
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
            if group == .BREASTFEED {
                Button(intent: SwitchSideIntent()) {
                    circle("arrow.left.arrow.right", fill: Color.gray.opacity(0.25), foreground: .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Switch side")
            }
            Button(intent: PauseResumeTimerIntent(group: group)) {
                circle(state.isPaused ? "play.fill" : "pause.fill", fill: group.color, foreground: .white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.isPaused ? "Resume" : "Pause")
        }
    }

    private func circle(_ symbol: String, fill: Color, foreground: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: 40, height: 40)
            .background(fill, in: Circle())
    }
}

/// Mirrors the in-app timer banner: filled tile, title and child, elapsed time, controls.
struct LockScreenTimerView: View {
    let attributes: TimerActivityAttributes
    let state: TimerGroupState

    var body: some View {
        let group = attributes.group
        HStack(alignment: .center, spacing: 12) {
            IconTile(icon: group.icon, tint: group.color, size: 44, filled: true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(attributes.title(state)).font(.subheadline.weight(.semibold))
                    if state.isPaused {
                        Text("Paused").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
                ElapsedText(state: state)
                    .font(.rounded(.title2, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(group.color)
                Text(attributes.childName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            TimerButtons(group: group, state: state)
        }
    }
}
