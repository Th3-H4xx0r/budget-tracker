import MoneyMatterKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// YNAB, OFX/QFX, Microsoft Money, and BudgetBakers Wallet imports, mirroring their web
/// wizards: upload and parse, map accounts (and categories), review duplicates, import.
struct DataProviderImportFlow: View {
    let kind: DataProviderKind

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var reference
    @Environment(SessionStore.self) private var session
    @State private var model = DataProviderImportModel()
    @State private var alert: ErrorAlert?
    /// Actions started by `run`, cancelled when the flow is dismissed so job polling stops.
    @State private var runTasks: [Task<Void, Never>] = []

    var body: some View {
        Form {
            DataImportStepHeader(current: stepIndex, titles: stepTitles)
            switch model.step {
            case .file: fileStep
            case .mapping: mappingStep
            case .duplicates: duplicatesStep
            case .execute:
                if model.isFinished {
                    DataImportResultSections(summary: model.progress?.summary, failure: model.failure)
                } else {
                    DataImportProgressSection(progress: model.progress)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .disabled(model.isWorking)
        .overlay {
            if model.isWorking {
                ProgressView().controlSize(.large)
            }
        }
        .errorAlert($alert)
        .task { await reference.loadIfNeeded() }
        .task(id: model.uploadId) { await model.keepLeaseAlive(kind: kind, client: services.client) }
        .onDisappear {
            runTasks.forEach { $0.cancel() }
            runTasks.removeAll()
        }
    }

    private var title: LocalizedStringKey {
        switch kind {
        case .ynab: "YNAB Import"
        case .ofx: "OFX / QFX Import"
        case .msMoney: "Microsoft Money Import"
        case .budgetBakersWallet: "Wallet Import"
        }
    }

    /// YNAB has no duplicate step, so its import step comes one earlier.
    private var stepIndex: Int {
        if model.step == .execute, !kind.hasDuplicateDetection { return model.step.rawValue - 1 }
        return model.step.rawValue
    }

    private var stepTitles: [LocalizedStringKey] {
        var titles: [LocalizedStringKey] = ["Choose File", kind.hasCategoryMapping ? "Map Accounts & Categories" : "Map Accounts"]
        if kind.hasDuplicateDetection { titles.append("Review Duplicates") }
        titles.append("Import")
        return titles
    }

    private var contentTypes: [UTType] {
        switch kind {
        case .ofx: [UTType(filenameExtension: "ofx"), UTType(filenameExtension: "qfx"), .data].compactMap(\.self)
        case .msMoney: [UTType(filenameExtension: "mny"), .data].compactMap(\.self)
        case .ynab, .budgetBakersWallet: [.commaSeparatedText, .plainText, .text]
        }
    }

    private var baseCurrency: String { session.baseCurrency?.currencyCode ?? "USD" }

    // MARK: Steps

    @ViewBuilder
    private var fileStep: some View {
        DataImportFilePickerSection(
            title: model.fileName == nil ? "Choose File" : "Change File",
            footer: fileFooter,
            fileName: model.fileName,
            contentTypes: contentTypes
        ) { url in
            model.pick(url: url, kind: kind) { alert = ErrorAlert($0) }
        }
        if kind == .msMoney {
            Section {
                SecureField("File password (optional)", text: $model.password)
                    .textContentType(.password)
            } footer: {
                Text("Only needed if the Money file is password-protected.")
            }
        }
    }

    private var fileFooter: LocalizedStringKey {
        switch kind {
        case .ynab: "Export your YNAB plan as CSV and choose the Register file."
        case .ofx: "Choose an OFX or QFX file downloaded from your bank (up to 10 MB)."
        case .msMoney: "Choose a Microsoft Money .mny file (up to 50 MB)."
        case .budgetBakersWallet: "Export records from BudgetBakers Wallet as CSV and choose that file."
        }
    }

    @ViewBuilder
    private var mappingStep: some View {
        if let result = model.parsed {
            Section("File Contents") {
                LabeledContent("Transactions", value: result.transactionCount, format: .number)
                if result.transferCount > 0 {
                    LabeledContent("Transfers", value: result.transferCount, format: .number)
                }
                if let range = result.dateRange {
                    LabeledContent("Dates") {
                        Text("\(DataDuplicateReviewSection.day(range.from)) – \(DataDuplicateReviewSection.day(range.to))")
                    }
                }
            }
            if !result.warnings.isEmpty {
                Section("Warnings") {
                    ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, warning in
                        Label(warning.message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                    }
                }
            }
            Section {
                ForEach(result.accounts) { account in
                    if kind == .ynab {
                        ynabAccountRow(account)
                    } else if account.isImportable {
                        DataAccountMappingRow(
                            title: account.displayName,
                            subtitle: accountSubtitle(account),
                            choice: Binding(
                                get: { model.accountChoices[account.key] ?? .createNew },
                                set: { model.accountChoices[account.key] = $0 }
                            ),
                            accounts: reference.accounts
                        )
                    } else {
                        LabeledContent(account.displayName) {
                            Text("Not supported")
                        }
                    }
                }
            } header: {
                Text("Accounts")
            } footer: {
                Text("New accounts use the currency from the file. Linked accounts receive the imported transactions.")
            }
            if kind.hasCategoryMapping, !result.categories.isEmpty {
                Section {
                    ForEach(result.categories) { category in
                        DataCategoryMappingRow(
                            title: category.name,
                            subtitle: String(localized: "\(category.transactionCount) transactions"),
                            categoryId: Binding(
                                get: { model.categoryChoices[category.name] },
                                set: { model.categoryChoices[category.name] = $0 }
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
            Section {
                if kind != .ynab {
                    Toggle("Recalculate linked account balances", isOn: $model.recalculateBalance)
                }
                if kind == .msMoney {
                    Toggle("Include voided transactions", isOn: $model.includeVoided)
                }
            }
        }
    }

    private func accountSubtitle(_ account: DataSourceAccount) -> String {
        let count = String(localized: "\(account.transactionCount) transactions")
        guard let currency = account.currency else { return count }
        return "\(currency) · \(count)"
    }

    private func ynabAccountRow(_ account: DataSourceAccount) -> some View {
        let binding = Binding<String?>(
            get: { model.ynabSkipped.contains(account.key) ? nil : (model.ynabCurrencies[account.key] ?? account.currency ?? baseCurrency) },
            set: { value in
                if let value {
                    model.ynabSkipped.remove(account.key)
                    model.ynabCurrencies[account.key] = value
                } else {
                    model.ynabSkipped.insert(account.key)
                }
            }
        )
        return Picker(selection: binding) {
            Text("Skip").tag(String?.none)
            ForEach(currencyCodes(including: account.currency), id: \.self) { code in
                Text(code).tag(Optional(code))
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                Text("\(account.transactionCount) transactions").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func currencyCodes(including extra: String?) -> [String] {
        var codes = reference.userCurrencies.map(\.currencyCode)
        if !codes.contains(baseCurrency) { codes.insert(baseCurrency, at: 0) }
        if let extra, !codes.contains(extra) { codes.append(extra) }
        return codes
    }

    @ViewBuilder
    private var duplicatesStep: some View {
        DataDuplicateReviewSection(duplicates: model.duplicates, included: $model.includedDuplicates, currencyCode: nil)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            switch model.step {
            case .file:
                Button("Next") { run { try await model.upload(kind: kind, client: $0) } }
                    .disabled(model.fileName == nil)
            case .mapping:
                Button(kind.hasDuplicateDetection ? "Next" : "Import") {
                    run { client in
                        if kind.hasDuplicateDetection {
                            try await model.detectDuplicates(kind: kind, client: client, baseCurrency: baseCurrency)
                        } else {
                            try await model.execute(kind: kind, client: client, baseCurrency: baseCurrency)
                        }
                    }
                }
            case .duplicates:
                Button("Import") { run { try await model.execute(kind: kind, client: $0, baseCurrency: baseCurrency) } }
            case .execute:
                EmptyView()
            }
        }
        if model.step == .mapping || model.step == .duplicates {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { model.goBack(kind: kind) }
            }
        }
    }

    private func run(_ action: @escaping (APIClient) async throws -> Void) {
        guard let client = services.client else { return }
        runTasks.append(Task {
            do {
                try await action(client)
                if model.isFinished { await reference.refresh() }
            } catch {
                alert = ErrorAlert(error)
            }
        })
    }
}

@MainActor
@Observable
final class DataProviderImportModel {
    enum Step: Int { case file, mapping, duplicates, execute }

    var step: Step = .file
    var fileName: String?
    var password = ""
    private(set) var fileText: String?
    private(set) var fileData: Data?
    private(set) var uploadId: String?
    private(set) var parsed: DataProviderParseResult?
    var accountChoices: [String: DataAccountChoice] = [:]
    var categoryChoices: [String: String] = [:]
    var ynabCurrencies: [String: String] = [:]
    var ynabSkipped: Set<String> = []
    var recalculateBalance = false
    var includeVoided = false
    private(set) var duplicates: [DataImportDuplicate] = []
    var includedDuplicates: Set<Int> = []
    private(set) var progress: DataImportProgress?
    private(set) var failure: String?
    private(set) var isWorking = false

    var isFinished: Bool { step == .execute && (progress?.status.isFinished ?? false || failure != nil) }

    func pick(url: URL, kind: DataProviderKind, onError: (any Error) -> Void) {
        do {
            if kind.uploadsBinary {
                fileData = try DataImportFileReader.read(url)
                fileText = nil
            } else {
                fileText = try DataImportFileReader.readText(url)
                fileData = nil
            }
            fileName = url.lastPathComponent
            uploadId = nil
            parsed = nil
        } catch {
            onError(error)
        }
    }

    func upload(kind: DataProviderKind, client: APIClient) async throws {
        isWorking = true
        defer { isWorking = false }
        let response: DataProviderParseResponse
        if kind.uploadsBinary, let fileData {
            response = try await client.dataUploadFile(kind, fileData: fileData, password: password)
        } else if let fileText {
            response = try await client.send(Endpoints.dataProviderParse(kind, fileContent: fileText))
        } else {
            return
        }
        uploadId = response.uploadId
        parsed = response.result
        accountChoices = [:]
        categoryChoices = [:]
        step = .mapping
    }

    /// Fills unmapped categories with AI matches; categories AI couldn't match stay "create new".
    func suggestCategories(client: APIClient) async throws {
        let names = (parsed?.categories ?? []).map(\.name).filter { categoryChoices[$0] == nil }
        guard !names.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        let result = try await client.send(Endpoints.dataAIMapCategories(names))
        for (name, id) in result.matched { categoryChoices[name] = id }
    }

    func goBack(kind: DataProviderKind) {
        switch step {
        case .mapping: step = .file
        case .duplicates: step = .mapping
        default: break
        }
    }

    private func request(kind: DataProviderKind, baseCurrency: String, skip: [Int]? = nil) -> DataProviderImportRequest {
        var accountMapping: [String: DataImportAccountMapping] = [:]
        for account in parsed?.accounts ?? [] where account.isImportable {
            switch accountChoices[account.key] ?? .createNew {
            case .createNew:
                accountMapping[account.key] = .createNew(
                    name: kind == .ofx ? account.displayName : nil,
                    currencyCode: account.currency ?? baseCurrency,
                    currentBalance: nil
                )
            case .link(let id):
                accountMapping[account.key] = .linkExisting(accountId: id)
            case .skip:
                accountMapping[account.key] = .skip
            }
        }
        var categoryMapping: [String: DataImportCategoryMapping]?
        if kind.hasCategoryMapping {
            var mapping: [String: DataImportCategoryMapping] = [:]
            for category in parsed?.categories ?? [] {
                mapping[category.name] = categoryChoices[category.name].map { .linkExisting(categoryId: $0) } ?? .createNew
            }
            categoryMapping = mapping
        }
        return DataProviderImportRequest(
            fileContent: kind.uploadsBinary ? nil : fileText,
            uploadId: kind.uploadsBinary ? uploadId : nil,
            accountMapping: accountMapping,
            categoryMapping: categoryMapping,
            skipDuplicateIndices: skip,
            recalculateBalance: skip == nil ? nil : recalculateBalance,
            includeVoidedTransactions: kind == .msMoney && skip != nil ? includeVoided : nil
        )
    }

    func detectDuplicates(kind: DataProviderKind, client: APIClient, baseCurrency: String) async throws {
        isWorking = true
        defer { isWorking = false }
        let response = try await client.send(
            Endpoints.dataProviderDetectDuplicates(kind, request: request(kind: kind, baseCurrency: baseCurrency))
        )
        duplicates = response.duplicates
        includedDuplicates = []
        step = .duplicates
    }

    func execute(kind: DataProviderKind, client: APIClient, baseCurrency: String) async throws {
        let job: DataImportJobRef
        isWorking = true
        if kind == .ynab {
            var mapping: [String: DataYnabAccountMapping] = [:]
            for account in parsed?.accounts ?? [] {
                let currency = ynabCurrencies[account.key] ?? account.currency ?? baseCurrency
                mapping[account.key] = DataYnabAccountMapping(currencyCode: currency, skip: ynabSkipped.contains(account.key) ? true : nil)
            }
            do {
                job = try await client.send(Endpoints.dataYnabExecute(DataYnabExecuteRequest(fileContent: fileText ?? "", accountMapping: mapping)))
            } catch {
                isWorking = false
                throw error
            }
        } else {
            let skip = duplicates.map(\.rowIndex).filter { !includedDuplicates.contains($0) }
            do {
                job = try await client.send(Endpoints.dataProviderExecute(kind, request: request(kind: kind, baseCurrency: baseCurrency, skip: skip)))
            } catch {
                isWorking = false
                throw error
            }
        }
        isWorking = false
        step = .execute
        do {
            let final = try await DataImportJobPoller.poll {
                try await client.send(Endpoints.dataProviderStatus(kind, jobId: job.jobId))
            } onUpdate: { [weak self] in
                self?.progress = $0
            }
            progress = final
            if final.status == .failed { failure = final.error ?? String(localized: "The import failed.") }
        } catch {
            failure = ErrorMessage.inline(for: error)
        }
    }

    /// Refreshes the server-side upload every 30 seconds until the flow is left.
    func keepLeaseAlive(kind: DataProviderKind, client: APIClient?) async {
        guard kind.uploadsBinary, let client, let uploadId else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, step != .execute else { return }
            _ = try? await client.send(Endpoints.dataRefreshUploadLease(kind, uploadId: uploadId))
        }
    }
}
