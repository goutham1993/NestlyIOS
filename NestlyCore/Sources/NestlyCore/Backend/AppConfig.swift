import Foundation

public enum AppConfig {
    public static let supabaseURL = URL(string: "https://kuyskumyayiwpyiwhkup.supabase.co")!
    /// Publishable (anon) key. RLS is the security boundary; never ship a service-role key.
    public static let supabaseKey = "sb_publishable_zZmg34taTJm9k57PdYBEug_JGcRZ21_"
    public static let photoBucket = "activity-photos"
    public static let profilePhotoBucket = "profile-photos"

    public static let bundleId = "Baby.NestlyIOS"
    public static let appGroup = "group.Baby.NestlyIOS"
    public static let teamId = "3TN6G8DQVM"
    public static let keychainGroup = "\(teamId).\(bundleId).shared"
    public static let keychainService = "nestly.supabase.auth"
    public static let backgroundRefreshId = "\(bundleId).reschedule"

    /// App Group defaults shared with the widget extension and App Intents; falls back to the
    /// app's own defaults when the group entitlement is missing (e.g. unsigned simulator builds).
    public static let sharedDefaults: UserDefaults = UserDefaults(suiteName: appGroup) ?? .standard
}
