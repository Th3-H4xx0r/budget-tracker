import MoneyMatterKit
import SwiftUI
import UniformTypeIdentifiers

/// Reads a file picked with `.fileImporter`, which hands out security-scoped URLs.
enum DataImportFileReader {
    static func read(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    /// Text content for sources that send the file as a string. Falls back to Latin-1 for
    /// exports from older tools.
    static func readText(_ url: URL) throws -> String {
        let data = try read(url)
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}

/// Polls an import job until it finishes. A 404 means the job aged out of retention.
enum DataImportJobPoller {
    static func poll(
        every interval: Duration = .seconds(2),
        fetch: @escaping () async throws -> DataImportProgress,
        onUpdate: @escaping (DataImportProgress) -> Void
    ) async throws -> DataImportProgress {
        var failures = 0
        while true {
            try Task.checkCancellation()
            do {
                let progress = try await fetch()
                failures = 0
                onUpdate(progress)
                if progress.status.isFinished { return progress }
            } catch {
                failures += 1
                if failures >= 5 || Task.isCancelled { throw error }
            }
            try await Task.sleep(for: interval)
        }
    }
}

/// A file-picking row: what's chosen, plus a button to choose.
struct DataImportFilePickerSection: View {
    let title: LocalizedStringKey
    let footer: LocalizedStringKey
    let fileName: String?
    let contentTypes: [UTType]
    let onPick: (URL) -> Void
    @State private var isPicking = false

    var body: some View {
        Section {
            Button {
                isPicking = true
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        if let fileName {
                            Text(fileName)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } icon: {
                    Image(systemName: fileName == nil ? "doc.badge.plus" : "doc.fill")
                }
            }
        } footer: {
            Text(footer)
        }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: contentTypes) { result in
            if case .success(let url) = result { onPick(url) }
        }
    }
}

/// The duplicates the server matched. Each row is skipped unless the user includes it,
/// matching the web's pre-selected "skip" state.
struct DataDuplicateReviewSection: View {
    let duplicates: [DataImportDuplicate]
    @Binding var included: Set<Int>
    let currencyCode: String?

