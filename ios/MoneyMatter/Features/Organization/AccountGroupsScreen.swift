import MoneyMatterKit
import SwiftUI

/// Settings › Account Groups: nested groups of accounts. Create, edit, nest, move, delete,
/// and add or remove accounts. Mirrors the web `settings/subpages/accounts-groups` page.
struct AccountGroupsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData

    @State private var store = OrgAccountGroupsStore()
    @State private var editorTarget: OrgAccountGroupEditorTarget?
    @State private var confirmingDelete: OrgAccountGroup?
    @State private var alert: ErrorAlert?

    var body: some View {
        content
            .navigationTitle("Account Groups")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorTarget = .create(parentId: nil)
                    } label: {
                        Label("Add Group", systemImage: "plus")
                    }
                }
            }
            .task {
                store.services = services
                await store.load()
            }
            .refreshable { await store.load() }
            .sheet(item: $editorTarget) { target in
                OrgAccountGroupEditorSheet(target: target, groups: store.groups.value ?? []) {
                    await store.load()
                }
            }
            .confirmationDialog(
                "Delete Group?",
                isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }),
                titleVisibility: .visible,
                presenting: confirmingDelete
            ) { group in
                Button("Delete \(group.name)", role: .destructive) { Task { await delete(group) } }
            } message: { _ in
                Text("Accounts in the group aren't deleted; they just leave the group.")
            }
            .errorAlert($alert)
            .environment(store)
    }

    @ViewBuilder
    private var content: some View {
        switch store.groups {
        case .idle, .loading:
            List {
                ForEach(0..<5, id: \.self) { _ in
                    Label("Group name · 3 accounts", systemImage: "folder.fill")
                }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await store.load() }
        case .loaded(let groups) where groups.isEmpty:
            ContentUnavailableView {
                Label("No Account Groups", systemImage: "folder")
            } description: {
                Text("Group accounts, like everything at one bank, to see them together.")
            } actions: {
                Button("Add Group") { editorTarget = .create(parentId: nil) }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded:
            List {
                ForEach(store.flattened, id: \.group.id) { row in
                    NavigationLink {
                        OrgAccountGroupDetailScreen(groupID: row.group.id)
                            .environment(store)
                    } label: {
                        OrgAccountGroupRow(group: row.group)
                            .padding(.leading, CGFloat(row.depth) * 24)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = row.group }
                        Button("Edit", systemImage: "pencil") { editorTarget = .edit(row.group) }
                            .tint(.indigo)
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editorTarget = .edit(row.group) }
                        Button("Add Subgroup", systemImage: "folder.badge.plus") {
                            editorTarget = .create(parentId: row.group.id)
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = row.group }
                    }
                }
            }
        }
    }

    private func delete(_ group: OrgAccountGroup) async {
        do {
            _ = try await services.orgCoreSend(Endpoints.orgDeleteAccountGroup(id: group.id))
            await store.load()
            await referenceData.refreshAccounts()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

// MARK: - Store

/// The account-group list shared by the list and its detail screens.
@MainActor
@Observable
final class OrgAccountGroupsStore {
    var groups: LoadState<[OrgAccountGroup]> = .idle
    @ObservationIgnored var services: AppServices?

    struct Row {
        let group: OrgAccountGroup
        let depth: Int
    }

    func load() async {
        guard let services else { return }
        if groups.value == nil { groups = .loading }
        do {
            groups = .loaded(try await services.orgCoreSend(Endpoints.orgAccountGroups(includeArchived: true)))
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation { groups = .failed(apiError) }
        }
    }

    /// Every group, depth first, with its nesting depth.
    var flattened: [Row] {
        let all = groups.value ?? []
        var seen = Set<String>()
        func visit(_ group: OrgAccountGroup, depth: Int) -> [Row] {
            guard seen.insert(group.id).inserted else { return [] }
            let children = all.filter { $0.parentGroupId == group.id }
            let nested = children.isEmpty ? group.childGroups : children
            return [Row(group: group, depth: depth)] + nested.flatMap { visit($0, depth: depth + 1) }
        }
        return OrgAccountGroup.roots(of: all).flatMap { visit($0, depth: 0) }
    }

    func group(id: String) -> OrgAccountGroup? {
        flattened.first { $0.group.id == id }?.group
    }

    /// Ids a group can't move under: itself and everything below it.
    func blockedParents(for id: String) -> Set<String> {
        var result: Set<String> = [id]
        var queue = [id]
        let rows = flattened
        while let current = queue.popLast() {
            for row in rows where row.group.parentGroupId == current && !result.contains(row.group.id) {
                result.insert(row.group.id)
                queue.append(row.group.id)
            }
            if let group = rows.first(where: { $0.group.id == current })?.group {
                for child in group.childGroups where !result.contains(child.id) {
                    result.insert(child.id)
                    queue.append(child.id)
                }
            }
        }
        return result
    }
}

// MARK: - Rows

private struct OrgAccountGroupRow: View {
    let group: OrgAccountGroup

    var body: some View {
        HStack(spacing: 12) {
            OrgAccountGroupLogoView(group: group)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                Text("\(group.accounts.count) accounts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if group.bankDataProviderConnectionId != nil {
                Image(systemName: "building.columns")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Bank connection group"))
            }
        }
    }
}

private struct OrgAccountGroupLogoView: View {
    let group: OrgAccountGroup

    var body: some View {
        if let initials = group.logoInitials, !initials.isEmpty {
            InitialsBadge(initials, colorHex: group.logoColor)
        } else if let domain = group.logoDomain, !domain.isEmpty {
            InitialsBadge(String(domain.prefix(1)).uppercased(), colorHex: group.logoColor)
        } else {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Detail

private struct OrgAccountGroupDetailScreen: View {
    let groupID: String

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(OrgAccountGroupsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var editorTarget: OrgAccountGroupEditorTarget?
    @State private var isPickingAccounts = false
    @State private var isMoving = false
    @State private var confirmingDelete = false
    @State private var alert: ErrorAlert?

    private var group: OrgAccountGroup? { store.group(id: groupID) }

    var body: some View {
        List {
            if let group {
                Section("Accounts") {
                    if group.accounts.isEmpty {
                        Text("No accounts in this group yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(group.accounts) { account in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
                                Text(account.currencyCode)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            AmountText(account.currentBalance, currencyCode: account.currencyCode)
                        }
                        .swipeActions {
                            Button("Remove", systemImage: "folder.badge.minus", role: .destructive) {
                                Task { await remove(account) }
                            }
                        }
                    }
                    Button("Add Accounts", systemImage: "plus") { isPickingAccounts = true }
                }
                let children = store.flattened.filter { $0.group.parentGroupId == group.id }
                if !children.isEmpty {
                    Section("Subgroups") {
                        ForEach(children, id: \.group.id) { row in
                            NavigationLink {
                                OrgAccountGroupDetailScreen(groupID: row.group.id)
                                    .environment(store)
                            } label: {
                                OrgAccountGroupRow(group: row.group)
                            }
                        }
                    }
                }
                Section {
                    Button("Edit Group", systemImage: "pencil") { editorTarget = .edit(group) }
                    Button("Add Subgroup", systemImage: "folder.badge.plus") { editorTarget = .create(parentId: group.id) }
                    Button("Move Group", systemImage: "arrow.up.and.down.and.arrow.left.and.right") { isMoving = true }
                    Button("Delete Group", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            } else if case .failed(let error) = store.groups {
                InlineRetryView(ErrorMessage.message(for: error)) { await store.load() }
            } else {
                ContentUnavailableView("Group Not Found", systemImage: "folder.badge.questionmark")
            }
        }
        .navigationTitle(group?.name ?? String(localized: "Group"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.load() }
        .sheet(item: $editorTarget) { target in
            OrgAccountGroupEditorSheet(target: target, groups: store.groups.value ?? []) {
                await store.load()
            }
        }
        .sheet(isPresented: $isPickingAccounts) {
            OrgAccountGroupAccountPicker(groupID: groupID, existingIDs: Set(group?.accounts.map(\.id) ?? [])) {
                await store.load()
                await referenceData.refreshAccounts()
            }
        }
        .sheet(isPresented: $isMoving) {
            OrgAccountGroupMoveSheet(groupID: groupID)
                .environment(store)
        }
        .confirmationDialog("Delete Group?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Group", role: .destructive) { Task { await deleteGroup() } }
        } message: {
            Text("Accounts in the group aren't deleted; they just leave the group.")
        }
        .errorAlert($alert)
    }

    private func remove(_ account: Account) async {
        do {
            _ = try await services.orgCoreSend(Endpoints.orgRemoveAccountsFromGroup(groupId: groupID, accountIds: [account.id]))
            await store.load()
            await referenceData.refreshAccounts()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func deleteGroup() async {
        do {
            _ = try await services.orgCoreSend(Endpoints.orgDeleteAccountGroup(id: groupID))
            await store.load()
            await referenceData.refreshAccounts()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

// MARK: - Account picker

private struct OrgAccountGroupAccountPicker: View {
    let groupID: String
    let existingIDs: Set<String>
    let onDone: () async -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<String>()
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    private var candidates: [Account] {
        referenceData.activeAccounts.filter { !existingIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    ContentUnavailableView("No Other Accounts", systemImage: "tray", description: Text("Every active account is already in this group."))
                }
                ForEach(candidates) { account in
                    Button {
                        if selected.contains(account.id) { selected.remove(account.id) } else { selected.insert(account.id) }
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(account.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(account.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                .accessibilityHidden(true)
                            Text(account.name).foregroundStyle(.primary)
                            Spacer()
                            Text(account.currencyCode).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityAddTraits(selected.contains(account.id) ? .isSelected : [])
                }
            }
            .disabled(isSaving)
            .navigationTitle("Add Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Add") { Task { await add() } }
                            .disabled(selected.isEmpty)
                    }
                }
            }
            .errorAlert($alert)
        }
    }

    private func add() async {
        isSaving = true
        defer { isSaving = false }
        do {
            for id in selected {
                _ = try await services.orgCoreSend(Endpoints.orgAddAccountToGroup(groupId: groupID, accountId: id))
            }
            await onDone()
            dismiss()
        } catch {
            await onDone()
            alert = ErrorAlert(error)
        }
    }
}

// MARK: - Move

private struct OrgAccountGroupMoveSheet: View {
    let groupID: String

    @Environment(AppServices.self) private var services
    @Environment(OrgAccountGroupsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    var body: some View {
        NavigationStack {
            List {
                let current = store.group(id: groupID)?.parentGroupId
                Section {
                    Button {
                        Task { await move(to: nil) }
                    } label: {
                        Label("Top Level", systemImage: "arrow.up.to.line")
                    }
                    .disabled(current == nil)
                }
                Section("Move Under") {
                    let blocked = store.blockedParents(for: groupID)
                    ForEach(store.flattened.filter { !blocked.contains($0.group.id) }, id: \.group.id) { row in
                        Button {
                            Task { await move(to: row.group.id) }
                        } label: {
                            HStack {
                                Text(row.group.name).foregroundStyle(.primary)
                                Spacer()
                                if row.group.id == current {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                        .accessibilityLabel(Text("Current parent"))
                                }
                            }
                            .padding(.leading, CGFloat(row.depth) * 20)
                        }
                        .disabled(row.group.id == current)
                    }
                }
            }
            .disabled(isSaving)
            .navigationTitle("Move Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if isSaving { ToolbarItem(placement: .confirmationAction) { ProgressView() } }
            }
            .errorAlert($alert)
        }
    }

    private func move(to parentId: String?) async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await services.orgCoreSend(Endpoints.orgMoveAccountGroup(id: groupID, newParentGroupId: parentId))
            await store.load()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

// MARK: - Editor

enum OrgAccountGroupEditorTarget: Identifiable {
    case create(parentId: String?)
    case edit(OrgAccountGroup)

    var id: String {
        switch self {
        case .create(let parentId): "create-\(parentId ?? "root")"
        case .edit(let group): group.id
        }
    }
}

private struct OrgAccountGroupEditorSheet: View {
    let target: OrgAccountGroupEditorTarget
    let groups: [OrgAccountGroup]
    let onSaved: () async -> Void

    private enum LogoStyle: Hashable { case none, domain, initials }

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var parentId: String?
    @State private var logoStyle: LogoStyle = .none
    @State private var domain = ""
    @State private var initials = ""
    @State private var logoColor = OrgColorHex.color(from: nil)
    @State private var isSaving = false
    @State private var alert: ErrorAlert?
    @State private var didLoad = false

    private var editing: OrgAccountGroup? {
        if case .edit(let group) = target { return group }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    if editing == nil {
                        Picker("Parent Group", selection: $parentId) {
                            Text("None (Top Level)").tag(String?.none)
                            ForEach(groups) { group in
                                Text(group.name).tag(Optional(group.id))
                            }
                        }
                    }
                }
                Section {
                    Picker("Logo", selection: $logoStyle) {
                        Text("Folder").tag(LogoStyle.none)
                        Text("Website").tag(LogoStyle.domain)
                        Text("Initials").tag(LogoStyle.initials)
                    }
                    .pickerStyle(.segmented)
                    switch logoStyle {
                    case .none:
                        EmptyView()
                    case .domain:
                        TextField("example.com", text: $domain)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    case .initials:
                        TextField("Initials", text: $initials)
                            .textInputAutocapitalization(.characters)
                            .onChange(of: initials) { _, value in
                                if value.count > 2 { initials = String(value.prefix(2)) }
                            }
                        ColorPicker("Colour", selection: $logoColor, supportsOpacity: false)
                    }
                } header: {
                    Text("Logo")
                } footer: {
                    if logoStyle == .domain {
                        Text("The group shows the brand logo for this website.")
                    }
                }
            }
            .navigationTitle(editing == nil ? "New Group" : "Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!isValid)
                    }
                }
            }
            .onAppear(perform: populate)
            .errorAlert($alert)
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValid: Bool {
        guard !trimmedName.isEmpty else { return false }
        switch logoStyle {
        case .none: return true
        case .domain: return !domain.trimmingCharacters(in: .whitespaces).isEmpty
        case .initials: return !initials.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func populate() {
        guard !didLoad else { return }
        didLoad = true
        switch target {
        case .create(let parent):
            parentId = parent
        case .edit(let group):
            name = group.name
            parentId = group.parentGroupId
            if let value = group.logoDomain, !value.isEmpty {
                logoStyle = .domain
                domain = value
            } else if let value = group.logoInitials, !value.isEmpty {
                logoStyle = .initials
                initials = value
                logoColor = OrgColorHex.color(from: group.logoColor)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let logo: OrgAccountGroupLogo = switch logoStyle {
        case .none: .none
        case .domain: .domain(domain.trimmingCharacters(in: .whitespaces).lowercased())
        case .initials: .initials(initials.trimmingCharacters(in: .whitespaces).uppercased(), color: OrgColorHex.string(from: logoColor))
        }
        do {
            if let editing {
                let request = OrgAccountGroupRequest(name: trimmedName, logo: logo, isUpdate: true)
                _ = try await services.orgCoreSend(Endpoints.orgUpdateAccountGroup(id: editing.id, request))
            } else {
                let request = OrgAccountGroupRequest(name: trimmedName, parentGroupId: parentId, logo: logo, isUpdate: false)
                _ = try await services.orgCoreSend(Endpoints.orgCreateAccountGroup(request))
            }
            await onSaved()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}
