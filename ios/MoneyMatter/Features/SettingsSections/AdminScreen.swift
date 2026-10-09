import MoneyMatterKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Admin (admins only): tools for the server operator. Today that's uploading
/// historical security prices from a CSV or JSON file.
struct AdminScreen: View {
    @State private var showsPriceUpload = false

    var body: some View {
        Form {
            Section {
                Button {
                    showsPriceUpload = true
                } label: {
                    Label("Upload Security Prices", systemImage: "chart.line.uptrend.xyaxis")
                }
            } header: {
                Text("Securities")
            } footer: {
                Text("Add historical prices for a security the price providers don't cover. Prices are shared by every user on this server.")
            }
        }
        .navigationTitle("Admin")
        .sheet(isPresented: $showsPriceUpload) {
            AdminPriceUploadFlow()
        }
    }
}

// MARK: - Flow

private enum AdminPriceUploadStep: Hashable {
    case file
    case mapping
    case preview
    case options
    case result
}

@MainActor
@Observable
private final class AdminPriceUploadModel {
    var security: SettingsAdminSecurity?
    var info: SettingsAdminPriceUploadInfo?
    var file: SettingsAdminPriceFile?
    var fileName = ""
    var mapping = SettingsAdminPriceMapping()
    var rows: [SettingsAdminPriceRow] = []
    var autoFilter = true
    var override = false
    var result: SettingsAdminBulkUploadResult?
}

