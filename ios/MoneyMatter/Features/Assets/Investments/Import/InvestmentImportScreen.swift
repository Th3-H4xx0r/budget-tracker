import MoneyMatterKit
import SwiftUI
import UniformTypeIdentifiers

/// Imports investment transactions into one portfolio from a file: pick a CSV (mapped on
/// the device) or another statement read by AI, review the parsed trades, then import.
/// Mirrors the web `portfolios/transactions-import` flow.
struct InvestmentImportScreen: View {
    let portfolioID: String

    private enum Step {
        case pick
        case mapping(InvestmentImportCSV)
        case aiConfirm
        case review([InvestmentImportHolding], warnings: [String])
        case done(InvestmentImportResult)
    }

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .pick
    @State private var fileData: Data?
    @State private var fileName = ""
    @State private var isPickingFile = false
    @State private var isWorking = false
    @State private var skipped: Set<String> = []
    @State private var resolvingHolding: InvestmentImportHolding?
    @State private var alert: ErrorAlert?

    var body: some View {
        content
            .navigationTitle("Import Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $isPickingFile,
                allowedContentTypes: [.commaSeparatedText, .plainText, .pdf],
                allowsMultipleSelection: false
            ) { result in
                handlePicked(result)
            }
            .overlay {
                if isWorking {
                    ProgressView("Working…")
                        .padding(24)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }
            }
            .disabled(isWorking)
            .sheet(item: $resolvingHolding) { holding in
                InvestmentImportSymbolSearchSheet(initialQuery: holding.parsedSymbol, portfolioID: portfolioID) { security in
                    resolve(holdingID: holding.tempId, with: security)
                }
            }
            .errorAlert($alert)
    }

    private func resolve(holdingID: String, with security: InvestmentImportSecurity) {
        guard case .review(var holdings, let warnings) = step,
              let index = holdings.firstIndex(where: { $0.tempId == holdingID })
        else { return }
        holdings[index].resolvedSecurity = security
        holdings[index].resolvedConfidence = "auto"
        holdings[index].currencyCode = holdings[index].currencyCode ?? security.currencyCode
        step = .review(holdings, warnings: warnings)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .pick:
            ContentUnavailableView {
                Label("Import from a File", systemImage: "square.and.arrow.down")
            } description: {
                Text("Choose a CSV export from your broker to map its columns, or a PDF statement to read with AI.")
            } actions: {
                Button("Choose File") { isPickingFile = true }
                    .buttonStyle(.borderedProminent)
            }
        case .mapping(let csv):
            InvestmentImportMappingForm(csv: csv, fileName: fileName) { mapping in
                await extract(mapping: mapping)
            }
        case .aiConfirm:
            ContentUnavailableView {
                Label(fileName, systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("This file isn't a CSV, so its trades will be read by your AI model. This uses AI credits.")
            } actions: {
                Button("Read with AI") { Task { await extract(mapping: nil) } }
                    .buttonStyle(.borderedProminent)
                Button("Choose Another File") { isPickingFile = true }
            }
        case .review(let holdings, let warnings):
            review(holdings, warnings: warnings)
        case .done(let result):
            doneView(result)
        }
    }

