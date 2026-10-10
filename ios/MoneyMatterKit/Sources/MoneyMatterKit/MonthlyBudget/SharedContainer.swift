import Foundation

/// Identifiers the app and its widget extension share: the App Group, the shared Keychain
/// access group, and the keys stored in them.
public enum SharedContainer {
    public static let appGroupID = "group.com.pranavkrishna.budgettracker"

    /// Keychain service for bearer tokens; the account is the server's `hostAndPort`.
    public static let keychainService = "com.pranavkrishna.budgettracker"

    /// The team prefix used when Info.plist doesn't carry `AppIdentifierPrefix`.
    public static let fallbackAppIdentifierPrefix = "VY5CNF8734."

    /// `<TeamID>.com.pranavkrishna.budgettracker.shared`, listed under
    /// `keychain-access-groups` in both the app and the widget entitlements.
    public static var keychainAccessGroup: String {
        let fromInfo = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String
        let prefix = fromInfo.flatMap { $0.hasSuffix(".") && $0.count > 1 ? $0 : nil } ?? fallbackAppIdentifierPrefix
        return "\(prefix)com.pranavkrishna.budgettracker.shared"
    }

    /// `BGTaskSchedulerPermittedIdentifiers` entry for the background budget refresh.
    public static let budgetRefreshTaskIdentifier = "com.pranavkrishna.budgettracker.budget-refresh"

    /// The widget `kind`, for targeted reloads.
    public static let monthlyBudgetWidgetKind = "MonthlyBudgetWidget"

    /// Opened when the widget is tapped.
    public static let homeURL = URL(string: "moneymatter://home")!

    /// Opened from the widget's "Set a monthly budget" state.
    public static let setBudgetURL = URL(string: "moneymatter://settings/monthly-budget")!

    /// Key of the server origin string in `defaults`.
    public static let serverOriginKey = "serverOrigin"

    /// The App Group defaults, or `.standard` where the group isn't provisioned (e.g. `swift test`).
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// The server the app is connected to, as mirrored into the App Group.
    public static func server(defaults: UserDefaults = SharedContainer.defaults) -> ServerEndpoint? {
        guard let origin = defaults.string(forKey: serverOriginKey) else { return nil }
        return try? ServerEndpoint(validating: origin)
    }
}