    var body: some View {
        Section {
            if duplicates.isEmpty {
                Label("No duplicates found", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(duplicates) { duplicate in
                    Toggle(isOn: Binding(
                        get: { included.contains(duplicate.rowIndex) },
                        set: { isOn in
                            if isOn { included.insert(duplicate.rowIndex) } else { included.remove(duplicate.rowIndex) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(duplicate.importedDescription.isEmpty ? String(localized: "No description") : duplicate.importedDescription)
                                    .lineLimit(1)
                                Spacer()
                                amount(duplicate.importedAmount)
                            }
                            Text("Matches \(Self.day(duplicate.existingDate)) · \(duplicate.existingNote.isEmpty ? String(localized: "no note") : duplicate.existingNote)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if let confidence = duplicate.confidence {
                                Text("\(confidence)% match")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Possible Duplicates")
        } footer: {
            if !duplicates.isEmpty {
                Text("Duplicates are skipped. Turn a row on to import it anyway.")
            }
        }
    }

    @ViewBuilder
    private func amount(_ value: Decimal) -> some View {
        if let currencyCode {
            AmountText(value, currencyCode: currencyCode)
        } else {
            Text(value, format: .number.precision(.fractionLength(2)))
                .monospacedDigit()
        }
    }

    static func day(_ iso: String) -> String {
        guard let date = APIDateFormat.parseTimestamp(iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// Job progress while an import runs.
struct DataImportProgressSection: View {
    let progress: DataImportProgress?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if let fraction = progress?.fraction {
                    ProgressView(value: fraction) {
                        Text("Importing…")
                    } currentValueLabel: {
                        Text("\(progress?.processedCount ?? 0) of \(progress?.totalCount ?? 0)")
                            .monospacedDigit()
                    }
                } else {
                    ProgressView {
                        Text(progress?.status == .queued ? "Waiting to start…" : "Importing…")
                    }
                }
                Text("You can leave this screen; the import keeps running on the server.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}

/// The finished job's counters, balance changes, and row errors.
struct DataImportResultSections: View {
    let summary: DataImportSummary?
    let failure: String?

    private static let labels: [(String, LocalizedStringKey)] = [
        ("imported", "Transactions imported"),
        ("transactionsImported", "Transactions imported"),
        ("transfersImported", "Transfers imported"),
        ("merged", "Merged with existing"),
        ("skipped", "Skipped"),
        ("duplicatesSkipped", "Duplicates skipped"),
        ("skippedUnpriceable", "Skipped (no exchange rate)"),
        ("outOfWalletImported", "Out-of-wallet imported"),
        ("voidedImported", "Voided imported"),
        ("accountsCreated", "Accounts created"),
        ("accountsLinked", "Accounts linked"),
        ("accountsSkipped", "Accounts skipped"),
        ("categoriesCreated", "Categories created"),
        ("tagsCreated", "Tags created"),
        ("payeesCreated", "Payees created"),
        ("splitsDetected", "Splits detected"),
    ]

    var body: some View {
        if let failure {
            Section {
                Label {
                    Text(failure)
                } icon: {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                }
            } header: {
                Text("Import Failed")
            }
        }
        if let summary {
            Section {
                Label("Import complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                ForEach(Self.labels.filter { summary.counts[$0.0] != nil }, id: \.0) { key, label in
                    LabeledContent(label) {
                        Text(summary.counts[key] ?? 0, format: .number)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Summary")
            }
            if !summary.accountBalanceChanges.isEmpty {
                Section("Account Balances") {
                    ForEach(summary.accountBalanceChanges) { change in
                        LabeledContent {
                            Text(change.balanceAfter, format: .number.precision(.fractionLength(2)))
                                .monospacedDigit()
                        } label: {
                            Text(change.accountName)
                            if change.isNewAccount {
                                Text("New account")
                            } else if let delta = change.delta {
                                Text("Changed by \(delta.formatted(.number.precision(.fractionLength(2))))")
                            }
                        }
                    }
                }
            }
            if !summary.errors.isEmpty {
                Section("Errors") {
                    ForEach(Array(summary.errors.enumerated()), id: \.offset) { _, error in
                        VStack(alignment: .leading, spacing: 2) {
                            if let row = error.rowIndex {
                                Text("Row \(row + 1)").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(error.error).font(.footnote)
                        }
                    }
                }
            }
        }
    }
}

/// How one source account maps onto the user's accounts.
enum DataAccountChoice: Hashable {
    case createNew
    case link(String)
    case skip
}

struct DataAccountMappingRow: View {
    let title: String
    let subtitle: String?
    @Binding var choice: DataAccountChoice
    let accounts: [Account]
    var allowsSkip = true

    var body: some View {
        Picker(selection: $choice) {
            Text("Create new account").tag(DataAccountChoice.createNew)
            if allowsSkip {
                Text("Skip").tag(DataAccountChoice.skip)
            }
            if !accounts.isEmpty {
                Section("Link to Existing") {
                    ForEach(accounts) { account in
                        Text("\(account.name) (\(account.currencyCode))").tag(DataAccountChoice.link(account.id))
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(2)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .pickerStyle(.navigationLink)
    }
}

/// How one source category maps onto the user's categories.
struct DataCategoryMappingRow: View {
    let title: String
    let subtitle: String?
    @Binding var categoryId: String?
    let categories: [MoneyMatterKit.Category]

    var body: some View {
        Picker(selection: $categoryId) {
            Text("Create new category").tag(String?.none)
            ForEach(categories) { category in
                Text(category.name).tag(Optional(category.id))
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(2)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .pickerStyle(.navigationLink)
    }
}

/// A step indicator for the stepped import flows.
struct DataImportStepHeader: View {
    let current: Int
    let titles: [LocalizedStringKey]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Step \(current + 1) of \(titles.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(titles[min(current, titles.count - 1)])
                .font(.headline)
            ProgressView(value: Double(current + 1), total: Double(titles.count))
                .accessibilityHidden(true)
        }
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
    }
}

extension DataImportSource {
    var displayName: LocalizedStringKey {
        switch self {
        case .csv: "CSV"
        case .ynab: "YNAB"
        case .statementParser: "AI Statement Parser"
        case .budgetBakersWallet: "BudgetBakers Wallet"
        case .msMoney: "Microsoft Money"
        case .ofx: "OFX / QFX"
        case .unknown: "Import"
        }
    }

    var systemImage: String {
        switch self {
        case .csv: "tablecells"
        case .ynab: "dollarsign.circle"
        case .statementParser: "doc.text.magnifyingglass"
        case .budgetBakersWallet: "wallet.bifold"
        case .msMoney: "externaldrive"
        case .ofx: "building.columns"
        case .unknown: "square.and.arrow.down"
        }
    }
}
