import AppIntents
import Foundation
import NestlyCore

/// Last quick-log result, shown on the Quick Log widget until it goes stale.
enum WidgetStatus {
    private static let textKey = "widget_last_result"
    private static let atKey = "widget_last_result_at"
    static let visibleFor: TimeInterval = 30 * 60

    static func set(_ text: String) {
        AppConfig.sharedDefaults.set(text, forKey: textKey)
        AppConfig.sharedDefaults.set(Date().timeIntervalSince1970, forKey: atKey)
    }

    static func current(at date: Date = Date()) -> String? {
        let at = AppConfig.sharedDefaults.double(forKey: atKey)
        guard at > 0, date.timeIntervalSince1970 - at < visibleFor else { return nil }
        return AppConfig.sharedDefaults.string(forKey: textKey)
    }
}

/// One-tap bottle feed (spec §21.1); used by the widget, Siri and Shortcuts.
struct LogBottleIntent: AppIntent {
    static var title: LocalizedStringResource = "Add feed"
    static var description = IntentDescription("Logs a bottle feed with your default (or last) amount.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await QuickBottleLog.run()
        let prefs = Preferences.shared.units
        WidgetStatus.set(result.widgetMessage(prefs))
        WidgetRefresher.reloadAll()
        return .result(dialog: IntentDialog(stringLiteral: result.message(prefs)))
    }
}

struct LogVitaminDIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Vitamin D"
    static var description = IntentDescription("Marks today's Vitamin D dose as given.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await QuickVitaminDLog.run()
        let message = result.message()
        WidgetStatus.set(message)
        WidgetRefresher.reloadAll()
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

enum TimerGroupAppEnum: String, AppEnum {
    case BREASTFEED, PUMP, SLEEP

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Timer"
    static var caseDisplayRepresentations: [TimerGroupAppEnum: DisplayRepresentation] = [
        .BREASTFEED: "Breastfeed", .PUMP: "Pump", .SLEEP: "Sleep",
    ]

    var group: TimerGroup { TimerGroup(rawValue: rawValue) ?? .SLEEP }

    init(_ group: TimerGroup) { self = TimerGroupAppEnum(rawValue: group.rawValue) ?? .SLEEP }
}

/// Live Activity Pause / Resume button (spec §21.5).
struct PauseResumeTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or resume timer"
    static var isDiscoverable = false

    @Parameter(title: "Timer") var group: TimerGroupAppEnum

    init() {}
    init(group: TimerGroup) { self.group = TimerGroupAppEnum(group) }

    func perform() async throws -> some IntentResult {
        TimerControl.pauseResume(group.group)
        await LiveTimerActivities.syncAndWait()
        return .result()
    }
}

/// Live Activity "Switch side" button for breastfeeding.
struct SwitchSideIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Switch breastfeeding side"
    static var isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        TimerControl.switchSide()
        await LiveTimerActivities.syncAndWait()
        return .result()
    }
}
