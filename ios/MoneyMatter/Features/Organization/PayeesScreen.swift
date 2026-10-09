import MoneyMatterKit
import SwiftUI

/// Settings → Payees: a searchable, sortable list of payees with their stats, mirroring the
/// web Manage tab. Rows open the payee detail; the toolbar creates payees and opens the
/// payee settings (auto-detection and ignored names).
struct PayeesScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData

    @State private var state: LoadState<[OrgPayee]> = .idle
    @State private var query = ""
    @State private var sortBy: OrgPayeeSortField = .transactionCount
    @State private var sortDir: OrgPayeeSortDirection = .desc
    @State private var canLoadMore = false
    @State private var isLoadingMore = false
    @State private var isCreating = false
    @State private var alert: ErrorAlert?

    private static let pageSize = 50

    var body: some View {
        content
            .navigationTitle("Payees")
            .searchable(text: $query, prompt: "Search payees")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        OrgPayeeSettingsScreen()
                    } label: {
                        Label("Payee Settings", systemImage: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreating = true
                    } label: {
                        Label("New Payee", systemImage: "plus")
                    }
                }
            }
            .task(id: ReloadKey(query: query, sortBy: sortBy, sortDir: sortDir)) {
                if !query.isEmpty {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                }
                await reload()
            }
            .refreshable {
                await reload()
                await referenceData.refreshPayees()
            }
            .sheet(isPresented: $isCreating) {
                OrgPayeeFormSheet(payee: nil) { _ in
                    Task { await reload() }
                }
            }
            .errorAlert($alert)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            placeholderList
        case .failed(let error):
            LoadFailedView(error: error) { await reload() }
        case .loaded(let payees):
            if payees.isEmpty {
                emptyState
            } else {
                list(payees)
            }
        }
    }

    private var placeholderList: some View {
        List {
            ForEach(0..<8, id: \.self) { _ in
                OrgPayeeListRow(
                    payee: OrgPayee(id: "placeholder", name: "Placeholder payee", stats: OrgPayeeStats(transactionCount: 12, netFlowRef: -120)),
                    category: nil,
                    currencyCode: "USD"
                )
            }
        }
        .redactedWhileLoading(true)
    }

    @ViewBuilder
    private var emptyState: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView {
                Label("No Payees", systemImage: "storefront")
            } description: {
                Text("Payees are created from the merchants in your transactions, or you can add one yourself.")
            } actions: {
                Button("New Payee") { isCreating = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    private func list(_ payees: [OrgPayee]) -> some View {
        let currency = OrgPayeeSupport.baseCurrencyCode(referenceData)
        return List {
            Section {
                ForEach(payees) { payee in
                    NavigationLink {
                        OrgPayeeDetailScreen(payeeID: payee.id) {
                            Task { await reload() }
                        }
                    } label: {
                        OrgPayeeListRow(
                            payee: payee,
                            category: referenceData.category(id: payee.displayCategoryId),
                            currencyCode: currency
                        )
                    }
                    .onAppear {
                        if payee.id == payees.last?.id, canLoadMore {
                            Task { await loadMore() }
                        }
                    }
                }
                if isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } footer: {
                Text("Sorted by \(OrgPayeeSupport.title(for: sortBy)), \(sortDir == .asc ? String(localized: "ascending") : String(localized: "descending")).")
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(OrgPayeeSortField.allCases, id: \.self) { field in
                Button {
                    if sortBy == field {
                        sortDir = sortDir == .asc ? .desc : .asc
                    } else {
                        sortBy = field
                        sortDir = field.defaultDirection
                    }
                } label: {
                    if sortBy == field {
                        Label(OrgPayeeSupport.title(for: field), systemImage: sortDir == .asc ? "arrow.up" : "arrow.down")
                    } else {
                        Text(OrgPayeeSupport.title(for: field))
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    private func reload() async {
        if state.value == nil { state = .loading }
        do {
            let page = try await OrgPayeeSupport.client(services).send(
                Endpoints.orgPayees(query: query, sortBy: sortBy, sortDir: sortDir, limit: Self.pageSize, offset: 0)
            )
            guard !Task.isCancelled else { return }
            state = .loaded(page)
            canLoadMore = query.trimmingCharacters(in: .whitespaces).isEmpty && page.count >= Self.pageSize
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            if state.value == nil {
                state = .failed(apiError)
            } else {
                alert = ErrorAlert(error)
            }
        }
    }

    private func loadMore() async {
        guard let current = state.value, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await OrgPayeeSupport.client(services).send(
                Endpoints.orgPayees(sortBy: sortBy, sortDir: sortDir, limit: Self.pageSize, offset: current.count)
            )
            let known = Set(current.map(\.id))
            state = .loaded(current + page.filter { !known.contains($0.id) })
            canLoadMore = page.count >= Self.pageSize
        } catch {
            canLoadMore = false
            alert = ErrorAlert(error)
        }
    }

    private struct ReloadKey: Equatable {
        let query: String
        let sortBy: OrgPayeeSortField
        let sortDir: OrgPayeeSortDirection
    }
}

/// One payee in the list: logo, name, category, transaction count, and net flow.
private struct OrgPayeeListRow: View {
    let payee: OrgPayee
    let category: Category?
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            OrgPayeeLogoBadge(name: payee.name, initials: payee.logoInitials, colorHex: payee.logoColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(payee.name)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let category {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(Color(hex: category.color) ?? .gray)
                        Text(category.name)
                    } else {
                        Text("No category")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                OrgPayeeNetFlowText(amount: payee.stats?.netFlowRef ?? 0, currencyCode: currencyCode)
                Text("\(payee.stats?.transactionCount ?? 0) transactions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
