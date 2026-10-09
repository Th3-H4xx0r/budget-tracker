import MoneyMatterKit
import SwiftUI

/// Configure and generate a data export (a zip of JSON, CSV, or Excel files), then share it.
struct ExportScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var reference
    @State private var format: DataExportFormat = .json
    @State private var groups: Set<DataExportGroup> = Set(DataExportGroup.allCases)
    @State private var limitsDates = false
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var to = Date.now
    @State private var accountIds: Set<String> = []
    @State private var isGenerating = false
    @State private var exported: ExportedFile?
    @State private var alert: ErrorAlert?

    private struct ExportedFile {
        let url: URL
        let filename: String
        let totalRows: Int?
    }

    var body: some View {
        Form {
            Section {
                Picker("Format", selection: $format) {
                    Text("JSON").tag(DataExportFormat.json)
                    Text("CSV").tag(DataExportFormat.csv)
                    Text("Excel").tag(DataExportFormat.xlsx)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Format")
            } footer: {
                Text("The export downloads as a zip file.")
            }

            Section("Include") {
                ForEach(DataExportGroup.allCases, id: \.self) { group in
                    Toggle(isOn: Binding(
                        get: { groups.contains(group) },
                        set: { isOn in
                            if isOn { groups.insert(group) } else { groups.remove(group) }
                        }
                    )) {
                        Label(Self.title(group), systemImage: Self.icon(group))
                    }
                }
            }

            Section("Period") {
                Toggle("Limit to a date range", isOn: $limitsDates)
                if limitsDates {
                    DatePicker("From", selection: $from, in: ...to, displayedComponents: .date)
                    DatePicker("To", selection: $to, in: from..., displayedComponents: .date)
                }
            }

            Section {
                NavigationLink {
                    accountPicker
                } label: {
                    LabeledContent("Accounts") {
                        Text(accountIds.isEmpty ? String(localized: "All") : String(localized: "\(accountIds.count) selected"))
                    }
                }
            }

            if let exported {
                Section {
                    LabeledContent("File", value: exported.filename)
                    if let rows = exported.totalRows {
                        LabeledContent("Rows", value: rows, format: .number)
                    }
                    ShareLink(item: exported.url) {
                        Label("Share Export", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Ready")
                }
            }
        }
        .navigationTitle("Export")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isGenerating {
                    ProgressView()
                } else {
                    Button("Generate") { Task { await generate() } }
                        .disabled(groups.isEmpty)
                }
            }
        }
        .onChange(of: configuration) { exported = nil }
        .errorAlert($alert)
        .task { await reference.loadIfNeeded() }
    }

    private var configuration: DataExportRequest {
        DataExportRequest(
            format: format,
            groups: DataExportGroup.allCases.filter { groups.contains($0) },
            dateRange: limitsDates ? DataExportDateRange(from: CalendarDate(date: from), to: CalendarDate(date: to)) : nil,
            accountIds: reference.accounts.map(\.id).filter { accountIds.contains($0) }
        )
    }

    private var accountPicker: some View {
        List {
            Section {
                Button {
                    accountIds = []
                } label: {
                    HStack {
                        Text("All Accounts").foregroundStyle(.primary)
                        Spacer()
                        if accountIds.isEmpty {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
            }
            Section {
                ForEach(reference.accounts) { account in
                    Button {
                        if accountIds.contains(account.id) { accountIds.remove(account.id) } else { accountIds.insert(account.id) }
                    } label: {
                        HStack {
                            Text(account.name).foregroundStyle(.primary)
                            Spacer()
                            if accountIds.contains(account.id) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityAddTraits(accountIds.contains(account.id) ? .isSelected : [])
                }
            }
        }
        .navigationTitle("Accounts")
    }

    private func generate() async {
        guard let client = services.client else { return }
        isGenerating = true
        defer { isGenerating = false }
        do {
            let file = try await client.dataDownload(configuration)
            let directory = FileManager.default.temporaryDirectory.appending(path: "exports", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: file.filename)
            try? FileManager.default.removeItem(at: url)
            try file.data.write(to: url, options: .atomic)
            exported = ExportedFile(url: url, filename: file.filename, totalRows: file.totalRows)
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private static func title(_ group: DataExportGroup) -> LocalizedStringKey {
        switch group {
        case .transactions: "Transactions"
        case .budgets: "Budgets"
        case .subscriptions: "Subscriptions"
        case .investments: "Investments"
        }
    }

    private static func icon(_ group: DataExportGroup) -> String {
        switch group {
        case .transactions: "list.bullet.rectangle"
        case .budgets: "chart.pie"
        case .subscriptions: "repeat"
        case .investments: "chart.line.uptrend.xyaxis"
        }
    }
}
