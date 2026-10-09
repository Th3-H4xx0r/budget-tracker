import MoneyMatterKit
import SwiftUI

/// Settings > Security > Danger Zone: wipe all financial data (keeping the account) or delete
/// the account. Each needs the user to type a confirmation first.
struct DangerZoneScreen: View {
    @Environment(SessionStore.self) private var session

    @State private var presented: DangerZoneAction?

    var body: some View {
        Form {
            Section {
                Button("Wipe All Data", systemImage: "trash.slash", role: .destructive) {
                    presented = .wipe
                }
            } header: {
                Text("Wipe Data")
            } footer: {
                Text("Deletes every account, transaction, budget, and other record, but keeps your sign-in. You'll set up a base currency again afterwards.")
            }

            Section {
                Button("Delete Account", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                    presented = .delete
                }
            } header: {
                Text("Delete Account")
            } footer: {
                Text("Permanently deletes your account and all of its data. This can't be undone.")
            }
        }
        .navigationTitle("Danger Zone")
        .sheet(item: $presented) { action in
            DangerZoneConfirmSheet(action: action, email: session.user?.email)
        }
    }
}

private enum DangerZoneAction: String, Identifiable {
    case wipe
    case delete

    var id: String { rawValue }
}

/// The type-to-confirm sheet for a destructive action.
private struct DangerZoneConfirmSheet: View {
    let action: DangerZoneAction
    let email: String?

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var typed = ""
    @State private var isWorking = false
    @State private var alert: ErrorAlert?
    @State private var needsSharingAcknowledgement = false

    private static let wipePhrase = "WIPE MY DATA"
    private static let deletePhrase = "DELETE"

    /// The text to type: the fixed phrase for a wipe, the account email for a delete (as on the web).
    private var phrase: String {
        switch action {
        case .wipe: Self.wipePhrase
        case .delete: email.flatMap { $0.isEmpty ? nil : $0 } ?? Self.deletePhrase
        }
    }

    private var matches: Bool { typed.trimmingCharacters(in: .whitespaces) == phrase }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        switch action {
                        case .wipe:
                            Text("All your financial data will be deleted permanently. Your account and sign-in methods stay.")
                        case .delete:
                            Text("Your account and all of its data will be deleted permanently. You'll be signed out.")
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    TextField(text: $typed) {
                        Text(phrase)
                    }
                    .textInputAutocapitalization(action == .wipe ? .characters : .never)
                    .autocorrectionDisabled()
                    .keyboardType(action == .delete && email != nil ? .emailAddress : .default)
                } header: {
                    Text("Type \(Text(phrase).bold()) to confirm")
                        .textCase(nil)
                }

                Section {
                    Button(role: .destructive) {
                        Task { await run(acknowledgeSharing: false) }
                    } label: {
                        HStack {
                            switch action {
                            case .wipe: Text("Wipe All Data")
                            case .delete: Text("Delete Account")
                            }
                            if isWorking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!matches || isWorking)
                }
            }
            .navigationTitle(action == .wipe ? "Wipe Data" : "Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(isWorking)
                }
            }
            .interactiveDismissDisabled(isWorking)
            .errorAlert($alert)
            .confirmationDialog("Some of your data is shared", isPresented: $needsSharingAcknowledgement, titleVisibility: .visible) {
                Button("Wipe Anyway", role: .destructive) { Task { await run(acknowledgeSharing: true) } }
            } message: {
                Text("Accounts or a household you own are shared with other people. Wiping removes their access too.")
            }
        }
    }

    private func run(acknowledgeSharing: Bool) async {
        guard matches else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let client = try settingsSectionsClient(services)
            switch action {
            case .wipe:
                _ = try await client.send(Endpoints.settingsWipeData(acknowledgeSharing: acknowledgeSharing))
                dismiss()
                referenceData.reset()
                // Re-runs the launch check, which lands on onboarding for the now-empty profile.
                await session.retryLaunch()
            case .delete:
                _ = try await client.send(Endpoints.settingsDeleteAccount())
                dismiss()
                await session.signOut()
            }
        } catch {
            let apiError = APIError(error)
            if case .server(409, let code, _) = apiError, code == SettingsSecurityErrorCode.wipeNeedsSharingAcknowledgement {
                needsSharingAcknowledgement = true
            } else {
                alert = ErrorAlert(error)
            }
        }
    }
}
