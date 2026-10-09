import Charts
import MoneyMatterKit
import SwiftUI

/// One vehicle: current value and change since purchase, purchase / depreciation / 5-year
/// projection figures, the depreciation curve, details, and the value-override history.
/// Mirrors the web `vehicle-details` page.
struct VehicleDetailScreen: View {
    let vehicleID: String
    /// Lets the list refresh after an edit, override, or delete.
    var onChange: () async -> Void = {}

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var state: LoadState<Vehicle> = .idle
    @State private var overrides: LoadState<[Transaction]> = .idle
    @State private var isEditing = false
    @State private var isOverriding = false
    @State private var isConfirmingDelete = false
    @State private var pendingOverrideDelete: Transaction?
    @State private var alert: ErrorAlert?

    private static let projectionHorizonMonths = 144
    private static let fiveYearMonths = 60

    var body: some View {
        content
            .navigationTitle(state.value?.displayName ?? String(localized: "Vehicle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let vehicle = state.value, vehicle.account != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Override Value", systemImage: "slider.horizontal.3") { isOverriding = true }
                            Button("Edit", systemImage: "pencil") { isEditing = true }
                            Divider()
                            Button("Delete Vehicle", systemImage: "trash", role: .destructive) {
                                isConfirmingDelete = true
                            }
                        } label: {
                            Label("Actions", systemImage: "ellipsis")
                        }
                    }
                }
            }
            .sheet(isPresented: $isEditing) {
                if let vehicle = state.value {
                    VehicleFormSheet(mode: .edit(vehicle)) { saved in
                        if let saved { state = .loaded(saved) }
                        await reload()
                        await referenceData.refreshAccounts()
                        await onChange()
                    }
                }
            }
            .sheet(isPresented: $isOverriding) {
                if let account = state.value?.account {
                    VehicleValueOverrideSheet(account: account) {
                        await reload()
                        await referenceData.refreshAccounts()
                        await onChange()
                    }
                }
            }
            .confirmationDialog("Delete this vehicle?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Vehicle", role: .destructive) {
                    Task { await deleteVehicle() }
                }
            } message: {
                Text("The vehicle account and its value history will be removed.")
            }
            .confirmationDialog(
                "Delete this override?",
                isPresented: Binding(
                    get: { pendingOverrideDelete != nil },
                    set: { if !$0 { pendingOverrideDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingOverrideDelete
            ) { transaction in
                Button("Delete Override", role: .destructive) {
                    Task { await deleteOverride(transaction) }
                }
            } message: { _ in
                Text("The vehicle's value is recalculated without this override.")
            }
            .errorAlert($alert)
            .task {
                if case .idle = state { await reload() }
            }
            .refreshable { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ScrollView {
                VStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 20).fill(.quaternary).frame(height: 140)
                    RoundedRectangle(cornerRadius: 20).fill(.quaternary).frame(height: 90)
                    RoundedRectangle(cornerRadius: 20).fill(.quaternary).frame(height: 260)
                }
                .padding()
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await reload() }
        case .loaded(let vehicle):
            if let account = vehicle.account {
                loaded(vehicle, account: account)
            } else {
                ContentUnavailableView {
                    Label("Vehicle Not Found", systemImage: "car")
                } description: {
                    Text("This vehicle may have been deleted.")
                } actions: {
                    Button("Back") { dismiss() }
                }
            }
        }
    }

    private func loaded(_ vehicle: Vehicle, account: Account) -> some View {
        let calculator = VehicleDetailFigures(
            vehicle: vehicle,
            account: account,
            baseCurrencyCode: session.baseCurrency?.currencyCode,
            horizonMonths: Self.projectionHorizonMonths,
            fiveYearMonths: Self.fiveYearMonths
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero(vehicle, figures: calculator)
                kpis(vehicle, figures: calculator)
                chartCard(figures: calculator)
                detailsCard(vehicle, figures: calculator)
                overridesCard(account: account)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func hero(_ vehicle: Vehicle, figures: VehicleDetailFigures) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: VehicleListRow.symbol(for: vehicle.vehicleClass))
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .background(.tint.opacity(0.12), in: .rect(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(VehicleLabels.vehicleClass(vehicle.vehicleClass))
                        .font(.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(vehicle.displayName)
                        .font(.title2.weight(.semibold))
                    Text(vehicle.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Value")
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                AmountText(figures.currentValue, currencyCode: figures.currencyCode)
                    .font(.largeTitle.weight(.semibold))
                HStack(spacing: 6) {
                    AmountText(abs(vehicle.depreciationAmount), currencyCode: figures.currencyCode)
                    VehicleChangeLabel(vehicle: vehicle)
                }
                .font(.subheadline)
                if let ref = figures.refCurrentValue, let base = figures.baseCurrencyCode {
                    Text("≈ \(MoneyFormat.string(ref, currencyCode: base))")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text("Since \(vehicle.purchaseDate.startDate().formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private func kpis(_ vehicle: Vehicle, figures: VehicleDetailFigures) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { kpiTiles(vehicle, figures: figures) }
            VStack(spacing: 12) { kpiTiles(vehicle, figures: figures) }
        }
    }

    @ViewBuilder
    private func kpiTiles(_ vehicle: Vehicle, figures: VehicleDetailFigures) -> some View {
        VehicleKPITile(title: "Purchase Price", amount: vehicle.purchasePrice, currencyCode: figures.currencyCode) {
            Text(vehicle.purchaseDate.startDate().formatted(date: .abbreviated, time: .omitted))
        }
        VehicleKPITile(title: "Total Depreciation", amount: abs(vehicle.depreciationAmount), currencyCode: figures.currencyCode) {
            Text("Over \(figures.ownedYears, format: .number.precision(.fractionLength(1))) years")
        }
        VehicleKPITile(title: "In 5 Years", amount: figures.fiveYearValue, currencyCode: figures.currencyCode) {
            Text("\(figures.fiveYearLossPercent / 100, format: .percent.precision(.fractionLength(1))) less than today")
        }
    }

    private func chartCard(figures: VehicleDetailFigures) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Depreciation")
            Text("Estimated value over time, projected forward.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Chart {
                ForEach(Array(figures.timeline.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .interpolationMethod(.linear)
                        .foregroundStyle(point.date <= figures.today ? Color.accentColor : Color.secondary)
                }
                RuleMark(y: .value("Salvage floor", figures.salvageFloor))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
                RuleMark(x: .value("Today", figures.today))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.tertiary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("Today").font(.caption2).foregroundStyle(.secondary)
                    }
                if let anchor = figures.overrideAnchor {
                    PointMark(x: .value("Date", anchor.date), y: .value("Value", anchor.value))
                        .symbolSize(60)
                        .foregroundStyle(.orange)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(verbatim: MoneyFormat.compactString(Decimal(amount), currencyCode: figures.currencyCode))
                        }
                    }
                }
            }
            .frame(height: 240)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Depreciation chart")
            .accessibilityValue(Text("Value falls from \(MoneyFormat.string(figures.purchaseValue, currencyCode: figures.currencyCode)) at purchase to \(MoneyFormat.string(figures.currentValue, currencyCode: figures.currencyCode)) today, and about \(MoneyFormat.string(figures.fiveYearValue, currencyCode: figures.currencyCode)) in five years."))
        }
        .cardStyle()
    }

    private func detailsCard(_ vehicle: Vehicle, figures: VehicleDetailFigures) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader("Details")
            LabeledContent("Class") { Text(VehicleLabels.vehicleClass(vehicle.vehicleClass)) }
            LabeledContent("Year") { Text(verbatim: String(vehicle.year)) }
            if let trim = vehicle.trim, !trim.isEmpty {
                LabeledContent("Trim") { Text(verbatim: trim) }
            }
            if let mileage = vehicle.currentMileage {
                LabeledContent("Mileage") { Text(mileage, format: .number).monospacedDigit() }
            }
            Divider()
            LabeledContent("Depreciation") { Text(VehicleLabels.preset(vehicle.depreciationPreset)) }
            if let rate = vehicle.customAnnualRatePct {
                LabeledContent("Annual Rate") {
                    Text(NSDecimalNumber(decimal: rate).doubleValue / 100, format: .percent).monospacedDigit()
                }
            }
            LabeledContent("Salvage Floor") {
                VStack(alignment: .trailing) {
                    Text(NSDecimalNumber(decimal: vehicle.salvageFloorPct).doubleValue / 100, format: .percent)
                        .monospacedDigit()
                    Text(verbatim: "≈ " + MoneyFormat.string(Decimal(figures.salvageFloor), currencyCode: figures.currencyCode))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if let anchor = vehicle.valueAnchor {
                LabeledContent("Last Override") {
                    VStack(alignment: .trailing) {
                        AmountText(anchor, currencyCode: figures.currencyCode)
                        Text((vehicle.valueAnchorDate ?? vehicle.purchaseDate).startDate().formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func overridesCard(account: Account) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Value Overrides") {
                Button {
                    isOverriding = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("Override Value")
            }
            switch overrides {
            case .idle, .loading:
                Text("Loading overrides")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .redactedWhileLoading(true)
            case .failed:
                InlineRetryView(String(localized: "Couldn't load overrides.")) { await loadOverrides(accountID: account.id) }
            case .loaded(let rows) where rows.isEmpty:
                Text("No overrides yet. The value follows the depreciation curve.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .loaded(let rows):
                ForEach(rows) { transaction in
                    HStack {
                        Image(systemName: transaction.transactionType == .income ? "arrow.up.right" : "arrow.down.right")
                            .foregroundStyle(transaction.transactionType == .income ? Color.green : Color.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            AmountText(
                                transaction.amount,
                                currencyCode: account.currencyCode,
                                style: transaction.transactionType == .income ? .income : .expense,
                                showsPlusSign: transaction.transactionType == .income
                            )
                            .font(.subheadline.weight(.medium))
                            HStack(spacing: 4) {
                                Text(transaction.time.formatted(date: .abbreviated, time: .omitted))
                                if let note = transaction.note, !note.isEmpty {
                                    Text(verbatim: "· \(note)").lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            pendingOverrideDelete = transaction
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete Override")
                    }
                    .frame(minHeight: 44)
                }
            }
        }
        .cardStyle()
    }

    private func reload() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            guard let vehicle = try await client.send(Endpoints.vehicle(id: vehicleID)) else {
                state = .failed(.notFound(message: nil))
                return
            }
            state = .loaded(vehicle)
            await loadOverrides(accountID: vehicle.accountId)
        } catch {
            if state.value == nil { state = .failed(APIError(error)) }
        }
    }

    private func loadOverrides(accountID: String) async {
        guard let client = services.client else { return }
        if overrides.value == nil { overrides = .loading }
        do {
            overrides = .loaded(try await client.send(Endpoints.vehicleValueOverrides(accountId: accountID)))
        } catch {
            if overrides.value == nil { overrides = .failed(APIError(error)) }
        }
    }

    private func deleteVehicle() async {
        guard let client = services.client, let vehicle = state.value else { return }
        do {
            _ = try await client.send(Endpoints.vehicleDelete(id: vehicle.id))
            referenceData.removeAccount(id: vehicle.accountId)
            await onChange()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func deleteOverride(_ transaction: Transaction) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.deleteTransaction(id: transaction.id))
            await reload()
            await referenceData.refreshAccounts()
            await onChange()
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

/// A headline figure with a caption.
private struct VehicleKPITile<Caption: View>: View {
    let title: LocalizedStringKey
    let amount: Decimal
    let currencyCode: String
    @ViewBuilder var caption: Caption

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            AmountText(amount, currencyCode: currencyCode)
                .font(.title3.weight(.semibold))
            caption
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

/// The figures the detail screen derives from a vehicle and its account.
private struct VehicleDetailFigures {
    let currencyCode: String
    let baseCurrencyCode: String?
    let currentValue: Decimal
    let refCurrentValue: Decimal?
    let purchaseValue: Decimal
    let today: Date
    let timeline: [VehicleDepreciationPoint]
    let overrideAnchor: VehicleDepreciationPoint?
    let salvageFloor: Double
    let ownedYears: Double
    let fiveYearValue: Decimal
    let fiveYearLossPercent: Double

    init(vehicle: Vehicle, account: Account, baseCurrencyCode: String?, horizonMonths: Int, fiveYearMonths: Int) {
        let calendar = Calendar.current
        currencyCode = account.currencyCode
        currentValue = account.currentBalance
        purchaseValue = vehicle.purchasePrice
        today = Date()
        if let base = baseCurrencyCode, base != account.currencyCode, account.currentBalance != 0 {
            self.baseCurrencyCode = base
            refCurrentValue = account.refCurrentBalance
        } else {
            self.baseCurrencyCode = nil
            refCurrentValue = nil
        }
        let purchase = NSDecimalNumber(decimal: vehicle.purchasePrice).doubleValue
        let purchaseDate = vehicle.purchaseDate.startDate(in: calendar)
        if let anchor = vehicle.valueAnchor, let anchorDate = vehicle.valueAnchorDate {
            overrideAnchor = VehicleDepreciationPoint(
                date: anchorDate.startDate(in: calendar),
                value: NSDecimalNumber(decimal: anchor).doubleValue
            )
        } else {
            overrideAnchor = nil
        }
        let salvagePct = NSDecimalNumber(decimal: vehicle.salvageFloorPct).doubleValue
        salvageFloor = purchase * salvagePct / 100
        timeline = VehicleDepreciation.timeline(
            purchaseValue: purchase,
            purchaseDate: purchaseDate,
            override: overrideAnchor,
            vehicleClass: vehicle.vehicleClass,
            preset: vehicle.depreciationPreset,
            customAnnualRatePct: vehicle.customAnnualRatePct.map { NSDecimalNumber(decimal: $0).doubleValue },
            salvageFloorPct: salvagePct,
            monthsHorizon: horizonMonths,
            calendar: calendar
        )
        let days = calendar.dateComponents([.day], from: purchaseDate, to: today).day ?? 0
        ownedYears = max(0, Double(days) / 365)
        let fiveYearsOut = calendar.date(byAdding: .month, value: fiveYearMonths, to: today) ?? today
        let projected = VehicleDepreciation.projectedValue(in: timeline, at: fiveYearsOut)
        fiveYearValue = Decimal(projected)
        let current = NSDecimalNumber(decimal: account.currentBalance).doubleValue
        fiveYearLossPercent = current == 0 ? 0 : (current - projected) / current * 100
    }
}
