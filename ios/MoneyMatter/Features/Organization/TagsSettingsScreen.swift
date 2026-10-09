import MoneyMatterKit
import SwiftUI

/// Settings › Tags: create, edit, and delete tags, and manage each tag's reminders.
/// Mirrors the web `settings/subpages/tags` page and `api/tags.ts`.
struct TagsSettingsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData

    @State private var editorTarget: OrgTagEditorTarget?
    @State private var confirmingDelete: Tag?
    @State private var alert: ErrorAlert?
    @State private var query = ""

    var body: some View {
        content
            .navigationTitle("Tags")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorTarget = .create
                    } label: {
                        Label("Add Tag", systemImage: "plus")
                    }
                }
            }
            .refreshable { await referenceData.refreshTags() }
            .task { await referenceData.loadIfNeeded() }
            .sheet(item: $editorTarget) { target in
                OrgTagEditorSheet(target: target)
            }
            .confirmationDialog(
                "Delete Tag?",
                isPresented: Binding(
                    get: { confirmingDelete != nil },
                    set: { if !$0 { confirmingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: confirmingDelete
            ) { tag in
                Button("Delete \(tag.name)", role: .destructive) {
                    Task { await delete(tag) }
                }
            } message: { _ in
                Text("The tag is removed from all transactions, and its reminders are deleted.")
            }
            .errorAlert($alert)
    }

    private var filteredTags: [Tag] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let sorted = referenceData.tags.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !trimmed.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedStandardContains(trimmed) }
    }

    @ViewBuilder
    private var content: some View {
        let tags = referenceData.tags
        if tags.isEmpty, !referenceData.hasLoaded, let error = referenceData.lastError {
            LoadFailedView(error: error) { await referenceData.refreshTags() }
        } else if tags.isEmpty, referenceData.isLoading || !referenceData.hasLoaded {
            List {
                ForEach(0..<6, id: \.self) { _ in
                    Label("Tag name", systemImage: "tag.fill")
                }
            }
            .redactedWhileLoading(true)
        } else if tags.isEmpty {
            ContentUnavailableView {
                Label("No Tags", systemImage: "tag")
            } description: {
                Text("Tags label transactions across categories, like trips or projects.")
            } actions: {
                Button("Add Tag") { editorTarget = .create }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            List {
                if let error = referenceData.lastError {
                    InlineRetryView(ErrorMessage.message(for: error)) { await referenceData.refreshTags() }
                }
                ForEach(filteredTags) { tag in
                    NavigationLink {
                        OrgTagDetailScreen(tagID: tag.id)
                    } label: {
                        OrgTagRow(tag: tag)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = tag }
                        Button("Edit", systemImage: "pencil") { editorTarget = .edit(tag) }
                            .tint(.indigo)
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editorTarget = .edit(tag) }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = tag }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search tags")
            .overlay {
                if !query.isEmpty, filteredTags.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }

    private func delete(_ tag: Tag) async {
        do {
            _ = try await services.orgCoreSend(Endpoints.orgDeleteTag(id: tag.id))
            await referenceData.refreshTags()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

private struct OrgTagRow: View {
    let tag: Tag

    var body: some View {
        HStack(spacing: 12) {
            OrgTagBadge(colorHex: tag.color, icon: tag.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                if let description = tag.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let count = tag.remindersCount, count > 0 {
                Label("\(count)", systemImage: "bell.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("\(count) reminders"))
            }
        }
    }
}

// MARK: - Detail

private struct OrgTagDetailScreen: View {
    let tagID: String

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var reminders: LoadState<[OrgTagReminder]> = .idle
    @State private var editorTarget: OrgTagEditorTarget?
    @State private var reminderTarget: OrgTagReminderTarget?
    @State private var confirmingDelete = false
    @State private var alert: ErrorAlert?

    private var tag: Tag? { referenceData.tag(id: tagID) }

    var body: some View {
        List {
            if let tag {
                Section {
                    HStack(spacing: 16) {
                        OrgTagBadge(colorHex: tag.color, icon: tag.icon)
                            .scaleEffect(1.4)
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tag.name).font(.title3.weight(.semibold))
                            if let description = tag.description, !description.isEmpty {
                                Text(description).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                remindersContent
            } header: {
                Text("Reminders")
            } footer: {
                Text("Reminders notify you when tagged spending crosses a limit, or when nothing was tagged in a period.")
            }
        }
        .navigationTitle(tag?.name ?? String(localized: "Tag"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let tag {
                        Button("Edit Tag", systemImage: "pencil") { editorTarget = .edit(tag) }
                    }
                    Button("Add Reminder", systemImage: "bell.badge") { reminderTarget = .create }
                    Button("Delete Tag", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .task { await loadReminders() }
        .refreshable { await loadReminders() }
        .sheet(item: $editorTarget) { OrgTagEditorSheet(target: $0) }
        .sheet(item: $reminderTarget) { target in
            OrgTagReminderEditorSheet(tagID: tagID, target: target) {
                await loadReminders()
                await referenceData.refreshTags()
            }
        }
        .confirmationDialog("Delete Tag?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Tag", role: .destructive) { Task { await deleteTag() } }
        } message: {
            Text("The tag is removed from all transactions, and its reminders are deleted.")
        }
        .errorAlert($alert)
    }

    @ViewBuilder
    private var remindersContent: some View {
        switch reminders {
        case .idle, .loading:
            ForEach(0..<2, id: \.self) { _ in
                Label("Reminder placeholder", systemImage: "bell")
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            InlineRetryView(ErrorMessage.message(for: error)) { await loadReminders() }
        case .loaded(let items) where items.isEmpty:
            ContentUnavailableView {
                Label("No Reminders", systemImage: "bell.slash")
            } actions: {
                Button("Add Reminder") { reminderTarget = .create }
            }
        case .loaded(let items):
            ForEach(items) { reminder in
                Button {
                    reminderTarget = .edit(reminder)
                } label: {
                    OrgTagReminderRow(reminder: reminder, currencyCode: baseCurrencyCode) { isOn in
                        Task { await setEnabled(reminder, isOn: isOn) }
                    }
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Task { await deleteReminder(reminder) }
                    }
                }
            }
        }
    }

    private var baseCurrencyCode: String {
        referenceData.userCurrencies.first(where: \.isDefaultCurrency)?.currencyCode ?? "USD"
    }

    private func loadReminders() async {
        if reminders.value == nil { reminders = .loading }
        do {
            reminders = .loaded(try await services.orgCoreSend(Endpoints.orgTagReminders(tagId: tagID)))
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation { reminders = .failed(apiError) }
        }
    }

    private func setEnabled(_ reminder: OrgTagReminder, isOn: Bool) async {
        let request = OrgTagReminderRequest(
            type: reminder.type,
            frequency: reminder.frequency,
            dayOfMonth: reminder.dayOfMonth,
            amountThreshold: reminder.amountThreshold,
            isEnabled: isOn
        )
        do {
            _ = try await services.orgCoreSend(Endpoints.orgUpdateTagReminder(tagId: tagID, id: reminder.id, request))
        } catch {
            alert = ErrorAlert(error)
        }
        await loadReminders()
    }

    private func deleteReminder(_ reminder: OrgTagReminder) async {
        do {
            _ = try await services.orgCoreSend(Endpoints.orgDeleteTagReminder(tagId: tagID, id: reminder.id))
            await loadReminders()
            await referenceData.refreshTags()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func deleteTag() async {
        do {
            _ = try await services.orgCoreSend(Endpoints.orgDeleteTag(id: tagID))
            await referenceData.refreshTags()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

private struct OrgTagReminderRow: View {
    let reminder: OrgTagReminder
    let currencyCode: String
    let onToggle: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.type == .existenceCheck ? "questionmark.circle" : "gauge.with.dots.needle.67percent")
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(OrgTagReminderText.typeTitle(reminder.type))
                    .foregroundStyle(.primary)
                Text(OrgTagReminderText.summary(reminder, currencyCode: currencyCode))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Toggle("Enabled", isOn: Binding(get: { reminder.isEnabled }, set: onToggle))
                .labelsHidden()
        }
    }
}

enum OrgTagReminderText {
    static func typeTitle(_ type: OrgTagReminderType) -> String {
        switch type {
        case .amountThreshold: String(localized: "Spending Limit")
        case .existenceCheck: String(localized: "Missing Transaction")
        case .unknown: String(localized: "Reminder")
        }
    }

    static func frequencyTitle(_ frequency: OrgTagReminderFrequency?) -> String {
        switch frequency {
        case nil: String(localized: "Immediately")
        case .daily: String(localized: "Daily")
        case .weekly: String(localized: "Weekly")
        case .monthly: String(localized: "Monthly")
        case .quarterly: String(localized: "Quarterly")
        case .yearly: String(localized: "Yearly")
        case .unknown: String(localized: "Custom")
        }
    }

    static func summary(_ reminder: OrgTagReminder, currencyCode: String) -> String {
        var parts = [frequencyTitle(reminder.frequency)]
        if reminder.frequency?.usesDayOfMonth == true {
            parts.append(String(localized: "day \(reminder.dayOfMonth ?? 1)"))
        }
        if reminder.type == .amountThreshold, let threshold = reminder.amountThreshold {
            parts.append(String(localized: "over \(MoneyFormat.string(threshold, currencyCode: currencyCode))"))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Tag editor

enum OrgTagEditorTarget: Identifiable {
    case create
    case edit(Tag)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let tag): tag.id
        }
    }
}

private struct OrgTagEditorSheet: View {
    let target: OrgTagEditorTarget

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var color = OrgColorHex.color(from: nil)
    @State private var icon: String?
    @State private var description = ""
    @State private var isSaving = false
    @State private var alert: ErrorAlert?
    @State private var didLoad = false

    private var editing: Tag? {
        if case .edit(let tag) = target { return tag }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    ColorPicker("Colour", selection: $color, supportsOpacity: false)
                    OrgIconPickerLink(selection: $icon, tint: color)
                }
                Section("Description") {
                    TextField("Optional", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(editing == nil ? "New Tag" : "Edit Tag")
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
                            .disabled(trimmedName.isEmpty || trimmedName.count > 100 || description.count > 500)
                    }
                }
            }
            .onAppear(perform: populate)
            .errorAlert($alert)
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func populate() {
        guard !didLoad else { return }
        didLoad = true
        if let editing {
            name = editing.name
            color = OrgColorHex.color(from: editing.color)
            icon = editing.icon
            description = editing.description ?? ""
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = OrgTagRequest(
            name: trimmedName,
            color: OrgColorHex.string(from: color),
            icon: icon,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription
        )
        do {
            if let editing {
                _ = try await services.orgCoreSend(Endpoints.orgUpdateTag(id: editing.id, request))
            } else {
                _ = try await services.orgCoreSend(Endpoints.orgCreateTag(request))
            }
            await referenceData.refreshTags()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

// MARK: - Reminder editor

enum OrgTagReminderTarget: Identifiable {
    case create
    case edit(OrgTagReminder)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let reminder): reminder.id
        }
    }
}

private struct OrgTagReminderEditorSheet: View {
    let tagID: String
    let target: OrgTagReminderTarget
    let onSaved: () async -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var type: OrgTagReminderType = .amountThreshold
    @State private var frequency: OrgTagReminderFrequency?
    @State private var dayOfMonth = 1
    @State private var threshold: Decimal?
    @State private var isEnabled = true
    @State private var isSaving = false
    @State private var alert: ErrorAlert?
    @State private var didLoad = false

    private var editing: OrgTagReminder? {
        if case .edit(let reminder) = target { return reminder }
        return nil
    }

    private var baseCurrencyCode: String {
        referenceData.userCurrencies.first(where: \.isDefaultCurrency)?.currencyCode ?? "USD"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(OrgTagReminderType.allKnown, id: \.self) { type in
                            Text(OrgTagReminderText.typeTitle(type)).tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } footer: {
                    Text(type == .amountThreshold
                         ? "Notifies you when spending with this tag reaches the limit."
                         : "Notifies you when no transaction gets this tag during the period.")
                }
                if type == .amountThreshold {
                    Section("Limit") {
                        TextField(
                            "Amount",
                            value: $threshold,
                            format: .currency(code: baseCurrencyCode)
                        )
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                    }
                }
                Section {
                    Picker("Check", selection: $frequency) {
                        Text(OrgTagReminderText.frequencyTitle(nil)).tag(OrgTagReminderFrequency?.none)
                        ForEach(OrgTagReminderFrequency.allKnown, id: \.self) { frequency in
                            Text(OrgTagReminderText.frequencyTitle(frequency)).tag(Optional(frequency))
                        }
                    }
                    if frequency?.usesDayOfMonth == true {
                        Picker("Day of Month", selection: $dayOfMonth) {
                            ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                        }
                    }
                    Toggle("Enabled", isOn: $isEnabled)
                } footer: {
                    if frequency?.usesDayOfMonth == true, dayOfMonth > 28 {
                        Text("In shorter months the check runs on the last day.")
                    } else if frequency == nil {
                        Text("Checks as soon as a transaction is tagged.")
                    }
                }
            }
            .navigationTitle(editing == nil ? "New Reminder" : "Edit Reminder")
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
                            .disabled(!isValid)
                    }
                }
            }
            .onAppear(perform: populate)
            .errorAlert($alert)
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var isValid: Bool {
        guard type == .amountThreshold else { return true }
        guard let threshold else { return false }
        return threshold >= Decimal(string: "0.01")!
    }

    private func populate() {
        guard !didLoad else { return }
        didLoad = true
        guard let editing else { return }
        type = editing.type == .unknown ? .amountThreshold : editing.type
        frequency = editing.frequency == .unknown ? nil : editing.frequency
        dayOfMonth = editing.dayOfMonth ?? 1
        threshold = editing.amountThreshold
        isEnabled = editing.isEnabled
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let request = OrgTagReminderRequest(
            type: type,
            frequency: frequency,
            dayOfMonth: frequency?.usesDayOfMonth == true ? dayOfMonth : nil,
            amountThreshold: type == .amountThreshold ? threshold : nil,
            isEnabled: isEnabled
        )
        do {
            if let editing {
                _ = try await services.orgCoreSend(Endpoints.orgUpdateTagReminder(tagId: tagID, id: editing.id, request))
            } else {
                _ = try await services.orgCoreSend(Endpoints.orgCreateTagReminder(tagId: tagID, request))
            }
            await onSaved()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}
