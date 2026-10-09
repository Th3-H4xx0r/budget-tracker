import MoneyMatterKit
import SwiftUI

/// The category tree as an indented, searchable list. Single selection pops on tap; multi
/// selection toggles checkmarks.
struct TransactionCategoryPicker: View {
    let isSelected: (String) -> Bool
    let onSelect: (Category) -> Void
    var dismissesOnSelect = true

    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List(rows) { row in
            Button {
                onSelect(row.category)
                if dismissesOnSelect { dismiss() }
            } label: {
                HStack(spacing: 12) {
                    CategoryIcon(category: row.category, size: 28)
                    Text(row.category.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    if isSelected(row.category.id) {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.leading, query.isEmpty ? CGFloat(row.depth) * 24 : 0)
                .contentShape(.rect)
            }
            .accessibilityAddTraits(isSelected(row.category.id) ? .isSelected : [])
        }
        .searchable(text: $query, prompt: "Search categories")
        .overlay {
            if !query.isEmpty, rows.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Category")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var rows: [FlattenedCategory] {
        let all = CategoryTree.flatten(referenceData.categoryTree)
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return all }
        return all.filter { $0.category.name.localizedCaseInsensitiveContains(term) }
    }
}

/// Searches payees with `GET /payees?q`; shows every known payee before a search.
struct TransactionPayeePicker: View {
    let selectedId: String?
    let onSelect: (PayeeLookup?) -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [PayeeLookup] = []
    @State private var searchError: APIError?

    var body: some View {
        List {
            Section {
                Button("No Payee") {
                    select(nil)
                }
            }
            Section(query.isEmpty ? "Payees" : "Results") {
                if let searchError, !query.isEmpty {
                    Text(ErrorMessage.message(for: searchError))
                        .foregroundStyle(.secondary)
                }
                ForEach(query.isEmpty ? knownPayees : results) { payee in
                    Button {
                        select(payee)
                    } label: {
                        HStack(spacing: 12) {
                            InitialsBadge(payee.logoInitials ?? payee.name, colorHex: payee.logoColor, size: 28)
                            Text(payee.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if payee.id == selectedId {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(.rect)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search payees")
        .task(id: query) {
            await search()
        }
        .overlay {
            if !query.isEmpty, results.isEmpty, searchError == nil {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Payee")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var knownPayees: [PayeeLookup] {
        referenceData.payees.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            results = []
            searchError = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            results = try await services.taxonomy.searchPayees(query: term).map(\.lookup)
            searchError = nil
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation { searchError = apiError }
        }
    }

    private func select(_ payee: PayeeLookup?) {
        onSelect(payee)
        dismiss()
    }
}

/// Multi-select over the user's tags.
struct TransactionTagsPicker: View {
    @Binding var selection: Set<String>

    @Environment(ReferenceDataStore.self) private var referenceData

    var body: some View {
        List {
            if referenceData.tags.isEmpty {
                ContentUnavailableView("No Tags", systemImage: "tag", description: Text("Tags you create on the web appear here."))
            }
            ForEach(referenceData.tags) { tag in
                Button {
                    if selection.contains(tag.id) {
                        selection.remove(tag.id)
                    } else {
                        selection.insert(tag.id)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: tag.color) ?? .gray)
                            .frame(width: 12, height: 12)
                        Text(tag.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(tag.id) {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .accessibilityAddTraits(selection.contains(tag.id) ? .isSelected : [])
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Multi-select over accounts, for the filter sheet.
struct TransactionAccountsPicker: View {
    @Binding var selection: Set<String>

    @Environment(ReferenceDataStore.self) private var referenceData

    var body: some View {
        List(referenceData.accounts) { account in
            Button {
                if selection.contains(account.id) {
                    selection.remove(account.id)
                } else {
                    selection.insert(account.id)
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name)
                            .foregroundStyle(.primary)
                        if account.isArchived {
                            Text("Archived")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if selection.contains(account.id) {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(.rect)
            }
            .accessibilityAddTraits(selection.contains(account.id) ? .isSelected : [])
        }
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The list filters: type, accounts, categories, and a date range.
struct TransactionFilterSheet: View {
    let onApply: (TransactionFilter) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: TransactionFilter

    init(filter: TransactionFilter, onApply: @escaping (TransactionFilter) -> Void) {
        _draft = State(initialValue: filter)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $draft.kind) {
                        ForEach(TransactionFilter.Kind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    NavigationLink {
                        TransactionAccountsPicker(selection: $draft.accountIds)
                    } label: {
                        LabeledContent("Accounts", value: summary(draft.accountIds.count))
                    }
                    NavigationLink {
                        TransactionCategoryPicker(
                            isSelected: { draft.categoryIds.contains($0) },
                            onSelect: { category in
                                if draft.categoryIds.contains(category.id) {
                                    draft.categoryIds.remove(category.id)
                                } else {
                                    draft.categoryIds.insert(category.id)
                                }
                            },
                            dismissesOnSelect: false
                        )
                    } label: {
                        LabeledContent("Categories", value: summary(draft.categoryIds.count))
                    }
                }
                Section("Date Range") {
                    Toggle("Limit to Dates", isOn: $draft.limitsDates.animation())
                    if draft.limitsDates {
                        DatePicker("From", selection: $draft.from, displayedComponents: .date)
                        DatePicker("To", selection: $draft.to, in: draft.from..., displayedComponents: .date)
                    }
                }
                Section {
                    Button("Reset Filters", role: .destructive) {
                        draft = TransactionFilter()
                    }
                    .disabled(draft.activeCount == 0)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(draft)
                        dismiss()
                    }
                }
            }
        }
    }

    private func summary(_ count: Int) -> String {
        count == 0 ? String(localized: "All") : String(localized: "\(count) selected")
    }
}