/// Select security → choose file → map columns → preview → options → result, as a pushed
/// stack inside its own sheet.
private struct AdminPriceUploadFlow: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var model = AdminPriceUploadModel()
    @State private var path: [AdminPriceUploadStep] = []
    @State private var alert: ErrorAlert?

    var body: some View {
        NavigationStack(path: $path) {
            AdminSecuritySearchStep { security in
                await select(security)
            }
            .navigationDestination(for: AdminPriceUploadStep.self) { step in
                switch step {
                case .file: AdminFileStep(model: model) { path.append(.mapping) }
                case .mapping: AdminMappingStep(model: model) { path.append(.preview) }
                case .preview: AdminPreviewStep(model: model) { path.append(.options) }
                case .options: AdminOptionsStep(model: model) { path.append(.result) }
                case .result: AdminResultStep(model: model) { dismiss() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .environment(model)
        .errorAlert($alert)
    }

    private func select(_ security: SettingsAdminSecurity) async {
        guard let client = services.client else { return }
        do {
            model.info = try await client.send(Endpoints.settingsAdminPriceUploadInfo(currencyCode: security.currencyCode))
            model.security = security
            model.file = nil
            model.result = nil
            path = [.file]
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

private struct AdminSecuritySearchStep: View {
    let onSelect: (SettingsAdminSecurity) async -> Void

    @Environment(AppServices.self) private var services
    @State private var query = ""
    @State private var results: LoadState<[SettingsAdminSecurity]> = .idle
    @State private var selectingID: String?

    var body: some View {
        List {
            switch results {
            case .idle:
                ContentUnavailableView(
                    "Find a Security",
                    systemImage: "magnifyingglass",
                    description: Text("Search by ticker, name, or ISIN to choose the security to upload prices for.")
                )
            case .loading:
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading) {
                        Text("Security Name Placeholder")
                        Text("TICK · Exchange")
                            .font(.caption)
                    }
                }
                .redactedWhileLoading(true)
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await search() }
            case .loaded(let securities) where securities.isEmpty:
                ContentUnavailableView.search(text: query)
            case .loaded(let securities):
                ForEach(securities) { security in
                    Button {
                        selectingID = security.id
                        Task {
                            await onSelect(security)
                            selectingID = nil
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(security.name)
                                    .foregroundStyle(.primary)
                                Text(Self.detail(security))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectingID == security.id { ProgressView() }
                        }
                    }
                    .disabled(selectingID != nil)
                }
            }
        }
        .navigationTitle("Choose Security")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Ticker, name, or ISIN"))
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard let client = services.client, !term.isEmpty else {
            results = .idle
            return
        }
        results = .loading
        do {
            results = .loaded(try await client.send(Endpoints.settingsAdminSearchSecurities(query: term)))
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation { results = .failed(apiError) }
        }
    }

    private static func detail(_ security: SettingsAdminSecurity) -> String {
        [security.symbol, security.exchangeAcronym ?? security.exchangeName, security.currencyCode]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private struct AdminSelectedSecuritySection: View {
    @Environment(AdminPriceUploadModel.self) private var model

    var body: some View {
        if let security = model.security {
            Section("Security") {
                LabeledContent("Name", value: security.name)
                LabeledContent("Symbol", value: security.symbol)
                LabeledContent("Currency", value: security.currencyCode)
            }
        }
    }
}

private struct AdminFileStep: View {
    let model: AdminPriceUploadModel
    let onContinue: () -> Void
    @State private var importsFile = false
    @State private var alert: ErrorAlert?

    var body: some View {
        Form {
            AdminSelectedSecuritySection()
            if let info = model.info {
                Section {
                    if let oldest = SettingsAdminPriceUploadInfo.day(info.oldestDate),
                       let newest = SettingsAdminPriceUploadInfo.day(info.newestDate) {
                        LabeledContent("Exchange Rates", value: "\(oldest) – \(newest)")
                            .monospacedDigit()
                    }
                    if let minimum = SettingsAdminPriceUploadInfo.day(info.minAllowedDate) {
                        LabeledContent("Earliest Allowed", value: minimum)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Available Range")
                } footer: {
                    Text("Prices can only be stored for dates that have exchange rates.")
                }
            }
            Section {
                Button {
                    importsFile = true
                } label: {
                    Label("Choose CSV or JSON File", systemImage: "doc.badge.plus")
                }
            } footer: {
                Text("A CSV needs a header row with a date column and a price column. A JSON file must be an array of objects.")
            }
        }
        .navigationTitle("Price File")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importsFile, allowedContentTypes: [.commaSeparatedText, .json, .plainText]) { result in
            load(result)
        }
        .errorAlert($alert)
    }

    private func load(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let isJSON = url.pathExtension.lowercased() == "json"
            let file = try SettingsAdminPriceFile.parse(data: data, isJSON: isJSON)
            model.file = file
            model.fileName = url.lastPathComponent
            model.mapping = SettingsAdminPriceMapping.autoDetect(fields: file.fields)
            onContinue()
        } catch is SettingsAdminPriceFile.ParseError {
            alert = ErrorAlert(
                title: String(localized: "Couldn't Read File"),
                message: String(localized: "The file has no price rows, or it isn't a CSV with a header row or a JSON array of objects.")
            )
        } catch {
            if let presented = ErrorAlert(error) {
                alert = ErrorAlert(title: String(localized: "Couldn't Read File"), message: presented.message)
            }
        }
    }
}

private struct AdminMappingStep: View {
    @Bindable var model: AdminPriceUploadModel
    let onContinue: () -> Void
    @State private var alert: ErrorAlert?

    var body: some View {
        Form {
            Section {
                LabeledContent("File", value: model.fileName)
                LabeledContent("Rows") {
                    Text(model.file?.rows.count ?? 0, format: .number)
                        .monospacedDigit()
                }
            }
            Section {
                columnPicker(Text("Date Column"), field: .date)
                columnPicker(Text("Price Column"), field: .price)
            } header: {
                Text("Columns")
            } footer: {
                Text("Columns named like “date” and “price”, “value”, or “amount” are matched automatically.")
            }
            Section("Date Format") {
                Picker("Date Format", selection: $model.mapping.dateFormat) {
                    ForEach(SettingsAdminDateFormat.allCases) { format in
                        Text(Self.example(format)).tag(format)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .navigationTitle("Map Columns")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Continue") { transform() }
                    .disabled(!model.mapping.isComplete)
            }
        }
        .errorAlert($alert)
    }

    private func columnPicker(_ title: Text, field: SettingsAdminPriceField) -> some View {
        Picker(selection: Binding(
            get: { model.mapping.columns[field] ?? "" },
            set: { model.mapping.columns[field] = $0.isEmpty ? nil : $0 }
        )) {
            Text("Not Mapped").tag("")
            ForEach(model.file?.fields ?? [], id: \.self) { column in
                Text(column).tag(column)
            }
        } label: {
            title
        }
    }

    private func transform() {
        guard let file = model.file, let security = model.security else { return }
        do {
            model.rows = try model.mapping.rows(from: file, currency: security.currencyCode)
            onContinue()
        } catch let error as SettingsAdminPriceMapping.TransformError {
            alert = ErrorAlert(title: String(localized: "Check the Mapping"), message: Self.message(for: error))
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private static func message(for error: SettingsAdminPriceMapping.TransformError) -> String {
        switch error {
        case .incompleteMapping:
            String(localized: "Choose both a date column and a price column.")
        case .invalidDate(let row, let value):
            String(localized: "Row \(row) has the date “\(value)”, which doesn't match the selected date format.")
        case .invalidPrice(let row, let value):
            String(localized: "Row \(row) has the price “\(value)”, which isn't a positive number.")
        }
    }

    private static func example(_ format: SettingsAdminDateFormat) -> String {
        switch format {
        case .dayMonthYearSlash: "31/12/2024 (dd/MM/yyyy)"
        case .monthDayYearSlash: "12/31/2024 (MM/dd/yyyy)"
        case .isoDash: "2024-12-31 (yyyy-MM-dd)"
        case .dayMonthYearDash: "31-12-2024 (dd-MM-yyyy)"
        case .monthDayYearDash: "12-31-2024 (MM-dd-yyyy)"
        }
    }
}

private struct AdminPreviewStep: View {
    let model: AdminPriceUploadModel
    let onContinue: () -> Void

    private static let previewLimit = 100

    var body: some View {
        List {
            Section {
                LabeledContent("Prices") {
                    Text(model.rows.count, format: .number)
                        .monospacedDigit()
                }
                if let first = model.rows.map(\.date).min(), let last = model.rows.map(\.date).max() {
                    LabeledContent("Dates", value: "\(first) – \(last)")
                        .monospacedDigit()
                }
            }
            Section {
                ForEach(Array(model.rows.prefix(Self.previewLimit).enumerated()), id: \.offset) { _, row in
                    LabeledContent(row.date) {
                        Text(row.price, format: .number.precision(.fractionLength(0...8)))
                            .monospacedDigit()
                    }
                    .monospacedDigit()
                }
            } header: {
                Text("Preview")
            } footer: {
                if model.rows.count > Self.previewLimit {
                    Text("Showing the first \(Self.previewLimit) rows.")
                }
            }
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Continue", action: onContinue)
                    .disabled(model.rows.isEmpty)
            }
        }
    }
}

private struct AdminOptionsStep: View {
    @Bindable var model: AdminPriceUploadModel
    let onFinished: () -> Void

    @Environment(AppServices.self) private var services
    @State private var isUploading = false
    @State private var alert: ErrorAlert?

    var body: some View {
        Form {
            AdminSelectedSecuritySection()
            Section {
                Toggle("Skip Dates Without Exchange Rates", isOn: $model.autoFilter)
                Toggle("Replace Existing Prices", isOn: $model.override)
            } footer: {
                Text("Skipping keeps the upload from failing on dates outside the available range. Replacing overwrites prices already stored for the same dates; otherwise they're left as they are.")
            }
            Section {
                Button {
                    Task { await upload() }
                } label: {
                    HStack {
                        Text("Upload \(model.rows.count) Prices")
                        Spacer()
                        if isUploading { ProgressView() }
                    }
                }
                .disabled(isUploading || model.rows.isEmpty)
            }
        }
        .navigationTitle("Upload Options")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isUploading)
        .errorAlert($alert)
    }

    private func upload() async {
        guard let client = services.client, let security = model.security else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            model.result = try await client.send(Endpoints.settingsAdminBulkUploadPrices(SettingsAdminBulkUploadRequest(
                searchResult: security,
                prices: model.rows,
                autoFilter: model.autoFilter,
                override: model.override
            )))
            onFinished()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

private struct AdminResultStep: View {
    let model: AdminPriceUploadModel
    let onDone: () -> Void

    var body: some View {
        Form {
            if let result = model.result {
                Section {
                    Label("Upload Complete", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    count(Text("Inserted"), result.summary.inserted)
                    count(Text("Duplicates Skipped"), result.summary.duplicates)
                    count(Text("Filtered Out"), result.summary.filtered)
                }
                if let oldest = SettingsAdminPriceUploadInfo.day(result.newOldestDate),
                   let newest = SettingsAdminPriceUploadInfo.day(result.newNewestDate) {
                    Section("Stored Price Range") {
                        Text("\(oldest) – \(newest)")
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone)
            }
        }
    }

    private func count(_ title: Text, _ value: Int) -> some View {
        LabeledContent {
            Text(value, format: .number)
                .monospacedDigit()
        } label: {
            title
        }
    }
}
