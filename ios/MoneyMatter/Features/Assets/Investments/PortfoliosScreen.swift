import MoneyMatterKit
import SwiftUI

/// Investment portfolios with their current value, plus create, edit and move-to-trash.
struct PortfoliosScreen: View {
    @Environment(AppServices.self) private var services
    @State private var state: LoadState<[Portfolio]> = .idle
    @State private var summaries: [String: PortfolioSummary] = [:]
    @State private var isCreating = false
    @State private var editing: Portfolio?
    @State private var pendingDelete: Portfolio?
    @State private var alert: ErrorAlert?

    var body: some View {
        content
            .navigationTitle("Investments")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        PortfolioTrashScreen { Task { await load() } }
                    } label: {
                        Label("Recently Deleted", systemImage: "trash")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Label("New Portfolio", systemImage: "plus")
                    }
                }
            }
            .task {
                if state.value == nil { await load() }
            }
            .sheet(isPresented: $isCreating) {
                PortfolioFormSheet(portfolio: nil) { Task { await load() } }
            }
            .sheet(item: $editing) { portfolio in
                PortfolioFormSheet(portfolio: portfolio) { Task { await load() } }
            }
            .confirmationDialog(
                "Delete Portfolio?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { portfolio in
                Button("Move to Recently Deleted", role: .destructive) {
                    Task { await delete(portfolio) }
                }
            } message: { _ in
                Text("The portfolio stays in Recently Deleted for 30 days, where you can restore it.")
            }
            .errorAlert($alert)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let portfolios) where portfolios.isEmpty:
            ContentUnavailableView {
                Label("No Portfolios", systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text("Create a portfolio to track stocks, crypto and cash in one place.")
            } actions: {
                Button("New Portfolio") { isCreating = true }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let portfolios):
            List {
                ForEach(portfolios) { portfolio in
                    NavigationLink {
                        PortfolioDetailScreen(portfolio: portfolio) { Task { await load() } }
                    } label: {
                        PortfolioListRow(portfolio: portfolio, summary: summaries[portfolio.id])
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = portfolio
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            editing = portfolio
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            editing = portfolio
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            pendingDelete = portfolio
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .refreshable { await load() }
        case .idle, .loading:
            List {
                ForEach(0..<3, id: \.self) { _ in
                    PortfolioListRow(portfolio: Portfolio(id: "placeholder", name: "Portfolio name"), summary: nil)
                }
            }
            .redactedWhileLoading(true)
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let portfolios = try await services.investmentsSend(Endpoints.portfolios())
            state = .loaded(portfolios)
            await loadSummaries(for: portfolios)
        } catch {
            if state.value == nil {
                state = .failed(APIError(error))
            } else {
                alert = ErrorAlert(error)
            }
        }
    }

    private func loadSummaries(for portfolios: [Portfolio]) async {
        guard let client = services.client else { return }
        let results = await withTaskGroup(of: (String, PortfolioSummary?).self) { group in
            for portfolio in portfolios {
                group.addTask {
                    (portfolio.id, try? await client.send(Endpoints.portfolioSummary(id: portfolio.id)))
                }
            }
            var collected: [String: PortfolioSummary] = [:]
            for await (id, summary) in group {
                if let summary { collected[id] = summary }
            }
            return collected
        }
        summaries = results
    }

    private func delete(_ portfolio: Portfolio) async {
        do {
            _ = try await services.investmentsSend(Endpoints.portfolioDelete(id: portfolio.id))
            await load()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

private struct PortfolioListRow: View {
    let portfolio: Portfolio
    let summary: PortfolioSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(portfolio.name)
                    .font(.headline)
                Spacer()
                if !portfolio.isEnabled {
                    Label("Hidden", systemImage: "eye.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(portfolio.portfolioType.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let summary {
                AmountText(summary.totalPortfolioValue, currencyCode: summary.currencyCode)
                    .font(.title3.weight(.semibold))
                HStack {
                    Text("Cost basis \(MoneyFormat.string(summary.totalCostBasis, currencyCode: summary.currencyCode))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    PortfolioGainText(
                        value: summary.unrealizedGainValue,
                        percent: summary.unrealizedGainPercent,
                        currencyCode: summary.currencyCode
                    )
                }
                .font(.footnote)
            } else {
                Text(verbatim: "$00,000.00")
                    .font(.title3.weight(.semibold))
                    .redacted(reason: .placeholder)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Create or edit a portfolio.
struct PortfolioFormSheet: View {
    let portfolio: Portfolio?
    let onSaved: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var portfolioType: PortfolioType = .investment
    @State private var details = ""
    @State private var usesBaseCurrency = true
    @State private var displayCurrencyCode: String?
    @State private var isEnabled = true
    @State private var isSaving = false
    @State private var alert: ErrorAlert?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $portfolioType) {
                        ForEach(PortfolioType.selectable, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    TextField("Description", text: $details, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Toggle("Use Base Currency", isOn: $usesBaseCurrency)
                    if !usesBaseCurrency {
                        CurrencyPickerLink(
                            title: "Display Currency",
                            currencies: referenceData.userCurrencies.compactMap(\.currency),
                            selection: $displayCurrencyCode
                        )
                    }
                } footer: {
                    Text("Totals and gains for this portfolio are shown in this currency.")
                }
                Section {
                    Toggle("Visible", isOn: $isEnabled)
                }
            }
            .navigationTitle(portfolio == nil ? "New Portfolio" : "Edit Portfolio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($alert)
            .onAppear(perform: populate)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 100 && (usesBaseCurrency || displayCurrencyCode != nil)
    }

    private func populate() {
        guard let portfolio else { return }
        name = portfolio.name
        portfolioType = portfolio.portfolioType == .unknown ? .other : portfolio.portfolioType
        details = portfolio.description ?? ""
        usesBaseCurrency = portfolio.displayCurrencyCode == nil
        displayCurrencyCode = portfolio.displayCurrencyCode
        isEnabled = portfolio.isEnabled
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let currency = usesBaseCurrency ? nil : displayCurrencyCode
        do {
            if let portfolio {
                let request = PortfolioUpdateRequest(
                    name: trimmedName,
                    portfolioType: portfolioType,
                    description: trimmedDetails.isEmpty ? .clear : .set(trimmedDetails),
                    displayCurrencyCode: currency.map { .set($0) } ?? .clear,
                    isEnabled: isEnabled
                )
                _ = try await services.investmentsSend(Endpoints.portfolioUpdate(id: portfolio.id, request))
            } else {
                let request = PortfolioCreateRequest(
                    name: trimmedName,
                    portfolioType: portfolioType,
                    description: trimmedDetails.isEmpty ? nil : trimmedDetails,
                    displayCurrencyCode: currency,
                    isEnabled: isEnabled
                )
                _ = try await services.investmentsSend(Endpoints.portfolioCreate(request))
            }
            onSaved()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// Deleted portfolios, kept for 30 days: restore or delete for good.
struct PortfolioTrashScreen: View {
    let onRestore: () -> Void

    @Environment(AppServices.self) private var services
    @State private var state: LoadState<[Portfolio]> = .idle
    @State private var pendingPurge: Portfolio?
    @State private var alert: ErrorAlert?

    private static let retentionDays = 30

    var body: some View {
        content
            .navigationTitle("Recently Deleted")
            .task {
                if state.value == nil { await load() }
            }
            .confirmationDialog(
                "Delete Permanently?",
                isPresented: Binding(get: { pendingPurge != nil }, set: { if !$0 { pendingPurge = nil } }),
                titleVisibility: .visible,
                presenting: pendingPurge
            ) { portfolio in
                Button("Delete Permanently", role: .destructive) {
                    Task { await purge(portfolio) }
                }
            } message: { _ in
                Text("The portfolio, its holdings and its transactions are deleted. This can't be undone.")
            }
            .errorAlert($alert)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let portfolios) where portfolios.isEmpty:
            ContentUnavailableView {
                Label("No Deleted Portfolios", systemImage: "trash")
            } description: {
                Text("Deleted portfolios stay here for 30 days.")
            } actions: {
                Button("Refresh") { Task { await load() } }
            }
        case .loaded(let portfolios):
            List {
                Section {
                    ForEach(portfolios) { portfolio in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(portfolio.name)
                                .font(.headline)
                            if let remaining = daysRemaining(for: portfolio) {
                                Text("Deleted permanently in \(remaining) days")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                Task { await restore(portfolio) }
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingPurge = portfolio
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                Task { await restore(portfolio) }
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            Button(role: .destructive) {
                                pendingPurge = portfolio
                            } label: {
                                Label("Delete Permanently", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    Text("Swipe right to restore a portfolio.")
                }
            }
            .refreshable { await load() }
        case .idle, .loading:
            List {
                ForEach(0..<3, id: \.self) { _ in
                    Text(verbatim: "Deleted portfolio")
                }
            }
            .redactedWhileLoading(true)
        }
    }

    private func daysRemaining(for portfolio: Portfolio) -> Int? {
        guard let deletedAt = portfolio.deletedAt,
              let purgeDate = Calendar.current.date(byAdding: .day, value: Self.retentionDays, to: deletedAt)
        else { return nil }
        let days = Calendar.current.dateComponents([.day], from: .now, to: purgeDate).day ?? 0
        return max(0, days)
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await services.investmentsSend(Endpoints.portfolios(onlyDeleted: true)))
        } catch {
            if state.value == nil { state = .failed(APIError(error)) } else { alert = ErrorAlert(error) }
        }
    }

    private func restore(_ portfolio: Portfolio) async {
        do {
            _ = try await services.investmentsSend(Endpoints.portfolioRestore(id: portfolio.id))
            onRestore()
            await load()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func purge(_ portfolio: Portfolio) async {
        do {
            _ = try await services.investmentsSend(Endpoints.portfolioDelete(id: portfolio.id, force: true))
            await load()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}
