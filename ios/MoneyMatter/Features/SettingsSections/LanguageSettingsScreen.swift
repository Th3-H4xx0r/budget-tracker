import MoneyMatterKit
import SwiftUI

/// Settings > App > Language: the account language, used by the web app and by server-sent text
/// such as emails. The app's own language follows iOS Settings.
struct LanguageSettingsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(\.openURL) private var openURL
    @State private var model = SettingsPreferencesModel()

    var body: some View {
        Form {
            switch model.state {
            case .failed(let error):
                Section {
                    InlineRetryView(ErrorMessage.message(for: error)) { await model.load(services: services) }
                }
            case .loaded(let preferences):
                languages(selected: preferences.locale ?? .english)
            case .idle, .loading:
                languages(selected: .english)
                    .redactedWhileLoading(true)
            }

            Section {
                Button("Open iOS Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } header: {
                Text("App Language")
            } footer: {
                Text("To change the language of this app, choose MoneyMatter in iOS Settings, then Language.")
            }
        }
        .navigationTitle("Language")
        .task { await model.loadIfNeeded(services: services) }
        .refreshable { await model.load(services: services) }
        .errorAlert($model.alert)
    }

    private func languages(selected: SettingsLocale) -> some View {
        Section {
            ForEach(SettingsLocale.allCases, id: \.code) { locale in
                Button {
                    guard locale != selected else { return }
                    Task {
                        await model.save(
                            SettingsPreferencesPatch(localeCode: locale.code),
                            optimistic: { $0.localeCode = locale.code },
                            services: services
                        )
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: locale.nativeName)
                                .foregroundStyle(.primary)
                            if locale.isCommunityTranslated {
                                Text("Community translation")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if locale == selected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityAddTraits(locale == selected ? .isSelected : [])
                .disabled(model.isSaving)
            }
        } header: {
            Text("Account Language")
        } footer: {
            Text("Used by MoneyMatter on the web and for emails and other messages from the server. Community translations may be incomplete.")
        }
    }
}
