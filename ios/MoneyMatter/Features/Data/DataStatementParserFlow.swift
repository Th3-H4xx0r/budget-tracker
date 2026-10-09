import MoneyMatterKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The AI statement parser ("text source"): a PDF, CSV, or text statement (or pasted text)
/// is read by AI into transactions for one account.
struct DataStatementParserFlow: View {
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var reference
    @State private var model = DataStatementParserModel()
    @State private var alert: ErrorAlert?
    /// Actions started by `run`, cancelled when the flow is dismissed so job polling stops.
    @State private var runTasks: [Task<Void, Never>] = []

    private let stepTitles: [LocalizedStringKey] = ["Upload & Extract", "Review Transactions", "Review Duplicates", "Import"]

    var body: some View {
        Form {
            DataImportStepHeader(current: model.step.rawValue, titles: stepTitles)
            switch model.step {
            case .upload: uploadStep
            case .review: reviewStep
            case .duplicates:
                DataDuplicateReviewSection(
                    duplicates: model.duplicates,
                    included: $model.includedDuplicates,
                    currencyCode: reference.account(id: model.accountId)?.currencyCode
                )
            case .execute:
                if model.isFinished {
                    DataImportResultSections(summary: model.progress?.summary, failure: model.failure)
                } else {
                    DataImportProgressSection(progress: model.progress)
                }
            }
        }
        .navigationTitle("AI Statement Parser")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .disabled(model.isWorking)
        .overlay {
            if model.isWorking {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    if model.step == .upload, model.estimate != nil {
                        Text("Reading your statement. Large files can take a few minutes.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
                .background(.regularMaterial, in: .rect(cornerRadius: 16))
            }
        }
        .errorAlert($alert)
        .task { await reference.loadIfNeeded() }
        .onDisappear {
            runTasks.forEach { $0.cancel() }
            runTasks.removeAll()
        }
    }

    // MARK: Upload

    @ViewBuilder
    private var uploadStep: some View {
        Section {
            Picker("Source", selection: $model.usesPastedText) {
                Text("File").tag(false)
                Text("Paste Text").tag(true)
            }
            .pickerStyle(.segmented)
        }
        if model.usesPastedText {
            Section {
                TextField("Paste statement text", text: $model.pastedText, axis: .vertical)
                    .lineLimit(6...14)
                    .font(.callout.monospaced())
            } footer: {
                Text("Paste the transaction lines from a statement or bank export.")
            }
        } else {
            DataImportFilePickerSection(
                title: model.fileName == nil ? "Choose Statement" : "Change File",
                footer: "PDF, CSV, or TXT, up to 10 MB.",
                fileName: model.fileName,
                contentTypes: [.pdf, .commaSeparatedText, .plainText]
            ) { url in
                model.pick(url: url) { alert = ErrorAlert($0) }
            }
        }
        if model.needsPassword {
            Section {
                SecureField("PDF password", text: $model.password)
            } footer: {
                Text("This PDF is password-protected.")
            }
        }
        if let estimate = model.estimate {
            estimateSections(estimate)
        }
    }

    @ViewBuilder
    private func estimateSections(_ estimate: DataStatementCostEstimate) -> some View {
        if estimate.success {
            Section("Estimate") {
                if let model = estimate.modelName {
                    LabeledContent("Model", value: model)
                }
                LabeledContent("Estimated Cost") {
                    if let cost = estimate.estimatedCostUsd {
                        Text(cost, format: .currency(code: "USD").precision(.fractionLength(2...4)))
                            .monospacedDigit()
                    } else {
                        Text("Not available")
                    }
                }
                LabeledContent("Estimated Tokens") {
                    Text("\(Self.thousands(estimate.estimatedInputTokens))K input, ~\(Self.thousands(estimate.estimatedOutputTokens))K output")
                        .monospacedDigit()
                }
                if let pages = estimate.textExtraction?.pageCount, pages > 0 {
                    LabeledContent("Pages", value: pages, format: .number)
                }
            }
            let tokens = estimate.estimatedInputTokens ?? 0
            if tokens >= 100_000 {
                warning("Extremely large file", "Processing may take 5+ minutes. Consider splitting the file into smaller parts for faster processing.", destructive: true)
            } else if tokens >= 60_000 {
                warning("Very large file detected", "Processing may take several minutes due to the file size.", destructive: true)
            } else if tokens >= 30_000 {
                warning("Large file detected", "Processing may take 1-2 minutes. Please be patient.", destructive: false)
            }
            if estimate.usingUserKey == false {
                warning("Free AI access", "You're using free AI access which has daily rate limits. For the fast and uninterrupted service, add your own API key in Settings › AI.", destructive: false)
            }
        } else {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(estimate.errorMessage ?? estimate.textExtraction?.error ?? String(localized: "Couldn't read this file."))
                        if let suggestion = estimate.suggestion {
                            Text(suggestion).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
        }
    }

    private func warning(_ title: LocalizedStringKey, _ message: LocalizedStringKey, destructive: Bool) -> some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(message).font(.footnote)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(destructive ? .red : .orange)
            }
        }
    }

