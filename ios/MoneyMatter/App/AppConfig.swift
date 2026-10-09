import Foundation

/// App-wide constants.
enum AppConfig {
    /// Prefilled on the server screen.
    static let defaultServerAddress = "https://budget.pkrishna.dev"

    /// The scheme the backend redirects to at the end of native OAuth (`NATIVE_APP_URL_SCHEME`).
    static let oauthCallbackScheme = "moneymatter"

    /// Keychain service for bearer tokens; the account is the server host.
    nonisolated static let keychainService = "com.pranavkrishna.budgettracker"

    /// Hosts listed under `webcredentials:` in the Associated Domains entitlement. Passkeys
    /// only work against these, so the passkey button is shown only for them.
    static let passkeyHosts: Set<String> = ["budget.pkrishna.dev"]

    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
