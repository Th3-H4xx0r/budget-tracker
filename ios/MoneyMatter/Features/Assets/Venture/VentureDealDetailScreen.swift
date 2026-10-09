import MoneyMatterKit
import SwiftUI

/// One deal: status, return metrics, terms, and the events timeline, with event and deal
/// editing. Mirrors the web `deal-detail` page.
struct VentureDealDetailScreen: View {
    let dealID: String
    var onChange: () async -> Void = {}

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var state: LoadState<VentureDeal> = .idle
    @State private var metrics: LoadState<VentureDealMetrics> = .idle
    @State private var events: LoadState<[VentureEvent]> = .idle
    @State private var isEditing = false
    @State private var isAddingEvent = false
    @State private var editingEvent: VentureEvent?
    @State private var pendingEventDelete: VentureEvent?
    @State private var isConfirmingDelete = false
    @State private var alert: ErrorAlert?

    var body: some View {
        content
            .navigationTitle(state.value?.name ?? String(localized: "Deal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let deal = state.value {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Add Event", systemImage: "plus") { isAddingEvent = true }
                            Button("Edit Deal", systemImage: "pencil") { isEditing = true }
                            Menu {
                                ForEach(VentureDealStatus.allKnown, id: \.self) { status in
                                    Button {
                                        Task { await setStatus(status) }
                                    } label: {
                                        if status == deal.status {
                                            Label { Text(VentureLabels.status(status)) } icon: { Image(systemName: "checkmark") }
                                        } else {
                                            Text(VentureLabels.status(status))
                                        }
                                    }
                                }
                            } label: {
                                Label("Status", systemImage: "flag")
                            }
                            Divider()
                            Button("Delete Deal", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                        } label: {
                            Label("Actions", systemImage: "ellipsis")
                        }
                    }
                }
            }
            .sheet(isPresented: $isEditing) {
                if let deal = state.value {
                    VentureDealFormSheet(deal: deal) { _ in await reloadAll() }
                }
            }
            .sheet(isPresented: $isAddingEvent) {
                if let deal = state.value {
                    VentureEventFormSheet(deal: deal, event: nil, hasInitialInvestment: hasInitialInvestment) {
                        await reloadAll()
                    }
                }
            }
            .sheet(item: $editingEvent) { event in
                if let deal = state.value {
                    VentureEventFormSheet(deal: deal, event: event, hasInitialInvestment: hasInitialInvestment) {
                        await reloadAll()
                    }
                }
            }
            .confirmationDialog("Delete this deal?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Deal", role: .destructive) {
                    Task { await deleteDeal() }
                }
            } message: {
                Text("The deal and its event history will be removed.")
            }
            .confirmationDialog(
                "Delete this event?",
                isPresented: Binding(
                    get: { pendingEventDelete != nil },
                    set: { if !$0 { pendingEventDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingEventDelete
            ) { event in
                if event.links.isEmpty {
                    Button("Delete Event", role: .destructive) {
                        Task { await deleteEvent(event, deleteLinkedTransactions: nil) }
                    }
                } else {
                    Button("Delete Event and Linked Transactions", role: .destructive) {
                        Task { await deleteEvent(event, deleteLinkedTransactions: true) }
                    }
                    Button("Delete Event, Keep Transactions", role: .destructive) {
                        Task { await deleteEvent(event, deleteLinkedTransactions: false) }
                    }
                }
            } message: { _ in
                Text("Later events are recalculated without it.")
            }
            .errorAlert($alert)
            .task {
                if case .idle = state { await reloadAll() }
            }
            .refreshable { await reloadAll() }
    }

    private var hasInitialInvestment: Bool {
        events.value?.contains { $0.type == .initialInvestment } ?? false
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            List {
                Section { Text("Deal summary placeholder").frame(height: 80) }
                Section { Text("Metrics placeholder").frame(height: 120) }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await reloadAll() }
        case .loaded(let deal):
            List {
                Section {
                    header(deal)
                }
                Section("Performance") {
                    metricsSection(deal)
                }
                Section("Terms") {
                    terms(deal)
                }
                Section {
                    eventsSection(deal)
                } header: {
                    HStack {
                        Text("Events")
                        Spacer()
                        Button {
                            isAddingEvent = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .accessibilityLabel("Add Event")
                    }
                }
                if let notes = deal.notes, !notes.isEmpty {
                    Section("Notes") {
                        Text(verbatim: notes)
                    }
                }
            }
        }
    }

    private func header(_ deal: VentureDeal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VentureStatusBadge(status: deal.status)
                Spacer()
            }
            if let company = deal.targetCompany, !company.isEmpty {
                Text(verbatim: company)
                    .font(.title3.weight(.semibold))
            }
            if let platform = deal.platform?.name {
                Label {
                    Text(verbatim: platform)
                } icon: {
                    Image(systemName: "building.columns")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            AmountText(deal.principal, currencyCode: deal.currencyCode)
                .font(.title.weight(.semibold))
            Text("Principal, invested \(VentureFormat.date(deal.investmentDate))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func metricsSection(_ deal: VentureDeal) -> some View {
        switch metrics {
        case .idle, .loading:
            LabeledContent("Current Value", value: "000,000")
                .redactedWhileLoading(true)
        case .failed:
            InlineRetryView(String(localized: "Couldn't load metrics.")) { await loadMetrics() }
        case .loaded(let metrics):
            LabeledContent("Cost Basis") { AmountText(metrics.costBasis, currencyCode: deal.currencyCode) }
            LabeledContent("Total Invested") { AmountText(metrics.totalInvested, currencyCode: deal.currencyCode) }
            LabeledContent("Current Value") {
                AmountText(metrics.currentValue, currencyCode: deal.currencyCode).fontWeight(.semibold)
            }
            LabeledContent("Distributions") { AmountText(metrics.totalDistributions, currencyCode: deal.currencyCode) }
            LabeledContent("P&L") {
                HStack(spacing: 6) {
                    AmountText(
                        metrics.pnlAbsolute,
                        currencyCode: deal.currencyCode,
                        style: metrics.pnlAbsolute > 0 ? .income : .neutral,
                        showsPlusSign: metrics.pnlAbsolute > 0
                    )
                    if metrics.pnlPct != nil {
                        Text(verbatim: "(\(VentureFormat.percent(metrics.pnlPct, signed: true)))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            LabeledContent("TVPI") { Text(verbatim: VentureFormat.multiple(metrics.tvpi)).monospacedDigit() }
            LabeledContent("DPI") { Text(verbatim: VentureFormat.multiple(metrics.dpi)).monospacedDigit() }
            LabeledContent("IRR") { Text(verbatim: VentureFormat.percent(metrics.irr, signed: true)).monospacedDigit() }
        }
    }

    @ViewBuilder
    private func terms(_ deal: VentureDeal) -> some View {
        if let subtype = deal.spvSubtype {
            LabeledContent("Structure") { Text(VentureLabels.spvSubtype(subtype)) }
        }
        LabeledContent("Entry Fee") {
            HStack(spacing: 6) {
                AmountText(deal.entryFee, currencyCode: deal.currencyCode)
                Text(verbatim: "(\(VentureFormat.percent(deal.entryFeePct)))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        LabeledContent("Management Fee") { Text(verbatim: VentureFormat.percent(deal.mgmtFeePct)).monospacedDigit() }
        LabeledContent("Carry") { Text(verbatim: VentureFormat.percent(deal.carryPct)).monospacedDigit() }
        LabeledContent("Hurdle") { Text(verbatim: VentureFormat.percent(deal.hurdlePct)).monospacedDigit() }
        LabeledContent("Investment Date") { Text(verbatim: VentureFormat.date(deal.investmentDate)) }
        if let exit = deal.expectedExitDate {
            LabeledContent("Expected Exit") { Text(verbatim: VentureFormat.date(exit)) }
        }
    }

    @ViewBuilder
    private func eventsSection(_ deal: VentureDeal) -> some View {
        switch events {
        case .idle, .loading:
            Text("Loading events")
                .redactedWhileLoading(true)
        case .failed:
            InlineRetryView(String(localized: "Couldn't load events.")) { await loadEvents() }
        case .loaded(let rows) where rows.isEmpty:
            VStack(alignment: .leading, spacing: 8) {
                Text("No events yet. Start with the initial investment.")
                    .foregroundStyle(.secondary)
                Button("Add Initial Investment") { isAddingEvent = true }
            }
        case .loaded(let rows):
            ForEach(rows.sorted { $0.eventDate > $1.eventDate }) { event in
                Button {
                    editingEvent = event
                } label: {
                    VentureEventRow(event: event, currencyCode: deal.currencyCode)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingEventDelete = event }
                    Button("Edit", systemImage: "pencil") { editingEvent = event }
                }
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { editingEvent = event }
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingEventDelete = event }
                }
            }
        }
    }

    private func reloadAll() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await client.send(Endpoints.ventureDeal(id: dealID)))
        } catch {
            if state.value == nil { state = .failed(APIError(error)) }
            return
        }
        async let metricsLoad: Void = loadMetrics()
        async let eventsLoad: Void = loadEvents()
        _ = await (metricsLoad, eventsLoad)
    }

    private func loadMetrics() async {
        guard let client = services.client else { return }
        do {
            metrics = .loaded(try await client.send(Endpoints.ventureDealMetrics(id: dealID)))
        } catch {
            if metrics.value == nil { metrics = .failed(APIError(error)) }
        }
    }

    private func loadEvents() async {
        guard let client = services.client else { return }
        do {
            events = .loaded(try await client.send(Endpoints.ventureEvents(dealId: dealID)))
        } catch {
            if events.value == nil { events = .failed(APIError(error)) }
        }
    }

    private func setStatus(_ status: VentureDealStatus) async {
        guard let client = services.client else { return }
        do {
            state = .loaded(try await client.send(Endpoints.ventureDealSetStatus(id: dealID, status: status)))
            await onChange()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func deleteDeal() async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.ventureDealDelete(id: dealID))
            await onChange()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func deleteEvent(_ event: VentureEvent, deleteLinkedTransactions: Bool?) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.ventureEventDelete(id: event.id, deleteLinkedTransactions: deleteLinkedTransactions))
            await reloadAll()
            await onChange()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// One timeline entry: type, date, amounts, and how cash moved.
private struct VentureEventRow: View {
    let event: VentureEvent
    let currencyCode: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: VentureLabels.eventSymbol(event.type))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(VentureLabels.eventType(event.type))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if let gross = event.grossAmount {
                        AmountText(
                            gross,
                            currencyCode: event.currencyCode.isEmpty ? currencyCode : event.currencyCode,
                            style: event.type == .distribution || event.type == .exit ? .income : .neutral
                        )
                        .font(.subheadline.weight(.medium))
                    }
                }
                Text(verbatim: VentureFormat.date(event.eventDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let nav = event.navAfter {
                    HStack(spacing: 4) {
                        Text("NAV after")
                        AmountText(nav, currencyCode: currencyCode)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let carry = event.gpCarryAmount, carry != 0 {
                    HStack(spacing: 4) {
                        Text(event.gpCarryOverridden ? "GP carry (manual)" : "GP carry")
                        AmountText(carry, currencyCode: currencyCode)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if event.cashFlowMode != .none, event.cashFlowMode != .unknown {
                    Text(VentureLabels.cashFlow(event.cashFlowMode))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let notes = event.notes, !notes.isEmpty {
                    Text(verbatim: notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
