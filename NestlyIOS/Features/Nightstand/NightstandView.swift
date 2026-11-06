import NestlyCore
import SwiftUI

/// Full-screen bedside view (spec §21.6).
struct NightstandView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: FeedSnapshotResult?
    @State private var result: String?
    @State private var resultTask: Task<Void, Never>?
    @State private var busy = false
    @State private var offset = CGSize.zero
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Dimmed so the screen stays easy on dark-adapted eyes.
    private static let accent = Palette.accent.opacity(0.85)
    private static let amber = Palette.warning.opacity(0.9)
    private static let red = Palette.critical.opacity(0.9)

    var body: some View {
        Clock(interval: 30) { now in
            content(now)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .foregroundStyle(Color(white: 0.85))
                .onChange(of: now / 60_000) { _, _ in
                    offset = CGSize(width: .random(in: -4 ... 4), height: .random(in: -4 ... 4))
                }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .task(id: authKey) {
            while !Task.isCancelled {
                snapshot = await FeedSnapshotLoader.load(repos: app.repos)
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    private var authKey: String {
        if case let .signedIn(id) = app.auth.status { return id }
        return "none"
    }

    @ViewBuilder
    private func content(_ now: EpochMs) -> some View {
        VStack(spacing: Space.xl) {
            Spacer(minLength: 0)
            switch snapshot {
            case nil:
                ProgressView().tint(.white)
            case .notSignedIn, .noChild:
                Text("Open Nestly to set up your family").font(.rounded(.title3, weight: .medium))
            case .unavailable:
                Text("Couldn't reach Nestly. Retrying…").font(.rounded(.title3, weight: .medium))
            case let .ready(s):
                ready(s, now)
            }
            if let result {
                Text(result)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.m)
                    .background(Color(white: 0.1), in: Capsule())
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            HStack(spacing: Space.m) {
                Button { Task { await logFeed() } } label: {
                    Label(busy ? "Saving…" : "Log Feed", systemImage: "plus")
                        .font(.rounded(.title3, weight: .semibold))
                        .foregroundStyle(Self.accent)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Palette.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                }
                .buttonStyle(.pressable)
                .disabled(busy)
                Button { close() } label: {
                    Text("Close")
                        .font(.rounded(.title3, weight: .medium))
                        .frame(width: 120, height: 64)
                        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, Space.xl)
        }
        .padding(.vertical, Space.xl)
        .animation(.snappy, value: result)
    }

    @ViewBuilder
    private func ready(_ s: FeedSnapshot, _ now: EpochMs) -> some View {
        VStack(spacing: Space.xs) {
            Text(s.childName).font(.rounded(.title2, weight: .semibold))
            Text(Format.headerDate(now)).font(.subheadline).foregroundStyle(Color(white: 0.5))
        }
        VStack(spacing: Space.s) {
            Text("Next feed").font(.subheadline.weight(.medium)).foregroundStyle(Color(white: 0.5))
            switch s.state(now: now) {
            case .noFeed:
                Text("No feeds logged yet").font(.rounded(.title3, weight: .medium))
            case let .upcoming(due, remaining):
                hero(due)
                Text("in \(Format.durationShort(remaining, roundUp: true))").font(.rounded(.title3, weight: .semibold)).foregroundStyle(Self.amber)
            case let .dueNow(due):
                hero(due)
                Text("Due now").font(.rounded(.title3, weight: .semibold)).foregroundStyle(Self.amber)
            case let .overdue(due, overdue):
                hero(due)
                Text("Overdue by \(Format.durationShort(overdue, roundUp: false))").font(.rounded(.title3, weight: .semibold)).foregroundStyle(Self.red)
            }
        }
        VStack(spacing: Space.s) {
            if let last = s.lastFeed {
                let detail = last.detailText(app.prefs.units).map { " · \($0)" } ?? ""
                Text("Last feed \(Format.time(last.startTime)) · \(last.label)\(detail)")
            }
            Text(todayLine(s))
        }
        .font(.callout)
        .foregroundStyle(Color(white: 0.55))
        .multilineTextAlignment(.center)
        vitaminD(s)
    }

    private func hero(_ due: EpochMs) -> some View {
        Text(Format.time(due))
            .font(.system(size: 76, weight: .light, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }

    private func todayLine(_ s: FeedSnapshot) -> String {
        var parts = ["Today: \(s.todayFeedCount) feed\(s.todayFeedCount == 1 ? "" : "s")"]
        if s.todayBottleMl > 0 { parts.append(Format.volume(s.todayBottleMl, app.prefs.units)) }
        if let avg = s.todayAvgIntervalMs { parts.append("every ~\(Format.durationShort(avg, roundUp: false))") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func vitaminD(_ s: FeedSnapshot) -> some View {
        if let given = s.vitaminDGivenAt {
            Label("Vitamin D given at \(Format.time(given))", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color(white: 0.5))
        } else {
            Button { Task { await logVitaminD() } } label: {
                HStack(spacing: Space.s) {
                    NestlyIcon.vitaminD.image.resizable().scaledToFit().frame(width: 18, height: 18)
                    Text("Vitamin D due")
                        .font(.subheadline.weight(.semibold))
                    Text("· Tap when given").font(.subheadline)
                        .foregroundStyle(Color(white: 0.5))
                }
                .foregroundStyle(Self.amber)
                .padding(.horizontal, Space.l)
                .frame(minHeight: 44)
                .background(Palette.warning.opacity(0.12), in: Capsule())
                .opacity(pulse ? 0.55 : 1)
            }
            .buttonStyle(.pressable)
            .disabled(busy)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
    }

    private func logFeed() async {
        busy = true
        defer { busy = false }
        let r = await QuickBottleLog.run(repos: app.repos)
        Haptics.success()
        show(r.nightstandMessage(app.prefs.units))
        snapshot = await FeedSnapshotLoader.load(repos: app.repos)
    }

    private func logVitaminD() async {
        busy = true
        defer { busy = false }
        let r = await QuickVitaminDLog.run(repos: app.repos)
        Haptics.success()
        show(r.message())
        snapshot = await FeedSnapshotLoader.load(repos: app.repos)
    }

    private func show(_ text: String) {
        result = text
        resultTask?.cancel()
        resultTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled { result = nil }
        }
    }

    private func close() {
        app.showNightstand = false
        dismiss()
    }
}