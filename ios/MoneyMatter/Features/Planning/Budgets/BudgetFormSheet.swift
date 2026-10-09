import MoneyMatterKit
import SwiftUI

/// Creates a budget (manual or category) or edits one. Editing matches the web: name, limit,
/// and, for category budgets, the tracked categories. Dates are fixed after creation.
struct BudgetFormSheet: View {
    let budget: PlanningBudget?
    var onSaved: (PlanningBudget?) -> Void

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var type: PlanningBudgetType
    @State private var categoryIDs: Set<String>
    @State private var hasStart = false
    @State private var startDate = Calendar.current.startOfDay(for: .now)
    @State private var hasEnd = false
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var autoInclude = false
    @State private var limit: Decimal?
    @State private var isSaving = false
    @State private var alert: ErrorAlert?
    @FocusState private var isNameFocused: Bool

    init(budget: PlanningBudget?, onSaved: @escaping (PlanningBudget?) -> Void) {
        self.budget = budget
        self.onSaved = onSaved
        _name = State(initialValue: budget?.name ?? "")
        _type = State(initialValue: budget?.type == .category ? .category : .manual)
        _categoryIDs = State(initialValue: Set(budget?.categories.map(\.id) ?? []))
        _limit = State(initialValue: budget?.limitAmount)
    }

    private var isEditing: Bool { budget != nil }
    private var currencyCode: String { session.baseCurrency?.currencyCode ?? "USD" }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasBothDates: Bool { hasStart && hasEnd }

    private var canSave: Bool {
        !isSaving && !trimmedName.isEmpty && trimmedName.count <= 200
            && (type != .category || !categoryIDs.isEmpty)
            && (limit ?? 1) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                }

                if !isEditing {
                    Section {
                        Picker("Type", selection: $type) {
                            Text("Manual").tag(PlanningBudgetType.manual)
                            Text("Category").tag(PlanningBudgetType.category)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Type")
                    } footer: {
                        if type == .category {
                            Text("Tracks every transaction in the chosen categories automatically.")
                        } else {
                            Text("You pick which transactions belong to the budget.")
                        }
                    }
                }

                if type == .category {
                    Section {
                        NavigationLink {
                            BudgetCategoryPickerList(selection: $categoryIDs)
                        } label: {
                            LabeledContent("Categories") {
                                if categoryIDs.isEmpty {
                                    Text("None")
                                } else {
                                    Text("\(categoryIDs.count) selected")
                                }
                            }
                        }
                    } footer: {
                        if categoryIDs.isEmpty {
                            Text("Choose at least one category.")
                        }
                    }
                }

                periodSection

                if !isEditing, type == .manual {
                    Section {
                        Toggle("Auto-include Transactions", isOn: $autoInclude)
                            .disabled(!hasBothDates)
                    } footer: {
                        Text("Adds new transactions dated within the budget's period. Needs both a start and an end date.")
                    }
                }

                Section {
                    HStack {
                        TextField("No limit", value: $limit, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                        Text(currencyCode)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Limit")
                } footer: {
                    if isEditing, budget?.limitAmount != nil {
                        Text("The limit can be changed but not removed.")
                    } else {
                        Text("Optional. Used to show how much of the budget is spent.")
                    }
                }
            }
            .navigationTitle(isEditing ? Text("Edit Budget") : Text("New Budget"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button {
                            Task { await save() }
                        } label: {
                            isEditing ? Text("Save") : Text("Create")
                        }
                        .disabled(!canSave)
                    }
                }
            }
            .onChange(of: hasBothDates) { _, both in
                if !both { autoInclude = false }
            }
            .onAppear { if !isEditing { isNameFocused = true } }
            .errorAlert($alert)
        }
        .interactiveDismissDisabled(isSaving)
    }

    @ViewBuilder private var periodSection: some View {
        if let budget {
            Section("Period") {
                LabeledContent("Start Date") { dateText(budget.startDate) }
                LabeledContent("End Date") { dateText(budget.endDate) }
            }
        } else {
            Section {
                Toggle("Start Date", isOn: $hasStart.animation())
                if hasStart {
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                }
                Toggle("End Date", isOn: $hasEnd.animation())
                if hasEnd {
                    DatePicker(
                        "Ends",
                        selection: $endDate,
                        in: (hasStart ? startDate : .distantPast)...,
                        displayedComponents: .date
                    )
                }
            } header: {
                Text("Period")
            } footer: {
                if type == .category, !hasStart, !hasEnd {
                    Text("Without dates, the budget tracks all time.")
                }
            }
        }
    }

    private func dateText(_ date: Date?) -> Text {
        if let date {
            Text(date, format: .dateTime.day().month(.abbreviated).year())
        } else {
            Text("Not set")
        }
    }

    private func save() async {
        guard let client = services.client, canSave else { return }
        isSaving = true
        defer { isSaving = false }
        let calendar = Calendar.current
        do {
            let saved: PlanningBudget?
            if let budget {
                let request = PlanningBudgetUpdateRequest(
                    name: trimmedName,
                    categoryIds: budget.type == .category ? Array(categoryIDs) : nil,
                    autoInclude: budget.autoInclude,
                    limitAmount: limit
                )
                saved = try await client.send(Endpoints.updatePlanningBudget(id: budget.id, request))
            } else {
                let start = hasStart ? calendar.startOfDay(for: startDate) : nil
                let end = hasEnd
                    ? calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: endDate))
                    : nil
                let request = PlanningBudgetCreateRequest(
                    name: trimmedName,
                    type: type,
                    categoryIds: type == .category ? Array(categoryIDs) : nil,
                    startDate: start,
                    endDate: end,
                    autoInclude: type == .manual && hasBothDates && autoInclude,
                    limitAmount: limit
                )
                saved = try await client.send(Endpoints.createPlanningBudget(request))
            }
            onSaved(saved)
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// Multi-select over the category tree, children indented under their parent.
private struct BudgetCategoryPickerList: View {
    @Binding var selection: Set<String>
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var searchText = ""

    private struct Entry: Identifiable {
        let category: Category
        let depth: Int
        var id: String { category.id }
    }

    private var entries: [Entry] {
        var result: [Entry] = []
        func walk(_ nodes: [CategoryNode], depth: Int) {
            for node in nodes {
                result.append(Entry(category: node.category, depth: depth))
                walk(node.children, depth: depth + 1)
            }
        }
        walk(referenceData.categoryTree, depth: 0)
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return result }
        return result
            .filter { $0.category.name.localizedCaseInsensitiveContains(query) }
            .map { Entry(category: $0.category, depth: 0) }
    }

    var body: some View {
        List {
            ForEach(entries) { entry in
                Button {
                    if selection.contains(entry.id) {
                        selection.remove(entry.id)
                    } else {
                        selection.insert(entry.id)
                    }
                } label: {
                    HStack(spacing: 12) {
                        CategoryIcon(category: entry.category, size: 28)
                        Text(entry.category.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(entry.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .fontWeight(.semibold)
                        }
                    }
                    .padding(.leading, CGFloat(entry.depth) * 20)
                    .contentShape(.rect)
                }
                .accessibilityAddTraits(selection.contains(entry.id) ? .isSelected : [])
            }
        }
        .overlay {
            if entries.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView("No Categories", systemImage: "tag")
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .searchable(text: $searchText)
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !selection.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { selection.removeAll() }
                }
            }
        }
        .task { await referenceData.loadIfNeeded() }
    }
}