    private static func thousands(_ value: Int?) -> String {
        let value = Double(value ?? 0) / 1000
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    // MARK: Review

    @ViewBuilder
    private var reviewStep: some View {
        if let extraction = model.extraction {
            Section {
                if let bank = extraction.metadata?.bankName {
                    LabeledContent("Bank", value: bank)
                }
                if let last4 = extraction.metadata?.accountNumberLast4 {
                    LabeledContent("Account", value: "•••• \(last4)")
                }
                if let period = extraction.metadata?.statementPeriod {
                    LabeledContent("Period") {
                        Text("\(DataDuplicateReviewSection.day(period.from)) – \(DataDuplicateReviewSection.day(period.to))")
                    }
                }
                if let dropped = extraction.droppedRowCount, dropped > 0 {
                    Label("\(dropped) rows couldn't be read and were dropped.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                }
            } header: {
                Text("Statement")
            }
            Section {
                Picker("Import into", selection: $model.accountId) {
                    Text("Choose…").tag(String?.none)
                    ForEach(reference.accounts) { account in
                        Text("\(account.name) (\(account.currencyCode))").tag(Optional(account.id))
                    }
                }
            } footer: {
                if let currency = extraction.metadata?.currencyCode {
                    Text("Statement currency: \(currency)")
                }
            }
            Section {
                ForEach(Array(extraction.transactions.enumerated()), id: \.offset) { index, transaction in
                    Toggle(isOn: Binding(
                        get: { !model.excluded.contains(index) },
                        set: { isOn in
                            if isOn { model.excluded.remove(index) } else { model.excluded.insert(index) }
                        }
                    )) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(transaction.merchant ?? transaction.description).lineLimit(1)
                                Text(DataDuplicateReviewSection.day(transaction.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(transaction.isIncome ? "+" : "−")\(transaction.amount.formatted(.number.precision(.fractionLength(2))))")
                                .monospacedDigit()
                                .foregroundStyle(transaction.isIncome ? .green : .primary)
                        }
                    }
                }
            } header: {
                Text("\(extraction.transactions.count - model.excluded.count) of \(extraction.transactions.count) Selected")
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            switch model.step {
            case .upload:
                if model.estimate?.success == true {
                    Button("Extract") { run { try await model.extract(client: $0) } }
                } else {
                    Button("Estimate") { run { try await model.estimateCost(client: $0) } }
                        .disabled(!model.hasInput)
                }
            case .review:
                Button("Next") { run { try await model.detectDuplicates(client: $0) } }
                    .disabled(model.accountId == nil || model.selectedCount == 0)
            case .duplicates:
                Button("Import") { run { try await model.execute(client: $0) } }
            case .execute:
                EmptyView()
            }
        }
        if model.step == .review || model.step == .duplicates {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { model.goBack() }
            }
        }
    }

    private func run(_ action: @escaping (APIClient) async throws -> Void) {
        guard let client = services.client else { return }
        runTasks.append(Task {
            do {
                try await action(client)
                if model.isFinished { await reference.refreshAccounts() }
            } catch {
                alert = ErrorAlert(error)
            }
        })
    }
}

@MainActor
@Observable
final class DataStatementParserModel {
    enum Step: Int { case upload, review, duplicates, execute }

    var step: Step = .upload
    var usesPastedText = false { didSet { estimate = nil } }
    var pastedText = "" { didSet { if oldValue != pastedText { estimate = nil } } }
    var password = ""
    private(set) var fileName: String?
    private(set) var fileData: Data?
    private(set) var estimate: DataStatementCostEstimate?
    private(set) var extraction: DataStatementExtraction?
    var accountId: String?
    var excluded: Set<Int> = []
    private(set) var duplicates: [DataImportDuplicate] = []
    var includedDuplicates: Set<Int> = []
    private(set) var progress: DataImportProgress?
    private(set) var failure: String?
    private(set) var isWorking = false

    var isFinished: Bool { step == .execute && (progress?.status.isFinished ?? false || failure != nil) }

    var hasInput: Bool { usesPastedText ? !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : fileData != nil }

    var needsPassword: Bool {
        let code = estimate?.textExtraction?.errorCode
        return code == "PASSWORD_REQUIRED" || code == "PASSWORD_INVALID" || !password.isEmpty
    }

    var selectedCount: Int { (extraction?.transactions.count ?? 0) - excluded.count }

    func pick(url: URL, onError: (any Error) -> Void) {
        do {
            fileData = try DataImportFileReader.read(url)
            fileName = url.lastPathComponent
            estimate = nil
            password = ""
        } catch {
            onError(error)
        }
    }

    func goBack() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    private var fileRequest: DataStatementFileRequest? {
        let data = usesPastedText ? Data(pastedText.utf8) : fileData
        guard let data else { return nil }
        return DataStatementFileRequest(fileBase64: data.base64EncodedString(), password: password.isEmpty ? nil : password)
    }

    func estimateCost(client: APIClient) async throws {
        guard let fileRequest else { return }
        isWorking = true
        defer { isWorking = false }
        estimate = try await client.send(Endpoints.dataStatementEstimateCost(fileRequest))
    }

    func extract(client: APIClient) async throws {
        guard let fileRequest else { return }
        isWorking = true
        defer { isWorking = false }
        extraction = try await client.send(Endpoints.dataStatementExtract(fileRequest))
        excluded = []
        step = .review
    }

    func detectDuplicates(client: APIClient) async throws {
        guard let accountId, let extraction else { return }
        isWorking = true
        defer { isWorking = false }
        let response = try await client.send(Endpoints.dataStatementDetectDuplicates(
            DataStatementImportRequest(accountId: accountId, transactions: extraction.transactions)
        ))
        duplicates = response.duplicates.filter { !excluded.contains($0.rowIndex) }
        includedDuplicates = []
        step = .duplicates
    }

    func execute(client: APIClient) async throws {
        guard let accountId, let extraction else { return }
        let skippedDuplicates = duplicates.map(\.rowIndex).filter { !includedDuplicates.contains($0) }
        let skip = Array(excluded.union(skippedDuplicates)).sorted()
        isWorking = true
        let job: DataImportJobRef
        do {
            job = try await client.send(Endpoints.dataStatementExecute(
                DataStatementImportRequest(accountId: accountId, transactions: extraction.transactions, skipIndices: skip)
            ))
        } catch {
            isWorking = false
            throw error
        }
        isWorking = false
        step = .execute
        do {
            let final = try await DataImportJobPoller.poll {
                try await client.send(Endpoints.dataStatementStatus(jobId: job.jobId))
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
