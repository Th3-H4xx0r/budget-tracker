import MoneyMatterKit
import SwiftUI

/// The import hub: every source the web supports, plus past imports.
struct ImportScreen: View {
    var body: some View {
        List {
            Section {
                source(.csv, "Any bank or spreadsheet export. Map the columns yourself.") {
                    DataCSVImportFlow()
                }
                source(.statementParser, "PDF, CSV, or text statements read by AI.") {
                    DataStatementParserFlow()
                }
                source(.ofx, "Open Financial Exchange files from your bank.") {
                    DataProviderImportFlow(kind: .ofx)
                }
            } header: {
                Text("Files")
            }
            Section {
                source(.ynab, "The Register CSV from a YNAB plan export.") {
                    DataProviderImportFlow(kind: .ynab)
                }
                source(.budgetBakersWallet, "Records exported from Wallet by BudgetBakers.") {
                    DataProviderImportFlow(kind: .budgetBakersWallet)
                }
                source(.msMoney, "A Microsoft Money .mny database.") {
                    DataProviderImportFlow(kind: .msMoney)
                }
            } header: {
                Text("Other Apps")
            }
            Section {
                NavigationLink {
                    DataImportHistoryScreen()
                } label: {
                    Label("Import History", systemImage: "clock.arrow.circlepath")
                }
            } footer: {
                Text("Review past imports or delete everything one import created.")
            }
        }
        .navigationTitle("Import")
    }

    private func source<Destination: View>(
        _ source: DataImportSource,
        _ detail: LocalizedStringKey,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.displayName)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: source.systemImage)
            }
        }
    }
}
