import MoneyMatterKit
import SwiftUI

/// Venture deals (SPV investments) as cards with their headline metrics, plus entry
/// points to create a deal and manage platforms. Mirrors the web `venture` page.
struct VentureScreen: View {
    @Environment(AppServices.self) private var services

    @State private var state: LoadState<[VentureDeal]> = .idle
    @State private var platformCount = 0
    @State private var statusFilter: VentureDealStatus?
    @State private var isCreating = false
    @State private var pendingDelete: VentureDeal?
    @State private var alert: ErrorAlert?

    var body: some View {
        content
            .navigationTitle("Venture")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Picker("Status", selection: $statusFilter) {
                            Text("All Deals").tag(VentureDealStatus?.none)
                            ForEach(VentureDealStatus.allKnown, id: \.self) { status in
                                Text(VentureLabels.status(status)).tag(VentureDealStatus?.some(status))
                            }
                        }
                        Divider()
                        NavigationLink {
                            VenturePlatformsScreen()
                        } label: {
                            Label("Manage Platforms", systemImage: "building.columns")
                        }
                    } label: {
                        Label("Options", systemImage: statusFilter == nil
                            ? "line.3.horizontal.decrease.circle"
                            : "line.3.horizontal.decrease.circle.fill")
                    }
                    Button {
                        isCreating = true
                    } label: {
                        Label("New Deal", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isCreating) {
                VentureDealFormSheet(deal: nil) { _ in await reload() }
            }
            .confirmationDialog(
                "Delete this deal?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { deal in
                Button("Delete Deal", role: .destructive) {
                    Task { await delete(deal) }
                }
            } message: { _ in
                Text("The deal and its event history will be removed.")
            }
            .errorAlert($alert)
            .task(id: statusFilter) { await reload() }
            .refreshable { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            List {
                ForEach(0..<3, id: \.self) { index in
                    VentureDealCard(deal: VentureScreen.placeholder(index), showsMetrics: false)
                }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await reload() }
        case .loaded(let deals) where deals.isEmpty:
            ContentUnavailableView {
                Label(statusFilter == nil ? "No Deals Yet" : "No Matching Deals", systemImage: "airplane.departure")
            } description: {
                if statusFilter != nil {
                    Text("No deals have this status.")
                } else if platformCount == 0 {
                    Text("Add a platform first if your deals come through a syndicate, then record your first deal.")
                } else {
                    Text("Record an SPV investment to track its value, distributions, and returns.")
                }
            } actions: {
                if statusFilter != nil {
                    Button("Show All Deals") { statusFilter = nil }
                } else {
                    Button("New Deal") { isCreating = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        case .loaded(let deals):
            List {
                ForEach(deals) { deal in
                    NavigationLink {
                        VentureDealDetailScreen(dealID: deal.id) { await reload() }
                    } label: {
                        VentureDealCard(deal: deal, showsMetrics: true)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = deal }
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = deal }
                    }
                }
            }
        }
    }

    private func reload() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            async let deals = client.send(Endpoints.ventureDeals(status: statusFilter))
            async let platforms = client.send(Endpoints.venturePlatforms())
            state = .loaded(try await deals)
            platformCount = (try? await platforms.count) ?? platformCount
        } catch {
            if state.value == nil { state = .failed(APIError(error)) }
        }
    }

    private func delete(_ deal: VentureDeal) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.ventureDealDelete(id: deal.id))
            if case .loaded(let deals) = state {
                state = .loaded(deals.filter { $0.id != deal.id })
            }
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private static func placeholder(_ index: Int) -> VentureDeal {
        VentureDeal(
            id: "placeholder-\(index)",
            name: "Venture deal name",
            targetCompany: "Company",
            currencyCode: "USD",
            principal: 10000,
            investmentDate: CalendarDate(year: 2024, month: 1, day: 1)
        )
    }
}

/// A deal: name, platform or target, status, principal, and (when loaded) value and P&L.
struct VentureDealCard: View {
    let deal: VentureDeal
    let showsMetrics: Bool

    @Environment(AppServices.self) private var services
    @State private var metrics: VentureDealMetrics?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(deal.name)
                        .font(.headline)
                        .lineLimit(2)
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                VentureStatusBadge(status: deal.status)
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invested")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AmountText(deal.principal + deal.entryFee, currencyCode: deal.currencyCode)
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                if let metrics {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Value")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        AmountText(metrics.currentValue, currencyCode: deal.currencyCode)
                            .font(.subheadline.weight(.medium))
                    }
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("P&L")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        AmountText(
                            metrics.pnlAbsolute,
                            currencyCode: deal.currencyCode,
                            style: metrics.pnlAbsolute > 0 ? .income : .neutral,
                            showsPlusSign: metrics.pnlAbsolute > 0
                        )
                        .font(.subheadline.weight(.medium))
                    }
                }
            }
            Text("Invested \(VentureFormat.date(deal.investmentDate))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .task(id: deal.id) {
            guard showsMetrics, metrics == nil, let client = services.client else { return }
            metrics = try? await client.send(Endpoints.ventureDealMetrics(id: deal.id))
        }
    }

    private var subtitle: String? {
        let parts = [deal.platform?.name, deal.targetCompany].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
