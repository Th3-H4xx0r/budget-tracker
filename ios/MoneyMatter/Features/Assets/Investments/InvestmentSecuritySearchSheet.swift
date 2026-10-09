import MoneyMatterKit
import SwiftUI

/// Searches stocks and crypto and adds them to a portfolio as holdings.
struct InvestmentSecuritySearchSheet: View {
    let portfolioID: String

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: LoadState<[InvestmentSecuritySearchResult]> = .idle
    @State private var addedIDs: Set<String> = []
    @State private var addingID: String?
    @State private var alert: ErrorAlert?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Add Symbols")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Ticker or company name")
                )
                .task(id: query) { await search() }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .errorAlert($alert)
        }
    }

    @ViewBuilder private var content: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            ContentUnavailableView {
                Label("Search Securities", systemImage: "magnifyingglass")
            } description: {
                Text("Find stocks and crypto by ticker or name, then tap to add them.")
            }
        } else {
            switch results {
            case .failed(let error):
                LoadFailedView(error: error) { await search() }
            case .loaded(let hits) where hits.isEmpty:
                ContentUnavailableView.search(text: trimmed)
            case .loaded(let hits):
                List(hits) { hit in
                    resultRow(hit)
                }
            case .idle, .loading:
                List {
                    ForEach(0..<5, id: \.self) { _ in
                        VStack(alignment: .leading) {
                            Text(verbatim: "AAPL")
                            Text(verbatim: "Apple Inc. · NASDAQ")
                        }
                    }
                }
                .redactedWhileLoading(true)
            }
        }
    }

    private func resultRow(_ hit: InvestmentSecuritySearchResult) -> some View {
        let isAdded = hit.isInPortfolio == true || addedIDs.contains(hit.id)
        return Button {
            Task { await add(hit) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: hit.symbol)
                        .font(.body.weight(.semibold))
                    Text(verbatim: [hit.name, hit.exchangeName ?? hit.exchangeAcronym].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !hit.isSupported {
                        Text("This asset type isn't supported yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(verbatim: hit.currencyCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if addingID == hit.id {
                    ProgressView()
                } else if isAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel(Text("Added"))
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.tint)
                        .accessibilityLabel(Text("Add"))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAdded || !hit.isSupported || addingID != nil)
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = .idle
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        results = .loading
        do {
            let hits = try await services.investmentsSend(
                Endpoints.investmentSecuritiesSearch(query: trimmed, portfolioID: portfolioID)
            )
            guard !Task.isCancelled else { return }
            results = .loaded(hits)
        } catch {
            guard !Task.isCancelled else { return }
            let apiError = APIError(error)
            if !apiError.isCancellation { results = .failed(apiError) }
        }
    }

    private func add(_ hit: InvestmentSecuritySearchResult) async {
        addingID = hit.id
        defer { addingID = nil }
        do {
            _ = try await services.investmentsSend(
                Endpoints.holdingCreate(HoldingCreateRequest(portfolioId: portfolioID, searchResult: hit))
            )
            addedIDs.insert(hit.id)
        } catch {
            alert = ErrorAlert(error)
        }
    }
}
