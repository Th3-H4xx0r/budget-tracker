import MoneyMatterKit
import SwiftUI

/// Vehicle accounts: each with its current estimated value and how much it has lost
/// since purchase. Mirrors the web Accounts page's vehicles section.
struct VehiclesScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData

    @State private var state: LoadState<[Vehicle]> = .idle
    @State private var isCreating = false
    @State private var pendingDelete: Vehicle?
    @State private var alert: ErrorAlert?

    var body: some View {
        content
            .navigationTitle("Vehicles")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Label("Add Vehicle", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isCreating) {
                VehicleFormSheet(mode: .create) { _ in
                    await reload()
                    await referenceData.refreshAccounts()
                }
            }
            .confirmationDialog(
                "Delete this vehicle?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { vehicle in
                Button("Delete Vehicle", role: .destructive) {
                    Task { await delete(vehicle) }
                }
            } message: { _ in
                Text("The vehicle account and its value history will be removed.")
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
            List {
                ForEach(VehiclesScreen.placeholders) { vehicle in
                    VehicleListRow(vehicle: vehicle)
                }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await reload() }
        case .loaded(let vehicles) where vehicles.isEmpty:
            ContentUnavailableView {
                Label("No Vehicles", systemImage: "car")
            } description: {
                Text("Track a car or motorcycle and watch its estimated value depreciate over time.")
            } actions: {
                Button("Add Vehicle") { isCreating = true }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let vehicles):
            List {
                Section {
                    VehicleTotalsHeader(vehicles: vehicles)
                }
                Section {
                    ForEach(vehicles) { vehicle in
                        NavigationLink {
                            VehicleDetailScreen(vehicleID: vehicle.id) {
                                await reload()
                            }
                        } label: {
                            VehicleListRow(vehicle: vehicle)
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                pendingDelete = vehicle
                            }
                        }
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                pendingDelete = vehicle
                            }
                        }
                    }
                }
            }
        }
    }

    private func reload() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            let vehicles = try await client.send(Endpoints.vehicles())
            state = .loaded(vehicles.filter { $0.account != nil })
        } catch {
            if state.value == nil { state = .failed(APIError(error)) }
        }
    }

    private func delete(_ vehicle: Vehicle) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.vehicleDelete(id: vehicle.id))
            if case .loaded(let vehicles) = state {
                state = .loaded(vehicles.filter { $0.id != vehicle.id })
            }
            referenceData.removeAccount(id: vehicle.accountId)
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private static let placeholders: [Vehicle] = (0..<3).map { index in
        Vehicle(
            id: "placeholder-\(index)",
            accountId: "placeholder-\(index)",
            make: "Vehicle make",
            model: "Model",
            year: 2020,
            vehicleClass: .sedan,
            purchasePrice: 20000,
            purchaseDate: CalendarDate(year: 2020, month: 1, day: 1)
        )
    }
}

/// Total value per currency across all vehicles.
private struct VehicleTotalsHeader: View {
    let vehicles: [Vehicle]

    private var totals: [(code: String, value: Decimal)] {
        var sums: [String: Decimal] = [:]
        for vehicle in vehicles {
            guard let account = vehicle.account else { continue }
            sums[account.currencyCode, default: 0] += account.currentBalance
        }
        return sums.sorted { $0.key < $1.key }.map { (code: $0.key, value: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Total Value")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(totals, id: \.code) { total in
                AmountText(total.value, currencyCode: total.code)
                    .font(.title2.weight(.semibold))
            }
            Text("^[\(vehicles.count) vehicle](inflect: true)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// One vehicle: name, year/make/model, current value, and the change since purchase.
struct VehicleListRow: View {
    let vehicle: Vehicle

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: VehicleListRow.symbol(for: vehicle.vehicleClass))
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(.tint.opacity(0.12), in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(vehicle.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(vehicle.currentValue, currencyCode: vehicle.account?.currencyCode ?? "USD")
                    .font(.body.weight(.semibold))
                VehicleChangeLabel(vehicle: vehicle)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    static func symbol(for vehicleClass: VehicleClass) -> String {
        switch vehicleClass {
        case .motorcycle: "motorcycle"
        case .truck: "truck.pickup.side"
        case .suv: "suv.side"
        case .ev: "bolt.car"
        default: "car"
        }
    }
}

/// `▼ 12.3%` in the expense colour when the vehicle lost value, green when it gained.
struct VehicleChangeLabel: View {
    let vehicle: Vehicle

    var body: some View {
        let isDown = vehicle.depreciationAmount >= 0
        let percent = abs(NSDecimalNumber(decimal: vehicle.depreciationPercent).doubleValue)
        Label {
            Text(percent / 100, format: .percent.precision(.fractionLength(1)))
                .monospacedDigit()
        } icon: {
            Image(systemName: isDown ? "arrow.down.right" : "arrow.up.right")
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(isDown ? Color.secondary : Color.green)
        .accessibilityLabel(isDown
            ? Text("Down \(percent / 100, format: .percent.precision(.fractionLength(1))) since purchase")
            : Text("Up \(percent / 100, format: .percent.precision(.fractionLength(1))) since purchase"))
    }
}
