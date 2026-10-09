import MoneyMatterKit
import SwiftUI

/// The live client for the settings sections, or a network error when the app runs on stubs.
func settingsSectionsClient(_ services: AppServices) throws -> APIClient {
    guard let client = services.client else { throw APIError.network(URLError(.notConnectedToInternet)) }
    return client
}

/// The app color scheme choice, stored on the device (`@AppStorage`) like the web stores it per browser.
enum SettingsAppearanceTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "settings.appearance.theme"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.stars"
        }
    }
}

/// Applies the stored theme with `preferredColorScheme`. Attach once at the root of a window or sheet.
private struct SettingsAppearanceThemeModifier: ViewModifier {
    @AppStorage(SettingsAppearanceTheme.storageKey) private var theme = SettingsAppearanceTheme.system.rawValue

    func body(content: Content) -> some View {
        content.preferredColorScheme(SettingsAppearanceTheme(rawValue: theme)?.colorScheme)
    }
}

extension View {
    /// Applies the theme chosen in Settings > Appearance.
    func settingsAppearanceTheme() -> some View {
        modifier(SettingsAppearanceThemeModifier())
    }
}

/// Loads `GET /user/settings` and applies `PATCH /user/settings` slices optimistically, rolling
/// back and raising an alert when a save fails. Shared by Appearance, Language, and General.
@Observable
final class SettingsPreferencesModel {
    private(set) var state: LoadState<SettingsUserPreferences> = .idle
    private(set) var isSaving = false
    var alert: ErrorAlert?

    var preferences: SettingsUserPreferences? { state.value }

    func loadIfNeeded(services: AppServices) async {
        if case .idle = state { await load(services: services) }
    }

    func load(services: AppServices) async {
        if state.value == nil { state = .loading }
        do {
            let client = try settingsSectionsClient(services)
            state = .loaded(try await client.send(Endpoints.settingsPreferences()))
        } catch {
            let apiError = APIError(error)
            if apiError.isCancellation { return }
            if state.value == nil { state = .failed(apiError) } else { alert = ErrorAlert(error) }
        }
    }

    /// Shows `optimistic` right away, sends `patch`, then adopts the server's merged settings.
    func save(_ patch: SettingsPreferencesPatch, optimistic: (inout SettingsUserPreferences) -> Void, services: AppServices) async {
        guard var current = state.value else { return }
        let previous = current
        optimistic(&current)
        state = .loaded(current)
        isSaving = true
        defer { isSaving = false }
        do {
            let client = try settingsSectionsClient(services)
            state = .loaded(try await client.send(Endpoints.updateSettingsPreferences(patch)))
        } catch {
            state = .loaded(previous)
            alert = ErrorAlert(error)
        }
    }
}
