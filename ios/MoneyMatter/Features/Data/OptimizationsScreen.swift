import SwiftUI

/// Tools that clean up existing data: find unlinked transfers and categorize with AI.
struct OptimizationsScreen: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    DataTransferSuggestionsScreen()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Transfer Suggestions")
                            Text("Find expenses and incomes that are really one transfer between your accounts.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                }
                NavigationLink {
                    DataAICategorizationScreen()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Categorization")
                            Text("Let AI categorize transactions still in your default category.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                }
            }
        }
        .navigationTitle("Optimizations")
    }
}
