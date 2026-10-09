import MoneyMatterKit
import SwiftUI

/// Create or edit a payee: name, default category, categorization mode, default tags, and
/// logo (automatic, a website domain, or custom initials on a colour).
struct OrgPayeeFormSheet: View {
    let payee: OrgPayee?
    let onSaved: (OrgPayee) -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var categoryId: String?
    @State private var mode: OrgPayeeCategorizationMode = .enforce
    @State private var tagIds: Set<String> = []
    @State private var logoKind: LogoKind = .automatic
    @State private var logoDomain = ""
    @State private var logoInitials = ""
    @State private var logoColor: Color = Color(hex: "#7c3aed") ?? .purple
    @State private var nameError: String?
    @State private var isSaving = false
    @State private var alert: ErrorAlert?
    @State private var didLoad = false

    enum LogoKind: Hashable {
        case automatic
        case domain
        case initials
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .onChange(of: name) { nameError = nil }
                } footer: {
                    if let nameError {
                        Text(nameError).foregroundStyle(.red)
                    }
                }

                Section {
                    NavigationLink {
                        TransactionCategoryPicker(isSelected: { $0 == categoryId }) { category in
                            categoryId = category.id
                        }
                    } label: {
                        LabeledContent("Default Category") {
                            Text(referenceData.category(id: categoryId)?.name ?? String(localized: "None"))
                        }
                    }
                    if categoryId != nil {
                        Button("Clear Default Category", role: .destructive) { categoryId = nil }
                    }
                    Picker("Categorization", selection: $mode) {
                        ForEach(OrgPayeeCategorizationMode.allCases, id: \.self) { option in
                            Text(OrgPayeeSupport.title(for: option)).tag(option)
                        }
                    }
                } header: {
                    Text("Categorization")
                } footer: {
                    Text(OrgPayeeSupport.hint(for: mode))
                }

                Section {
                    NavigationLink {
                        TransactionTagsPicker(selection: $tagIds)
                    } label: {
                        LabeledContent("Default Tags") {
                            Text(tagSummary)
                        }
                    }
                } footer: {
                    Text("Added to new transactions from this payee unless you pick tags yourself.")
                }

                Section("Logo") {
                    Picker("Logo", selection: $logoKind) {
                        Text("Automatic").tag(LogoKind.automatic)
                        Text("Website").tag(LogoKind.domain)
                        Text("Initials").tag(LogoKind.initials)
                    }
                    .pickerStyle(.segmented)
                    switch logoKind {
                    case .automatic:
                        Text("MoneyMatter matches a brand logo from the payee's name.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    case .domain:
                        TextField("Domain, e.g. netflix.com", text: $logoDomain)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    case .initials:
                        HStack {
                            TextField("Initials", text: $logoInitials)
                                .onChange(of: logoInitials) {
                                    if logoInitials.count > 2 { logoInitials = String(logoInitials.prefix(2)) }
                                }
                            OrgPayeeLogoBadge(
                                name: name,
                                initials: logoInitials.isEmpty ? nil : logoInitials,
                                colorHex: OrgPayeeSupport.hex(from: logoColor),
                                size: 32
                            )
                        }
                        ColorPicker("Colour", selection: $logoColor, supportsOpacity: false)
                    }
                }
            }
            .navigationTitle(payee == nil ? "New Payee" : "Edit Payee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($alert)
            .onAppear(perform: populate)
        }
    }

    private var tagSummary: String {
        let names = tagIds.compactMap { referenceData.tag(id: $0)?.name }.sorted()
        return names.isEmpty ? String(localized: "None") : names.joined(separator: ", ")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        guard !trimmedName.isEmpty else { return false }
        switch logoKind {
        case .automatic: return true
        case .domain: return !logoDomain.trimmingCharacters(in: .whitespaces).isEmpty
        case .initials: return !logoInitials.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private static func initialKind(of payee: OrgPayee) -> LogoKind {
        if let initials = payee.logoInitials, !initials.isEmpty { return .initials }
        if payee.logoSource == "manual", let domain = payee.logoDomain, !domain.isEmpty { return .domain }
        return .automatic
    }

    private func populate() {
        guard !didLoad else { return }
        didLoad = true
        guard let payee else { return }
        name = payee.name
        categoryId = payee.defaultCategoryId
        mode = payee.categorizationMode == .unknown ? .enforce : payee.categorizationMode
        tagIds = Set(payee.defaultTagIds)
        logoKind = Self.initialKind(of: payee)
        logoDomain = payee.logoDomain ?? ""
        logoInitials = payee.logoInitials ?? ""
        if let color = Color(hex: payee.logoColor) { logoColor = color }
    }

    private func logoFields(into request: inout OrgPayeeWriteRequest) {
        switch logoKind {
        case .automatic:
            break
        case .domain:
            request.logoDomain = .set(logoDomain.trimmingCharacters(in: .whitespaces).lowercased())
            request.logoInitials = .clear
            request.logoColor = .clear
        case .initials:
            request.logoInitials = .set(logoInitials.trimmingCharacters(in: .whitespaces))
            request.logoColor = .set(OrgPayeeSupport.hex(from: logoColor))
            request.logoDomain = .clear
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var request = OrgPayeeWriteRequest(
            name: trimmedName,
            defaultCategoryId: categoryId.map { FieldUpdate<String>.set($0) } ?? (payee?.defaultCategoryId == nil ? .unchanged : .clear),
            categorizationMode: mode,
            defaultTagIds: Array(tagIds).sorted()
        )
        logoFields(into: &request)
        do {
            let client = try OrgPayeeSupport.client(services)
            var saved: OrgPayee
            if let payee {
                saved = try await client.send(Endpoints.orgUpdatePayee(id: payee.id, request))
                if logoKind == .automatic, Self.initialKind(of: payee) != .automatic {
                    saved = try await client.send(Endpoints.orgResetPayeeLogo(id: payee.id))
                }
            } else {
                saved = try await client.send(Endpoints.orgCreatePayee(request))
            }
            await referenceData.refreshPayees()
            onSaved(saved)
            dismiss()
        } catch {
            if OrgPayeeSupport.isConflict(error) {
                let message = APIError(error).serverMessage ?? ""
                nameError = message.isEmpty ? String(localized: "Another payee already uses this name.") : message
            } else {
                alert = ErrorAlert(error)
            }
        }
    }
}
