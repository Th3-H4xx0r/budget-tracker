import MoneyMatterKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// CSV import, mirroring the web wizard: parse, map columns, map accounts/categories/tags,
/// review duplicates, then run the import job.
struct DataCSVImportFlow: View {
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var reference
    @Environment(SessionStore.self) private var session
    @State private var model = DataCSVImportModel()
    @State private var alert: ErrorAlert?

    private let stepTitles: [LocalizedStringKey] = ["Choose File", "Map Columns", "Map Values", "Review Duplicates", "Import"]

    var body: some View {
        Form {
            DataImportStepHeader(current: model.step.rawValue, titles: stepTitles)
            switch model.step {
            case .file: fileStep
            case .columns: columnsStep
            case .values: valuesStep
            case .duplicates: duplicatesStep
            case .execute:
                if model.isFinished {
                    DataImportResultSections(summary: model.progress?.summary, failure: model.failure)
                } else {
                    DataImportProgressSection(progress: model.progress)
                }
            }
        }
        .navigationTitle("CSV Import")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .disabled(model.isWorking)
        .overlay {
            if model.isWorking { ProgressView().controlSize(.large) }
        }
        .errorAlert($alert)
        .task {
            await reference.loadIfNeeded()
            if model.currencyCode.isEmpty { model.currencyCode = baseCurrency }
        }
    }

    private var baseCurrency: String { session.baseCurrency?.currencyCode ?? "USD" }

    // MARK: Steps

    @ViewBuilder
    private var fileStep: some View {
        DataImportFilePickerSection(
            title: model.fileName == nil ? "Choose CSV File" : "Change File",
            footer: "Choose a CSV exported from your bank or spreadsheet (up to 50,000 rows).",
            fileName: model.fileName,
            contentTypes: [.commaSeparatedText, .plainText, .text]
        ) { url in
            do {
                model.fileContent = try DataImportFileReader.readText(url)
                model.fileName = url.lastPathComponent
            } catch {
                alert = ErrorAlert(error)
            }
        }
        Section {
            Picker("Delimiter", selection: $model.delimiterChoice) {
                Text("Detect automatically").tag("")
                Text("Comma (,)").tag(",")
                Text("Semicolon (;)").tag(";")
                Text("Tab").tag("\t")
                Text("Pipe (|)").tag("|")
            }
        }
    }

