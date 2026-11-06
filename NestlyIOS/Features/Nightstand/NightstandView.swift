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

    private static let amber = Color(red: 1, green: 0.72, blue: 0.3)
    private static let red = Color(red: 1, green: 0.38, blue: 0.38)

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
        VStack(spacing: 22) {
            switch snapshot {
            case nil:
                ProgressView().tint(.white)
            case .notSignedIn:
                Text("Open Nestly to set up your family").font(.title3)
            case .noChild:
                Text("Open Nestly to set up your family").font(.title3)
            case .unavailable:
                Text("Couldn't reach Nestly. Retrying…").font(.title3)
            case let .ready(s):
                ready(s, now)
            }
            if let result {
                Text(result).font(.callout).multilineTextAlignment(.center).padding(.horizontal)
            }
            HStack(spacing: 16) {
                Button { Task { await logFeed() } } label: {
                    Text(busy ? "SAVING…" : "LOG FEED").font(.title3.weight(.bold)).frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(white: 0.22))
                .disabled(busy)
                Button { close() } label: {
                    Text("CLOSE").font(.title3.weight(.semibold)).frame(maxWidth: 140, minHeight: 64)
                }
                .buttonStyle(.bordered)
                .tint(Color(white: 0.5))
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private func ready(_ s: FeedSnapshot, _ now: EpochMs) -> some View {
        VStack(spacing: 4) {
            Text(s.childName).font(.title2.weight(.semibold))
            Text(Format.headerDate(now)).font(.subheadline).foregroundStyle(.secondary)
        }
        VStack(spacing: 6) {
            Text("NEXT FEED").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary)
            switch s.state(now: now) {
            case .noFeed:
                Text("No feeds logged yet — tap LOG FEED").font(.title3)
            case let .upcoming(due, remaining):
                Text(Format.time(due)).font(.system(size: 64, weight: .light, design: .rounded))
                Text("IN \(Format.durationShort(remaining, roundUp: true))").font(.title3.weight(.semibold)).foregroundStyle(Self.amber)
            case let .dueNow(due):
                Text(Format.time(due)).font(.system(size: 64, weight: .light, design: .rounded))
                Text("NOW").font(.title3.weight(.bold)).foregroundStyle(Self.amber)
            case let .overdue(due, overdue):
                Text(Format.time(due)).font(.system(size: 64, weight: .light, design: .rounded))
                Text("OVERDUE BY \(Format.durationShort(overdue, roundUp: false))").font(.title3.weight(.bold)).foregroundStyle(Self.red)
            }
        }
        if let last = s.lastFeed {
            let detail = last.detailText(app.prefs.units).map { " · \($0)" } ?? ""
            Text("Last feed \(Format.time(last.startTime)) · \(last.label)\(detail)").font(.callout).foregroundStyle(.secondary)
        }
        Text(todayLine(s)).font(.callout).foregroundStyle(.secondary)
        vitaminD(s)
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
            Text("VITAMIN D GIVEN at \(Format.time(given))").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
        } else {
            Button { Task { await logVitaminD() } } label: {
                VStack(spacing: 2) {
                    Text("VITAMIN D DUE").font(.footnote.weight(.bold))
                    Text("tap when given").font(.caption2)
                }
                .foregroundStyle(Self.red)
                .opacity(pulse ? 0.45 : 1)
            }
            .disabled(busy)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
    }

    private func logFeed() async {
        busy = true
        defer { busy = false }
        let r = await QuickBottleLog.run(repos: app.repos)
        show(r.nightstandMessage(app.prefs.units))
        snapshot = await FeedSnapshotLoader.load(repos: app.repos)
    }

    private func logVitaminD() async {
        busy = true
        defer { busy = false }
        let r = await QuickVitaminDLog.run(repos: app.repos)
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