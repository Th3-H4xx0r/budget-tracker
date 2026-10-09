import MoneyMatterKit
import SwiftUI

/// Settings › Categories: the category hierarchy with create, edit, move, and delete.
/// Mirrors the web `settings/subpages/categories` page.
struct CategoriesSettingsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData

    @State private var editorTarget: OrgCategoryEditorTarget?
    @State private var movingCategory: Category?
    @State private var reassigning: OrgCategoryReassignment?
    @State private var confirmingDelete: Category?
    @State private var alert: ErrorAlert?

    var body: some View {
        content
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorTarget = .create(parentId: nil)
                    } label: {
                        Label("Add Category", systemImage: "plus")
                    }
                }
            }
            .refreshable { await referenceData.refreshCategories() }
            .task { await referenceData.loadIfNeeded() }
            .sheet(item: $editorTarget) { target in
                OrgCategoryEditorSheet(target: target)
            }
            .sheet(item: $movingCategory) { category in
                OrgCategoryMoveSheet(category: category)
            }
            .sheet(item: $reassigning) { reassignment in
                OrgCategoryReassignSheet(reassignment: reassignment)
            }
            .confirmationDialog(
                "Delete Category?",
                isPresented: Binding(
                    get: { confirmingDelete != nil },
                    set: { if !$0 { confirmingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: confirmingDelete
            ) { category in
                Button("Delete \(category.name)", role: .destructive) {
                    Task { await delete(category) }
                }
            } message: { _ in
                Text("This category isn't used by any transactions.")
            }
            .errorAlert($alert)
    }

    @ViewBuilder
    private var content: some View {
        let rows = CategoryTree.flatten(referenceData.categoryTree)
        if rows.isEmpty, !referenceData.hasLoaded, let error = referenceData.lastError {
            LoadFailedView(error: error) { await referenceData.refreshCategories() }
        } else if rows.isEmpty, referenceData.isLoading || !referenceData.hasLoaded {
            List {
                ForEach(0..<8, id: \.self) { index in
                    Label("Category name \(index)", systemImage: "circle.fill")
                }
            }
            .redactedWhileLoading(true)
        } else if rows.isEmpty {
            ContentUnavailableView {
                Label("No Categories", systemImage: "square.grid.2x2")
            } description: {
                Text("Categories group your transactions for budgets and insights.")
            } actions: {
                Button("Add Category") { editorTarget = .create(parentId: nil) }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            List {
                if let error = referenceData.lastError {
                    InlineRetryView(ErrorMessage.message(for: error)) { await referenceData.refreshCategories() }
                }
                ForEach(rows) { row in
                    categoryRow(row)
                }
            }
        }
    }

    private func categoryRow(_ row: FlattenedCategory) -> some View {
        let category = row.category
        let isInternal = category.type == .internal
        let canHaveChildren = !isInternal && row.depth + 1 < OrgCategoryRules.maxNesting
        return Button {
            if !isInternal { editorTarget = .edit(category) }
        } label: {
            HStack(spacing: 12) {
                CategoryIcon(category: category, size: 30)
                Text(category.name)
                    .foregroundStyle(.primary)
                Spacer()
                if isInternal {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("System category"))
                }
            }
            .padding(.leading, CGFloat(row.depth) * 24)
        }
        .swipeActions(edge: .trailing) {
            if !isInternal {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    Task { await requestDelete(category) }
                }
                Button("Move", systemImage: "arrow.up.and.down.and.arrow.left.and.right") {
                    movingCategory = category
                }
                .tint(.indigo)
            }
        }
        .contextMenu {
            if !isInternal {
                Button("Edit", systemImage: "pencil") { editorTarget = .edit(category) }
                if canHaveChildren {
                    Button("Add Subcategory", systemImage: "plus") { editorTarget = .create(parentId: category.id) }
                }
                Button("Move", systemImage: "arrow.up.and.down.and.arrow.left.and.right") { movingCategory = category }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    Task { await requestDelete(category) }
                }
            }
        }
    }

    /// Subcategories block deletion; transactions need a replacement category first.
    private func requestDelete(_ category: Category) async {
        if referenceData.categories.contains(where: { $0.parentId == category.id }) {
            alert = ErrorAlert(
                title: String(localized: "Can't Delete Category"),
                message: String(localized: "Delete or move its subcategories first.")
            )
            return
        }
        do {
            let count = try await services.orgCoreSend(Endpoints.orgCategoryTransactionCount(id: category.id))
            if count > 0 {
                reassigning = OrgCategoryReassignment(category: category, transactionCount: count)
            } else {
                confirmingDelete = category
            }
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func delete(_ category: Category) async {
        do {
            _ = try await services.orgCoreSend(Endpoints.orgDeleteCategory(id: category.id))
            await referenceData.refreshCategories()
        } catch let error as APIError {
            if case .server(409, _, _) = error {
                await requestDelete(category)
            } else {
                alert = ErrorAlert(error)
            }
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

// MARK: - Rules

/// The web app's category nesting rules: three levels, internal categories can't take children,
/// and a category can't move under itself or its own subtree.
enum OrgCategoryRules {
    static let maxNesting = 3

    static func subtreeHeight(of id: String, in categories: [Category]) -> Int {
        let children = categories.filter { $0.parentId == id && $0.id != id }
        return 1 + (children.map { subtreeHeight(of: $0.id, in: categories) }.max() ?? 0)
    }

    static func descendants(of id: String, in categories: [Category]) -> Set<String> {
        var result = Set<String>()
        var queue = [id]
        while let current = queue.popLast() {
            for child in categories where child.parentId == current && !result.contains(child.id) {
                result.insert(child.id)
                queue.append(child.id)
            }
        }
        return result
    }

    /// Categories that can parent `movingID` (or a new category when `nil`), with depth.
    static func parentOptions(for movingID: String?, tree: [CategoryNode], categories: [Category]) -> [FlattenedCategory] {
        let height = movingID.map { subtreeHeight(of: $0, in: categories) } ?? 1
        let excluded = movingID.map { descendants(of: $0, in: categories).union([$0]) } ?? []
        return CategoryTree.flatten(tree).filter { row in
            row.category.type != .internal
                && !excluded.contains(row.category.id)
                && (row.depth + 1) + height <= maxNesting
        }
    }
}

// MARK: - Editor

enum OrgCategoryEditorTarget: Identifiable {
    case create(parentId: String?)
    case edit(Category)

    var id: String {
        switch self {
        case .create(let parentId): "create-\(parentId ?? "root")"
        case .edit(let category): category.id
        }
    }
}

private struct OrgCategoryEditorSheet: View {
    let target: OrgCategoryEditorTarget

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var color = OrgColorHex.color(from: nil)
    @State private var icon: String?
    @State private var parentId: String?
    @State private var isSaving = false
    @State private var alert: ErrorAlert?
    @State private var didLoad = false

    private var editing: Category? {
        if case .edit(let category) = target { return category }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    ColorPicker("Colour", selection: $color, supportsOpacity: false)
                    OrgIconPickerLink(selection: $icon, tint: color)
                }
                Section {
                    Picker("Parent", selection: $parentId) {
                        Text("None (Top Level)").tag(String?.none)
                        ForEach(parentOptions) { option in
                            Text(verbatim: String(repeating: "    ", count: option.depth) + option.category.name)
                                .tag(Optional(option.category.id))
                        }
                    }
                } footer: {
                    Text("Categories nest up to three levels.")
                }
                Section {
                    HStack {
                        Spacer()
                        CategoryIcon(
                            category: Category(id: "preview", name: name.isEmpty ? "?" : name, color: OrgColorHex.string(from: color), icon: icon),
                            size: 44
                        )
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(editing == nil ? "New Category" : "Edit Category")
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
                            .disabled(trimmedName.isEmpty)
                    }
                }
            }
            .onAppear(perform: populate)
            .errorAlert($alert)
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var parentOptions: [FlattenedCategory] {
        OrgCategoryRules.parentOptions(for: editing?.id, tree: referenceData.categoryTree, categories: referenceData.categories)
    }

    private func populate() {
        guard !didLoad else { return }
        didLoad = true
        switch target {
        case .create(let parent):
            parentId = parent
            if let parentColor = referenceData.category(id: parent)?.color {
                color = OrgColorHex.color(from: parentColor)
            }
        case .edit(let category):
            name = category.name
            color = OrgColorHex.color(from: category.color)
            icon = category.icon
            parentId = category.parentId
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let hex = OrgColorHex.string(from: color)
        do {
            if let editing {
                let parentUpdate: FieldUpdate<String> = parentId == editing.parentId
                    ? .unchanged
                    : parentId.map { .set($0) } ?? .clear
                let iconUpdate: FieldUpdate<String> = icon == editing.icon ? .unchanged : icon.map { .set($0) } ?? .clear
                let request = OrgCategoryUpdateRequest(
                    name: trimmedName,
                    color: hex,
                    icon: iconUpdate,
                    parentId: parentUpdate
                )
                _ = try await services.orgCoreSend(Endpoints.orgUpdateCategory(id: editing.id, request))
            } else {
                let request = OrgCategoryCreateRequest(name: trimmedName, color: hex, icon: icon, parentId: parentId)
                _ = try await services.orgCoreSend(Endpoints.orgCreateCategory(request))
            }
            await referenceData.refreshCategories()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

// MARK: - Move

private struct OrgCategoryMoveSheet: View {
    let category: Category

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await move(to: nil) }
                    } label: {
                        Label("Top Level", systemImage: "arrow.up.to.line")
                    }
                    .disabled(category.parentId == nil)
                }
                Section("Move Under") {
                    let options = OrgCategoryRules.parentOptions(
                        for: category.id,
                        tree: referenceData.categoryTree,
                        categories: referenceData.categories
                    )
                    if options.isEmpty {
                        Text("No category can hold this one without going deeper than three levels.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(options) { option in
                        Button {
                            Task { await move(to: option.category.id) }
                        } label: {
                            HStack(spacing: 12) {
                                CategoryIcon(category: option.category, size: 26)
                                Text(option.category.name).foregroundStyle(.primary)
                                Spacer()
                                if option.category.id == category.parentId {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                        .accessibilityLabel(Text("Current parent"))
                                }
                            }
                            .padding(.leading, CGFloat(option.depth) * 20)
                        }
                        .disabled(option.category.id == category.parentId)
                    }
                }
            }
            .disabled(isSaving)
            .navigationTitle("Move \(category.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if isSaving {
                    ToolbarItem(placement: .confirmationAction) { ProgressView() }
                }
            }
            .errorAlert($alert)
        }
    }

    private func move(to parentId: String?) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let request = OrgCategoryUpdateRequest(parentId: parentId.map { .set($0) } ?? .clear)
            _ = try await services.orgCoreSend(Endpoints.orgUpdateCategory(id: category.id, request))
            await referenceData.refreshCategories()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

// MARK: - Delete with reassign

struct OrgCategoryReassignment: Identifiable {
    let category: Category
    let transactionCount: Int
    var id: String { category.id }
}

private struct OrgCategoryReassignSheet: View {
    let reassignment: OrgCategoryReassignment

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss
    @State private var replacementId: String?
    @State private var isDeleting = false
    @State private var alert: ErrorAlert?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(reassignment.transactionCount) transactions use \(reassignment.category.name). Choose a category to move them to before deleting it.")
                        .foregroundStyle(.secondary)
                }
                Section("Move Transactions To") {
                    ForEach(options) { option in
                        Button {
                            replacementId = option.category.id
                        } label: {
                            HStack(spacing: 12) {
                                CategoryIcon(category: option.category, size: 26)
                                Text(option.category.name).foregroundStyle(.primary)
                                Spacer()
                                if replacementId == option.category.id {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .padding(.leading, CGFloat(option.depth) * 20)
                        }
                        .accessibilityAddTraits(replacementId == option.category.id ? .isSelected : [])
                    }
                }
            }
            .disabled(isDeleting)
            .navigationTitle("Delete \(reassignment.category.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isDeleting {
                        ProgressView()
                    } else {
                        Button("Delete", role: .destructive) { Task { await delete() } }
                            .disabled(replacementId == nil)
                    }
                }
            }
            .errorAlert($alert)
        }
    }

    private var options: [FlattenedCategory] {
        CategoryTree.flatten(referenceData.categoryTree).filter { $0.category.id != reassignment.category.id }
    }

    private func delete() async {
        guard let replacementId else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            _ = try await services.orgCoreSend(
                Endpoints.orgDeleteCategory(id: reassignment.category.id, replaceWithCategoryId: replacementId)
            )
            await referenceData.refreshCategories()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}