    @ViewBuilder
    private var columnsStep: some View {
        if let parsed = model.parsed {
            Section {
                LabeledContent("Rows", value: parsed.totalRows, format: .number)
                columnPicker("Date", selection: $model.dateColumn, optional: false)
                Picker("Date format", selection: $model.dateOrder) {
                    Text("Day first (31/12)").tag(DataCSVDateFieldOrder.dayFirst)
                    Text("Month first (12/31)").tag(DataCSVDateFieldOrder.monthFirst)
                }
                columnPicker("Amount", selection: $model.amountColumn, optional: false)
                columnPicker("Description", selection: $model.descriptionColumn, optional: true)
                columnPicker("Payee", selection: $model.payeeColumn, optional: true)
                columnPicker("Tags", selection: $model.tagsColumn, optional: true)
            } header: {
                Text("Columns")
            } footer: {
                if let sample = model.sampleValue(for: model.dateColumn) {
                    Text("First date in the file: \(sample)")
                }
            }

            Section("Transaction Type") {
                Picker("Type from", selection: $model.typeFromColumn) {
                    Text("Amount sign (negative = expense)").tag(false)
                    Text("A column").tag(true)
                }
                if model.typeFromColumn {
                    columnPicker("Type column", selection: $model.typeColumn, optional: false)
                    ForEach(model.typeValues, id: \.self) { value in
                        Picker(value, selection: Binding(
                            get: { model.incomeValues.contains(value) },
                            set: { isIncome in
                                if isIncome { model.incomeValues.insert(value) } else { model.incomeValues.remove(value) }
                            }
                        )) {
                            Text("Expense").tag(false)
                            Text("Income").tag(true)
                        }
                    }
                }
            }

            Section("Account") {
                Picker("Account from", selection: $model.accountFromColumn) {
                    Text("One account").tag(false)
                    Text("A column").tag(true)
                }
                if model.accountFromColumn {
                    columnPicker("Account column", selection: $model.accountColumn, optional: false)
                } else {
                    Picker("Account", selection: $model.accountId) {
                        Text("Choose…").tag(String?.none)
                        ForEach(reference.accounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                }
            }

            Section("Currency") {
                Picker("Currency from", selection: $model.currencyFromColumn) {
                    Text("One currency").tag(false)
                    Text("A column").tag(true)
                }
                if model.currencyFromColumn {
                    columnPicker("Currency column", selection: $model.currencyColumn, optional: false)
                } else {
                    Picker("Currency", selection: $model.currencyCode) {
                        ForEach(currencyCodes, id: \.self) { Text($0).tag($0) }
                    }
                }
            }

            Section {
                Picker("Categories", selection: $model.categoryMode) {
                    Text("One category").tag(DataCSVImportModel.CategoryMode.existing)
                    Text("Map a column to my categories").tag(DataCSVImportModel.CategoryMode.mapColumn)
                    Text("Create categories from a column").tag(DataCSVImportModel.CategoryMode.createFromColumn)
                }
                if model.categoryMode == .existing {
                    Picker("Category", selection: $model.categoryId) {
                        Text("Choose…").tag(String?.none)
                        ForEach(reference.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                } else {
                    columnPicker("Category column", selection: $model.categoryColumn, optional: false)
                }
            } header: {
                Text("Category")
            }
        }
    }

    private var currencyCodes: [String] {
        var codes = reference.userCurrencies.map(\.currencyCode)
        if !codes.contains(baseCurrency) { codes.insert(baseCurrency, at: 0) }
        return codes
    }

    private func columnPicker(_ title: LocalizedStringKey, selection: Binding<String>, optional: Bool) -> some View {
        Picker(title, selection: selection) {
            Text(optional ? "None" : "Choose…").tag("")
            ForEach(model.parsed?.headers ?? [], id: \.self) { header in
                Text(header).tag(header)
            }
        }
    }

    @ViewBuilder
    private var valuesStep: some View {
        if let values = model.uniqueValues {
            if let warning = values.currencyMismatchWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                }
            }
            if model.accountFromColumn, !values.sourceAccounts.isEmpty {
                Section("Accounts") {
                    ForEach(values.sourceAccounts, id: \.name) { account in
                        DataAccountMappingRow(
                            title: account.name,
                            subtitle: account.currency,
                            choice: Binding(
                                get: { model.accountChoices[account.name] ?? .createNew },
                                set: { model.accountChoices[account.name] = $0 }
                            ),
                            accounts: reference.accounts
                        )
                    }
                }
            }
            if model.categoryMode == .mapColumn, !values.sourceCategories.isEmpty {
                Section {
                    ForEach(values.sourceCategories, id: \.self) { name in
                        DataCategoryMappingRow(
                            title: name,
                            subtitle: nil,
                            categoryId: Binding(
                                get: { model.categoryChoices[name] },
                                set: { model.categoryChoices[name] = $0 }
                            ),
                            categories: reference.categories
                        )
                    }
                } header: {
                    HStack {
                        Text("Categories")
                        Spacer()
                        Button("Suggest with AI", systemImage: "sparkles") {
                            run { try await model.suggestCategories(client: $0) }
                        }
                        .font(.caption)
                        .textCase(nil)
                    }
                } footer: {
                    Text("Unmapped categories are created.")
                }
            }
            if !values.sourceTags.isEmpty {
                Section("Tags") {
                    ForEach(values.sourceTags, id: \.self) { tag in
                        Toggle(tag, isOn: Binding(
                            get: { !model.skippedTags.contains(tag) },
                            set: { isOn in
                                if isOn { model.skippedTags.remove(tag) } else { model.skippedTags.insert(tag) }
                            }
                        ))
                    }
                }
            }
            if !model.accountFromColumn && model.categoryMode != .mapColumn && values.sourceTags.isEmpty {
                Section {
                    Label("Nothing to map. Continue to check for duplicates.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var duplicatesStep: some View {
        if let result = model.duplicateResult {
            Section {
                if let valid = result.validRowCount {
                    LabeledContent("Rows to import", value: valid, format: .number)
                }
                if result.invalidRowCount > 0 {
                    LabeledContent("Rows with errors (skipped)", value: result.invalidRowCount, format: .number)
                }
                Toggle("Recalculate linked account balances", isOn: $model.recalculateBalance)
            }
            DataDuplicateReviewSection(duplicates: result.duplicates, included: $model.includedDuplicates, currencyCode: nil)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            switch model.step {
            case .file:
                Button("Next") { run { try await model.parse(client: $0) } }
                    .disabled(model.fileContent == nil)
            case .columns:
                Button("Next") { run { try await model.extractValues(client: $0) } }
                    .disabled(!model.isColumnMappingComplete)
            case .values:
                Button("Next") { run { try await model.detectDuplicates(client: $0) } }
            case .duplicates:
                Button("Import") { run { try await model.execute(client: $0) } }
            case .execute:
                EmptyView()
            }
        }
        if [.columns, .values, .duplicates].contains(model.step) {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { model.goBack() }
            }
        }
    }

    private func run(_ action: @escaping (APIClient) async throws -> Void) {
        guard let client = services.client else { return }
        Task {
            do {
                try await action(client)
                if model.isFinished { await reference.refresh() }
            } catch {
                alert = ErrorAlert(error)
            }
        }
    }
}

@MainActor
@Observable
final class DataCSVImportModel {
    enum Step: Int { case file, columns, values, duplicates, execute }
    enum CategoryMode: Hashable { case existing, mapColumn, createFromColumn }

    var step: Step = .file
    var fileName: String?
    var fileContent: String?
    var delimiterChoice = ""
    private(set) var parsed: DataCSVParseResult?

    var dateColumn = ""
    var dateOrder: DataCSVDateFieldOrder = .dayFirst
    var amountColumn = ""
    var descriptionColumn = ""
    var payeeColumn = ""
    var tagsColumn = ""
    var typeFromColumn = false
    var typeColumn = "" { didSet { incomeValues = [] } }
    var incomeValues: Set<String> = []
    var accountFromColumn = false
    var accountColumn = ""
    var accountId: String?
    var currencyFromColumn = false
    var currencyColumn = ""
    var currencyCode = ""
    var categoryMode: CategoryMode = .existing
    var categoryColumn = ""
    var categoryId: String?

    private(set) var uniqueValues: DataCSVUniqueValues?
    var accountChoices: [String: DataAccountChoice] = [:]
    var categoryChoices: [String: String] = [:]
    var skippedTags: Set<String> = []

    private(set) var duplicateResult: DataImportDuplicatesResponse?
    var includedDuplicates: Set<Int> = []
    var recalculateBalance = false

    private(set) var progress: DataImportProgress?
    private(set) var failure: String?
    private(set) var isWorking = false

    var isFinished: Bool { step == .execute && (progress?.status.isFinished ?? false || failure != nil) }

    var typeValues: [String] {
        guard !typeColumn.isEmpty, let rows = parsed?.preview else { return [] }
        var seen: [String] = []
        for row in rows {
            if let value = row[typeColumn]?.trimmingCharacters(in: .whitespaces), !value.isEmpty, !seen.contains(value) {
                seen.append(value)
            }
        }
        return seen
    }

    var isColumnMappingComplete: Bool {
        guard !dateColumn.isEmpty, !amountColumn.isEmpty else { return false }
        if typeFromColumn && typeColumn.isEmpty { return false }
        if accountFromColumn ? accountColumn.isEmpty : accountId == nil { return false }
        if currencyFromColumn ? currencyColumn.isEmpty : currencyCode.isEmpty { return false }
        switch categoryMode {
        case .existing: return categoryId != nil
        case .mapColumn, .createFromColumn: return !categoryColumn.isEmpty
        }
    }

    func sampleValue(for column: String) -> String? {
        guard !column.isEmpty else { return nil }
        return parsed?.preview.first?[column]
    }

    func goBack() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    func parse(client: APIClient) async throws {
        guard let fileContent else { return }
        isWorking = true
        defer { isWorking = false }
        let result = try await client.send(Endpoints.dataCSVParse(fileContent: fileContent, delimiter: delimiterChoice.isEmpty ? nil : delimiterChoice))
        parsed = result
        autoMatch(headers: result.headers)
        step = .columns
    }

    /// Guesses columns from header names, like the web's auto-match.
    private func autoMatch(headers: [String]) {
        func find(_ keywords: [String]) -> String {
            headers.first { header in
                let lower = header.lowercased()
                return keywords.contains { lower.contains($0) }
            } ?? ""
        }
        dateColumn = find(["date", "time", "дата"])
        amountColumn = find(["amount", "sum", "value", "сума"])
        descriptionColumn = find(["description", "note", "memo", "details", "опис"])
        payeeColumn = find(["payee", "merchant", "counterparty"])
        tagsColumn = find(["tag"])
        let category = find(["category", "категор"])
        if !category.isEmpty {
            categoryMode = .mapColumn
            categoryColumn = category
        }
        let currency = find(["currency", "валют"])
        if !currency.isEmpty {
            currencyFromColumn = true
            currencyColumn = currency
        }
        let account = find(["account", "рахун"])
        if !account.isEmpty {
            accountFromColumn = true
            accountColumn = account
        }
    }

    private func columnMapping() -> DataCSVColumnMapping {
        let category: DataCSVColumnMapping.CategoryOption = switch categoryMode {
        case .existing: .existing(categoryId: categoryId ?? "")
        case .mapColumn: .mapColumn(categoryColumn)
        case .createFromColumn: .createNew(column: categoryColumn)
        }
        let type: DataCSVColumnMapping.TransactionTypeOption = typeFromColumn
            ? .column(typeColumn, incomeValues: typeValues.filter { incomeValues.contains($0) }, expenseValues: typeValues.filter { !incomeValues.contains($0) })
            : .amountSign
        return DataCSVColumnMapping(
            date: dateColumn,
            dateFieldOrder: dateOrder,
            amount: amountColumn,
            description: descriptionColumn.isEmpty ? nil : descriptionColumn,
            payee: payeeColumn.isEmpty ? nil : payeeColumn,
            tagsColumn: tagsColumn.isEmpty ? nil : tagsColumn,
            category: category,
            currency: currencyFromColumn ? .column(currencyColumn) : .existing(currencyCode: currencyCode),
            transactionType: type,
            account: accountFromColumn ? .column(accountColumn) : .existing(accountId: accountId ?? "")
        )
    }

    private func request(skip: [Int]? = nil) -> DataCSVImportRequest {
        var accountMapping: [String: DataImportAccountMapping] = [:]
        if accountFromColumn {
            for account in uniqueValues?.sourceAccounts ?? [] {
                switch accountChoices[account.name] ?? .createNew {
                case .createNew: accountMapping[account.name] = .createNew()
                case .link(let id): accountMapping[account.name] = .linkExisting(accountId: id)
                case .skip: accountMapping[account.name] = .skip
                }
            }
        }
        var categoryMapping: [String: DataImportCategoryMapping] = [:]
        if categoryMode == .mapColumn {
            for name in uniqueValues?.sourceCategories ?? [] {
                categoryMapping[name] = categoryChoices[name].map { .linkExisting(categoryId: $0) } ?? .createNew
            }
        }
        var tagMapping: [String: DataCSVTagMapping]?
        if let tags = uniqueValues?.sourceTags, !tags.isEmpty {
            tagMapping = Dictionary(uniqueKeysWithValues: tags.map { ($0, skippedTags.contains($0) ? .skip : .createNew) })
        }
        return DataCSVImportRequest(
            fileContent: fileContent ?? "",
            delimiter: parsed?.detectedDelimiter ?? ",",
            columnMapping: columnMapping(),
            accountMapping: uniqueValues == nil ? nil : accountMapping,
            categoryMapping: uniqueValues == nil ? nil : categoryMapping,
            tagMapping: tagMapping,
            skipDuplicateIndices: skip,
            recalculateBalance: skip == nil ? nil : recalculateBalance,
            timezone: TimeZone.current.identifier
        )
    }

    /// Fills unmapped categories with AI matches; categories AI couldn't match stay "create new".
    func suggestCategories(client: APIClient) async throws {
        let names = (uniqueValues?.sourceCategories ?? []).filter { categoryChoices[$0] == nil }
        guard !names.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        let result = try await client.send(Endpoints.dataAIMapCategories(names))
        for (name, id) in result.matched { categoryChoices[name] = id }
    }

    func extractValues(client: APIClient) async throws {
        isWorking = true
        defer { isWorking = false }
        uniqueValues = nil
        var body = request()
        body.timezone = nil
        uniqueValues = try await client.send(Endpoints.dataCSVUniqueValues(body))
        step = .values
    }

    func detectDuplicates(client: APIClient) async throws {
        isWorking = true
        defer { isWorking = false }
        duplicateResult = try await client.send(Endpoints.dataCSVDetectDuplicates(request()))
        includedDuplicates = []
        step = .duplicates
    }

    func execute(client: APIClient) async throws {
        let skip = (duplicateResult?.duplicates ?? []).map(\.rowIndex).filter { !includedDuplicates.contains($0) }
        isWorking = true
        let job: DataImportJobRef
        do {
            job = try await client.send(Endpoints.dataCSVExecute(request(skip: skip)))
        } catch {
            isWorking = false
            throw error
        }
        isWorking = false
        step = .execute
        do {
            let final = try await DataImportJobPoller.poll {
                try await client.send(Endpoints.dataCSVStatus(jobId: job.jobId))
            } onUpdate: { [weak self] in
                self?.progress = $0
            }
            progress = final
            if final.status == .failed { failure = final.error ?? String(localized: "The import failed.") }
        } catch {
            failure = ErrorMessage.inline(for: error)
        }
    }
}
