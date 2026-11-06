import NestlyCore
import Observation
import SwiftUI

/// State and actions for one open entry sheet (port of Android `EntryController`). New
/// Breastfeed/Combo, Pump and Sleep entries keep durations in the shared `ActiveTimerStore`, so
/// timers survive the sheet closing and drive the Live Activity.
@MainActor
@Observable
final class EntryController {
    let request: EntryRequest
    @ObservationIgnored let repos: Repositories

    private(set) var kind: EntryKind
    var draft: EntryDraft
    private(set) var existing: [ActivityEntity] = []
    private(set) var loaded: Bool
    private(set) var lastBottleMl: Double?
    private(set) var defaultBottleMl: Double?
    private(set) var lastSide: BreastSide?
    private(set) var saving = false
    var error: String?
    /// Set after saving a new bottle/combo with a manually typed amount → ask about the default.
    var defaultPrompt: Double?
    private(set) var timers: [TimerKey: TimerState] = [:]
    @ObservationIgnored var amountTypedManually = false

    var isEditing: Bool { if case .edit = request { true } else { false } }
    var usesTimers: Bool { !isEditing && kind.isTimed }

    var timerGroup: TimerGroup? {
        switch kind {
        case .BREASTFEED, .COMBO: .BREASTFEED
        case .PUMP: .PUMP
        case .SLEEP: .SLEEP
        default: nil
        }
    }

    init(request: EntryRequest, repos: Repositories) {
        self.request = request
        self.repos = repos
        let now = nowMs()
        switch request {
        case let .new(kind, milestone, vaccines):
            self.kind = kind
            loaded = true
            let vitaminD = kind == .VITAMIN_D
            draft = EntryDraft(
                startTime: now,
                startTimeSet: !kind.isTimed,
                milestoneKey: milestone?.key,
                milestoneTitle: milestone?.title ?? "",
                dose: vitaminD ? EntryBuilder.VITAMIN_D_DEFAULT_DOSE : nil,
                doseUnit: vitaminD ? EntryBuilder.VITAMIN_D_DEFAULT_UNIT : nil,
                vaccines: vaccines
            )
        case .edit:
            kind = .BOTTLE
            loaded = false
            draft = EntryDraft(startTime: now)
        }
        refreshTimers()
    }

    func refreshTimers() {
        let fresh = TimerControl.store.timers()
        if fresh != timers { timers = fresh }
    }

    var anyTimerActive: Bool {
        guard usesTimers, let group = timerGroup else { return false }
        return group.keys.contains { !(timers[$0]?.isIdle ?? true) }
    }

    var anyTimerRunning: Bool {
        guard usesTimers, let group = timerGroup else { return false }
        return group.keys.contains { timers[$0]?.isRunning == true }
    }

    // MARK: Load

    func load(profile: ProfileEntity?) async {
        if case let .edit(id) = request {
            do {
                guard let row = try await repos.activities.get(id) else { throw ImportError("missing") }
                try await adopt(row)
            } catch {
                self.error = "Couldn't load this entry. Check your connection."
            }
            loaded = true
        }
        if !isEditing, kind == .BOTTLE || kind == .COMBO {
            defaultBottleMl = repos.prefs.defaultBottleMl
            if draft.bottleMl == nil, let defaultBottleMl { draft.bottleMl = defaultBottleMl }
        }
        guard let profile else { return }
        let activities = repos.activities
        if kind == .BOTTLE || kind == .COMBO {
            lastBottleMl = try? await activities.getLatest(familyId: profile.familyId, profileId: profile.id, .BOTTLE_FEED)?.bottle?.totalMl
        }
        if kind == .BREASTFEED || kind == .COMBO {
            lastSide = try? await activities.getLatest(familyId: profile.familyId, profileId: profile.id, .BREASTFEED)?.breastfeed?.endSide
        }
        if !isEditing, kind == .VITAMIN_D,
           let last = try? await activities.getLatest(familyId: profile.familyId, profileId: profile.id, .VITAMIN_D)?.medical,
           let dose = last.dose,
           draft.dose == EntryBuilder.VITAMIN_D_DEFAULT_DOSE, draft.doseUnit == EntryBuilder.VITAMIN_D_DEFAULT_UNIT {
            draft.dose = dose
            draft.doseUnit = last.doseUnit ?? draft.doseUnit
        }
    }

    /// Loads a row (and its combo sibling) into the form.
    private func adopt(_ row: ActivityEntity) async throws {
        if let group = row.comboGroupId {
            let rows = try await repos.activities.comboRows(group)
            if rows.count > 1 {
                existing = rows
                kind = .COMBO
                draft = EntryBuilder.draftOfCombo(rows)
                return
            }
        }
        existing = [row]
        kind = EntryKind.of(row.type)
        draft = EntryBuilder.draftOf(row)
    }

    // MARK: Timers

    func toggle(_ key: TimerKey) {
        TimerControl.toggle(key)
        refreshTimers()
    }