    private func review(_ holdings: [InvestmentImportHolding], warnings: [String]) -> some View {
        let request = InvestmentImportExecuteRequest(holdings: holdings, skipTempIds: skipped)
        let importCount = request.holdings.reduce(0) { total, holding in
            guard !skipped.contains(holding.tempId) else { return total }
            return total + holding.transactions.filter { !skipped.contains($0.tempId) }.count
        }
        return List {
            if !warnings.isEmpty {
                Section {
                    ForEach(warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            if holdings.isEmpty {
                ContentUnavailableView(
                    "No Transactions Found",
                    systemImage: "doc.questionmark",
                    description: Text("Check the column mapping and try again.")
                )
            }
            ForEach(holdings) { holding in
                Section {
                    Button {
                        resolvingHolding = holding
                    } label: {
                        Label(
                            holding.resolvedSecurity == nil ? "Match Symbol" : "Change Match",
                            systemImage: "magnifyingglass"
                        )
                    }
                    ForEach(holding.transactions) { transaction in
                        InvestmentImportTransactionRow(
                            transaction: transaction,
                            currencyCode: holding.resolvedSecurity?.currencyCode ?? holding.currencyCode ?? "USD",
                            isIncluded: Binding(
                                get: { !skipped.contains(transaction.tempId) },
                                set: { include in
                                    if include { skipped.remove(transaction.tempId) } else { skipped.insert(transaction.tempId) }
                                }
                            ),
                            isEnabled: holding.resolvedSecurity != nil && transaction.isImportable
                        )
                    }
                } header: {
                    InvestmentImportHoldingHeader(holding: holding)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await execute(request) }
            } label: {
                Text("Import ^[\(importCount) transaction](inflect: true)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(importCount == 0)
            .padding()
        }
    }

    private func doneView(_ result: InvestmentImportResult) -> some View {
        List {
            Section {
                Label {
                    Text("Import Complete").font(.headline)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            Section {
                LabeledContent("Transactions Imported") { Text(result.createdTransactions, format: .number) }
                LabeledContent("New Holdings") { Text(result.createdHoldings, format: .number) }
                LabeledContent("Merged into Existing") { Text(result.mergedHoldings, format: .number) }
                LabeledContent("New Securities") { Text(result.createdSecurities, format: .number) }
                if result.skippedPossibleDuplicates > 0 {
                    LabeledContent("Skipped Duplicates") { Text(result.skippedPossibleDuplicates, format: .number) }
                }
                if result.skippedHoldings > 0 {
                    LabeledContent("Skipped Holdings") { Text(result.skippedHoldings, format: .number) }
                }
                if result.failedTransactions > 0 {
                    LabeledContent("Failed") { Text(result.failedTransactions, format: .number).foregroundStyle(.red) }
                }
            }
            .monospacedDigit()
            if !result.warnings.isEmpty {
                Section("Warnings") {
                    ForEach(result.warnings, id: \.self) { Text(verbatim: $0).font(.footnote) }
                }
            }
            Section {
                Button("Done") { dismiss() }
                Button("Import Another File") {
                    step = .pick
                    fileData = nil
                    skipped = []
                }
            }
        }
    }

    private func handlePicked(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            alert = ErrorAlert(title: String(localized: "Couldn't Read File"), message: String(localized: "The file couldn't be opened."))
            return
        }
        fileData = data
        fileName = url.lastPathComponent
        let isCSV = url.pathExtension.lowercased() == "csv" || UTType(filenameExtension: url.pathExtension)?.conforms(to: .commaSeparatedText) == true
        if isCSV {
            do {
                let csv = try InvestmentImportCSV.parse(String(decoding: data, as: UTF8.self))
                step = .mapping(csv)
            } catch {
                alert = ErrorAlert(title: String(localized: "Couldn't Read CSV"), message: Self.message(for: error))
            }
        } else {
            step = .aiConfirm
        }
    }

    private static func message(for error: InvestmentImportCSV.ParseError) -> String {
        switch error {
        case .empty: String(localized: "The file is empty.")
        case .noHeaders: String(localized: "The file has no header row.")
        case .tooManyRows: String(localized: "The file has too many rows to import at once.")
        }
    }

    private func extract(mapping: InvestmentImportColumnMapping?) async {
        guard let client = services.client, let fileData else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let endpoint = mapping.map {
                Endpoints.investmentImportExtractCSV(fileData: fileData, portfolioId: portfolioID, mapping: $0)
            } ?? Endpoints.investmentImportExtractAI(fileData: fileData, portfolioId: portfolioID)
            let extraction = try await client.send(endpoint)
            skipped = Set(extraction.holdings.flatMap { holding in
                holding.transactions.filter { $0.possibleDuplicateOf != nil || !$0.isImportable }.map(\.tempId)
            })
            step = .review(extraction.holdings, warnings: extraction.warnings)
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func execute(_ request: InvestmentImportExecuteRequest) async {
        guard let client = services.client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            step = .done(try await client.send(Endpoints.investmentImportExecute(request)))
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// Maps CSV columns to trade fields, and side-column values to trade sides.
private struct InvestmentImportMappingForm: View {
    let csv: InvestmentImportCSV
    let fileName: String
    let onContinue: (InvestmentImportColumnMapping) async -> Void

    @Environment(ReferenceDataStore.self) private var referenceData

    @State private var symbol: String?
    @State private var date: String?
    @State private var side: String?
    @State private var quantity: String?
    @State private var price: String?
    @State private var fees: String?
    @State private var currency: String?
    @State private var name: String?
    @State private var defaultCurrency: String?
    @State private var assetClass = "stocks"
    @State private var sideMapping: [String: String] = [:]
    @State private var didSeed = false

    private static let sideOptions = ["buy", "sell", "dividend", "fee", "tax", "transfer", "other", "skip"]

    private var sideValues: [String] {
        guard let side else { return [] }
        return Array(csv.distinctValues(of: side).prefix(40))
    }

    private var isComplete: Bool {
        symbol != nil && date != nil && side != nil && quantity != nil && price != nil
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("File") { Text(verbatim: fileName).lineLimit(1) }
                LabeledContent("Rows") { Text(csv.rows.count, format: .number).monospacedDigit() }
            }
            Section("Required Columns") {
                columnPicker("Symbol", selection: $symbol, optional: false)
                columnPicker("Date", selection: $date, optional: false)
                columnPicker("Side", selection: $side, optional: false)
                columnPicker("Quantity", selection: $quantity, optional: false)
                columnPicker("Price", selection: $price, optional: false)
            }
            Section("Optional Columns") {
                columnPicker("Fees", selection: $fees, optional: true)
                columnPicker("Currency", selection: $currency, optional: true)
                columnPicker("Name", selection: $name, optional: true)
            }
            Section {
                Picker("Default Currency", selection: $defaultCurrency) {
                    Text("None").tag(String?.none)
                    ForEach(referenceData.userCurrencies) { item in
                        Text(verbatim: item.currencyCode).tag(String?.some(item.currencyCode))
                    }
                }
                Picker("Asset Type", selection: $assetClass) {
                    Text("Stocks").tag("stocks")
                    Text("Crypto").tag("crypto")
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Used when a row has no currency, and to help match symbols.")
            }
            if !sideValues.isEmpty {
                Section {
                    ForEach(sideValues, id: \.self) { value in
                        Picker(selection: Binding(
                            get: { sideMapping[value] ?? InvestmentImportColumnMapping.guessSide(for: value) },
                            set: { sideMapping[value] = $0 }
                        )) {
                            ForEach(Self.sideOptions, id: \.self) { option in
                                Text(Self.sideLabel(option)).tag(option)
                            }
                        } label: {
                            Text(verbatim: value)
                        }
                    }
                } header: {
                    Text("Side Values")
                } footer: {
                    Text("Only buys, sells, and dividends are imported.")
                }
            }
            Section {
                Button("Continue") {
                    Task { await submit() }
                }
                .disabled(!isComplete)
            }
        }
        .onAppear(perform: seed)
    }

    private func columnPicker(_ title: LocalizedStringKey, selection: Binding<String?>, optional: Bool) -> some View {
        Picker(title, selection: selection) {
            Text(optional ? "None" : "Choose").tag(String?.none)
            ForEach(csv.headers, id: \.self) { header in
                Text(verbatim: header).tag(String?.some(header))
            }
        }
    }

    private func seed() {
        guard !didSeed else { return }
        didSeed = true
        symbol = csv.guessColumn(["symbol", "ticker", "instrument"])
        date = csv.guessColumn(["date", "trade date", "time"])
        side = csv.guessColumn(["side", "type", "action", "transaction type"])
        quantity = csv.guessColumn(["quantity", "qty", "shares", "units"])
        price = csv.guessColumn(["price", "unit price", "share price"])
        fees = csv.guessColumn(["fees", "fee", "commission"])
        currency = csv.guessColumn(["currency", "ccy"])
        name = csv.guessColumn(["name", "description", "security"])
    }

    private func submit() async {
        guard let symbol, let date, let side, let quantity, let price else { return }
        var mapping: [String: String] = [:]
        for value in csv.distinctValues(of: side) {
            mapping[value] = sideMapping[value] ?? InvestmentImportColumnMapping.guessSide(for: value)
        }
        await onContinue(InvestmentImportColumnMapping(
            symbol: symbol,
            date: date,
            side: side,
            quantity: quantity,
            price: price,
            fees: fees,
            currency: currency,
            name: name,
            defaultCurrency: defaultCurrency,
            defaultAssetClassHint: assetClass,
            sideValueMapping: mapping
        ))
    }

    static func sideLabel(_ side: String) -> LocalizedStringResource {
        switch side {
        case "buy": "Buy"
        case "sell": "Sell"
        case "dividend": "Dividend"
        case "fee": "Fee"
        case "tax": "Tax"
        case "transfer": "Transfer"
        case "other": "Other"
        default: "Skip"
        }
    }
}

/// The symbol, what it matched, and whether it can be imported.
private struct InvestmentImportHoldingHeader: View {
    let holding: InvestmentImportHolding

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(verbatim: holding.resolvedSecurity?.symbol ?? holding.parsedSymbol)
                    .font(.subheadline.weight(.semibold))
                    .textCase(nil)
                if holding.hasExistingHolding {
                    Text("Existing")
                        .font(.caption2)
                        .textCase(nil)
                        .foregroundStyle(.secondary)
                }
            }
            if let security = holding.resolvedSecurity {
                Text(verbatim: security.name)
                    .font(.caption)
                    .textCase(nil)
                    .lineLimit(1)
            } else {
                Label("Symbol not matched", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .textCase(nil)
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// One parsed trade with an include toggle.
private struct InvestmentImportTransactionRow: View {
    let transaction: InvestmentImportTransaction
    let currencyCode: String
    @Binding var isIncluded: Bool
    let isEnabled: Bool

    var body: some View {
        Toggle(isOn: Binding(get: { isIncluded && isEnabled }, set: { isIncluded = $0 })) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(InvestmentImportMappingForm.sideLabel(transaction.side))
                        .font(.subheadline.weight(.medium))
                    Text(verbatim: transaction.date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if transaction.possibleDuplicateOf != nil {
                        Text("Possible duplicate")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 4) {
                    Text(verbatim: "\(transaction.quantity) ×")
                    AmountText(transaction.priceValue, currencyCode: currencyCode)
                    Text(verbatim: "=")
                    AmountText(transaction.amountValue, currencyCode: currencyCode)
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
        .disabled(!isEnabled)
    }
}

/// Searches securities to match an imported symbol the server couldn't resolve.
private struct InvestmentImportSymbolSearchSheet: View {
    let initialQuery: String
    let portfolioID: String
    let onSelect: (InvestmentImportSecurity) -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: LoadState<[InvestmentSecuritySearchResult]> = .idle

    var body: some View {
        NavigationStack {
            List {
                switch results {
                case .idle:
                    EmptyView()
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                case .failed(let error):
                    InlineRetryView(ErrorMessage.message(for: error)) { await search() }
                case .loaded(let rows) where rows.isEmpty:
                    ContentUnavailableView.search(text: query)
                case .loaded(let rows):
                    ForEach(rows) { result in
                        Button {
                            onSelect(InvestmentImportSecurity(
                                providerSymbol: result.providerSymbol,
                                symbol: result.symbol,
                                name: result.name,
                                assetClass: result.assetClass.rawValue,
                                providerName: result.providerName.rawValue,
                                currencyCode: result.currencyCode,
                                exchangeName: result.exchangeName,
                                cryptoCurrencyCode: result.cryptoCurrencyCode
                            ))
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(verbatim: result.symbol).font(.body.weight(.semibold))
                                    Spacer()
                                    Text(verbatim: result.currencyCode)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(verbatim: [result.name, result.exchangeName].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Symbol or name"))
            .navigationTitle("Match Symbol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if query.isEmpty { query = initialQuery }
            }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await search()
            }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let client = services.client else {
            results = .idle
            return
        }
        results = .loading
        do {
            results = .loaded(try await client.send(Endpoints.investmentSecuritiesSearch(query: text, portfolioID: portfolioID)))
        } catch {
            if !Task.isCancelled { results = .failed(APIError(error)) }
        }
    }
}
