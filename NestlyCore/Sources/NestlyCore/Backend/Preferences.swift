import Foundation
import Observation

/// Device-local preferences (spec §6), stored in the App Group so the widget, Live Activity and
/// App Intents read the same values.
@Observable
public final class Preferences: @unchecked Sendable {
    public static let shared = Preferences(defaults: AppConfig.sharedDefaults)

    enum Key {
        static let selectedProfile = "selected_profile"
        static let currentCaregiver = "current_caregiver"
        static let cardOrder = "card_order"
        static let disabledToggles = "disabled_toggles"
        static let filters = "filters"
        static let unitVolume = "unit_volume"
        static let unitWeight = "unit_weight"
        static let unitLength = "unit_length"
        static let unitTemperature = "unit_temperature"
        static let defaultBottleMl = "default_bottle_ml"
        static let defaultFeedIntervalMinutes = "default_feed_interval_minutes"
        static let pendingCaregiverName = "pending_caregiver_name"
    }

    @ObservationIgnored private let defaults: UserDefaults

    public private(set) var selectedProfileId: String?
    public private(set) var currentCaregiverId: String?
    public private(set) var cardOrder: [CardKind]
    public private(set) var disabledToggles: Set<ActivityToggle>
    public private(set) var filters: Set<FilterOption>
    public private(set) var units: UnitPrefs
    public private(set) var defaultBottleMl: Double?
    /// Minutes between feeds for the next-feed countdown. Defaults to 3 hours.
    public private(set) var defaultFeedIntervalMinutes: Int

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        selectedProfileId = defaults.string(forKey: Key.selectedProfile)
        currentCaregiverId = defaults.string(forKey: Key.currentCaregiver)
        let storedOrder = (defaults.stringArray(forKey: Key.cardOrder) ?? []).compactMap(CardKind.init(rawValue:))
        let missing = CardKind.defaultOrder.filter { !storedOrder.contains($0) }
        cardOrder = storedOrder.isEmpty ? CardKind.defaultOrder : storedOrder + missing
        disabledToggles = Set((defaults.stringArray(forKey: Key.disabledToggles) ?? []).compactMap(ActivityToggle.init(rawValue:)))
        filters = Set((defaults.stringArray(forKey: Key.filters) ?? []).compactMap(FilterOption.init(rawValue:)))
        units = UnitPrefs(
            volume: defaults.string(forKey: Key.unitVolume).flatMap(VolumeUnit.init(rawValue:)) ?? .ML,
            weight: defaults.string(forKey: Key.unitWeight).flatMap(WeightUnit.init(rawValue:)) ?? .KG,
            length: defaults.string(forKey: Key.unitLength).flatMap(LengthUnit.init(rawValue:)) ?? .CM,
            temp: defaults.string(forKey: Key.unitTemperature).flatMap(TempUnit.init(rawValue:)) ?? .F
        )
        let ml = defaults.object(forKey: Key.defaultBottleMl) as? Double
        defaultBottleMl = (ml ?? 0) > 0 ? ml : nil
        if defaults.object(forKey: Key.defaultFeedIntervalMinutes) != nil {
            let minutes = defaults.integer(forKey: Key.defaultFeedIntervalMinutes)
            defaultFeedIntervalMinutes = minutes > 0 ? minutes : ReminderLogic.defaultIntervalMinutes(.FEED)
        } else {
            defaultFeedIntervalMinutes = ReminderLogic.defaultIntervalMinutes(.FEED)
        }
    }

    /// Re-reads values another process (widget / intent) may have written.
    public func reload() {
        let fresh = Preferences(defaults: defaults)
        if fresh.selectedProfileId != selectedProfileId { selectedProfileId = fresh.selectedProfileId }
        if fresh.currentCaregiverId != currentCaregiverId { currentCaregiverId = fresh.currentCaregiverId }
        if fresh.defaultBottleMl != defaultBottleMl { defaultBottleMl = fresh.defaultBottleMl }
        if fresh.defaultFeedIntervalMinutes != defaultFeedIntervalMinutes { defaultFeedIntervalMinutes = fresh.defaultFeedIntervalMinutes }
        if fresh.units != units { units = fresh.units }
    }

    public func setSelectedProfile(_ id: String?) {
        selectedProfileId = id
        defaults.set(id, forKey: Key.selectedProfile)
    }

    public func setCurrentCaregiver(_ id: String?) {
        currentCaregiverId = id
        defaults.set(id, forKey: Key.currentCaregiver)
    }

    public func setCardOrder(_ order: [CardKind]) {
        cardOrder = order
        defaults.set(order.map(\.rawValue), forKey: Key.cardOrder)
    }

    public func setDisabledToggles(_ toggles: Set<ActivityToggle>) {
        disabledToggles = toggles
        defaults.set(toggles.map(\.rawValue).sorted(), forKey: Key.disabledToggles)
    }

    public func setFilters(_ value: Set<FilterOption>) {
        filters = value
        defaults.set(value.map(\.rawValue).sorted(), forKey: Key.filters)
    }

    public func setUnits(_ value: UnitPrefs) {
        units = value
        defaults.set(value.volume.rawValue, forKey: Key.unitVolume)
        defaults.set(value.weight.rawValue, forKey: Key.unitWeight)
        defaults.set(value.length.rawValue, forKey: Key.unitLength)
        defaults.set(value.temp.rawValue, forKey: Key.unitTemperature)
    }

    /// nil or 0 turns the default off. Stored in mL.
    public func setDefaultBottleMl(_ ml: Double?) {
        let value = (ml ?? 0) > 0 ? ml : nil
        defaultBottleMl = value
        if let value { defaults.set(value, forKey: Key.defaultBottleMl) } else { defaults.removeObject(forKey: Key.defaultBottleMl) }
    }

    /// At least one minute. Stored in minutes; 180 is 3 hours.
    public func setDefaultFeedIntervalMinutes(_ minutes: Int) {
        let value = max(minutes, 1)
        defaultFeedIntervalMinutes = value
        defaults.set(value, forKey: Key.defaultFeedIntervalMinutes)
    }

    /// Caregiver name typed at sign-up when email confirmation delayed the session.
    public var pendingCaregiverName: String? {
        get { defaults.string(forKey: Key.pendingCaregiverName) }
        set { defaults.set(newValue, forKey: Key.pendingCaregiverName) }
    }

    /// Sign-out clears the selection so the next account starts fresh.
    public func clearSelection() {
        setSelectedProfile(nil)
        setCurrentCaregiver(nil)
    }

    public var isCardVisible: (CardKind) -> Bool {
        let disabled = disabledToggles
        return { ActivityToggle.isCardVisible($0, disabled: disabled) }
    }
}