    func setDuration(_ key: TimerKey, seconds: Int64) {
        if usesTimers {
            TimerControl.setDuration(key, seconds: seconds)
            refreshTimers()
        } else {
            switch key {
            case .BREAST_LEFT: draft.leftSec = seconds
            case .BREAST_RIGHT: draft.rightSec = seconds
            case .PUMP: draft.pumpSec = seconds
            case .SLEEP: draft.endTime = draft.startTime + seconds * 1000
            }
        }
    }

    func reset(_ group: TimerGroup) {
        if usesTimers {
            TimerControl.clear(group)
            refreshTimers()
        } else if group == .PUMP {
            draft.pumpSec = 0
        }
    }

    /// The draft with any running timers folded in, as it would be saved right now.
    func effectiveDraft(_ now: EpochMs) -> EntryDraft {
        guard usesTimers else { return draft }
        var d = draft
        switch kind {
        case .BREASTFEED, .COMBO:
            let left = timers[.BREAST_LEFT] ?? TimerState()
            let right = timers[.BREAST_RIGHT] ?? TimerState()
            let begin: BreastSide? = {
                guard let l = left.sessionStart else { return right.sessionStart != nil ? .RIGHT : nil }
                guard let r = right.sessionStart else { return .LEFT }
                return l <= r ? .LEFT : .RIGHT
            }()
            let end: BreastSide? = {
                if left.isRunning { return .LEFT }
                if right.isRunning { return .RIGHT }
                if begin == .LEFT, right.sessionStart != nil { return .RIGHT }
                if begin == .RIGHT, left.sessionStart != nil { return .LEFT }
                return begin
            }()
            d.leftSec = left.elapsedMs(now) / 1000
            d.rightSec = right.elapsedMs(now) / 1000
            d.beginSide = begin
            d.endSide = end
            if !d.startTimeSet, let first = [left.sessionStart, right.sessionStart].compactMap({ $0 }).min() { d.startTime = first }
        case .PUMP:
            let t = timers[.PUMP] ?? TimerState()
            if !t.isIdle {
                d.pumpSec = t.elapsedMs(now) / 1000
                if !d.startTimeSet, let s = t.sessionStart { d.startTime = s }
            }
        case .SLEEP:
            let t = timers[.SLEEP] ?? TimerState()
            if !t.isIdle {
                let start = d.startTimeSet ? d.startTime : (t.sessionStart ?? d.startTime)
                d.startTime = start
                d.endTime = start + t.elapsedMs(now)
            }
        default:
            break
        }
        return d
    }

    func canSave(_ now: EpochMs) -> Bool { loaded && EntryBuilder.canSave(kind, effectiveDraft(now)) }

    // MARK: Save / delete

    /// Returns true when the sheet should close.
    func save(profile: ProfileEntity?, caregiverId: String?) async -> Bool {
        guard !saving else { return false }
        saving = true
        error = nil
        defer { saving = false }
        let now = nowMs()
        let d = effectiveDraft(now)
        guard let profile else {
            error = "No child selected. Check your connection and try again."
            return false
        }
        guard EntryBuilder.canSave(kind, d) else { return false }
        let ctx = EntryContext(
            familyId: existing.first?.familyId ?? profile.familyId,
            profileId: existing.first(where: { $0.profileId != nil })?.profileId ?? profile.id,
            caregiverId: caregiverId,
            timeZone: TimeZone.current.identifier,
            now: now,
            newId: newUUID
        )
        do {
            if isEditing, kind == .COMBO {
                let (rows, removed) = EntryBuilder.buildComboEdit(d, ctx, existing: existing)
                try await repos.activities.saveAll(rows, existing: existing, removed: removed, now: now)
            } else {
                try await repos.activities.saveAll(EntryBuilder.build(kind, d, ctx, existing: existing.first), existing: existing, now: now)
            }
        } catch is ConflictError {
            if let id = existing.first?.id, let fresh = try? await repos.activities.get(id) { try? await adopt(fresh) }
            error = ConflictError.message
            return false
        } catch {
            self.error = "Couldn't save. Check your connection and tap Save to retry."
            return false
        }
        if usesTimers, let group = timerGroup { TimerControl.clear(group) }
        WidgetRefresher.reloadAll()
        AppModel.shared.scheduleReschedule()
        if !isEditing, kind == .BOTTLE || kind == .COMBO, amountTypedManually,
           shouldOfferDefaultBottleUpdate(isEditing: false, newMl: d.bottleMl, defaultMl: defaultBottleMl) {
            defaultPrompt = d.bottleMl
            return false
        }
        return true
    }

    func delete() async -> Bool {
        guard !existing.isEmpty else { return false }
        do {
            for row in existing { try await repos.activities.delete(row) }
            WidgetRefresher.reloadAll()
            AppModel.shared.scheduleReschedule()
            return true
        } catch is ConflictError {
            error = ConflictError.message
        } catch {
            self.error = "Couldn't delete. Check your connection and try again."
        }
        return false
    }

    /// Clears this sheet's running timers without saving.
    func discardTimers() {
        if usesTimers, let group = timerGroup {
            TimerControl.clear(group)
            refreshTimers()
        }
    }

    func setStart(_ ms: EpochMs) {
        draft.startTime = ms
        draft.startTimeSet = true
        if let end = draft.endTime, end < ms { draft.endTime = nil }
    }
}
