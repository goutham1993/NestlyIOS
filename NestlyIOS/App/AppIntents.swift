import AppIntents
import NestlyCore

enum EntryKindAppEnum: String, AppEnum {
    case BREASTFEED, BOTTLE, SOLIDS, COMBO, PUMP, DIAPER, SLEEP, ROUTINE, BABY_FIRST, GROWTH, MILESTONE, MEDICAL, VACCINE, VITAMIN_D

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Entry"
    static var caseDisplayRepresentations: [EntryKindAppEnum: DisplayRepresentation] = [
        .BREASTFEED: "Breastfeed", .BOTTLE: "Bottle Feed", .SOLIDS: "Solids", .COMBO: "Combo Feed",
        .PUMP: "Pump", .DIAPER: "Diaper", .SLEEP: "Sleep", .ROUTINE: "Routine", .BABY_FIRST: "Baby First",
        .GROWTH: "Growth", .MILESTONE: "Milestone", .MEDICAL: "Medical", .VACCINE: "Vaccine", .VITAMIN_D: "Vitamin D",
    ]

    var kind: EntryKind { EntryKind(rawValue: rawValue) ?? .BOTTLE }
}

/// Opens the app to a new entry sheet of the given kind (spec §21.4).
struct OpenEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Add entry"
    static var openAppWhenRun = true

    @Parameter(title: "Kind") var kind: EntryKindAppEnum

    init() {}
    init(kind: EntryKindAppEnum) { self.kind = kind }

    @MainActor
    func perform() async throws -> some IntentResult {
        let app = AppModel.shared
        app.tab = .activity
        app.openEntry(.new(kind: kind.kind))
        return .result()
    }
}

struct OpenNightstandIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Nightstand"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.showNightstand = true
        return .result()
    }
}

struct NestlyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogBottleIntent(),
            phrases: [
                "Log a bottle in \(.applicationName)",
                "Add feed in \(.applicationName)",
                "Add a feed now in \(.applicationName)",
                "Log feed with \(.applicationName)",
            ],
            shortTitle: "Add feed",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: LogVitaminDIntent(),
            phrases: ["Log Vitamin D in \(.applicationName)"],
            shortTitle: "Vitamin D",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: OpenEntryIntent(kind: .DIAPER),
            phrases: ["Log a diaper in \(.applicationName)"],
            shortTitle: "Log diaper",
            systemImageName: "humidity.fill"
        )
        AppShortcut(
            intent: OpenEntryIntent(kind: .SLEEP),
            phrases: ["Start sleep in \(.applicationName)"],
            shortTitle: "Start sleep",
            systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: OpenNightstandIntent(),
            phrases: ["Open nightstand in \(.applicationName)"],
            shortTitle: "Nightstand",
            systemImageName: "bed.double.fill"
        )
    }
}
