import MoneyMatterKit
import SwiftUI

/// Creates a vehicle (and its account), or edits one's details and depreciation settings.
/// Purchase price, date, and currency are fixed once created.
struct VehicleFormSheet: View {
    enum Mode {
        case create
        case edit(Vehicle)
    }

    let mode: Mode
    /// Called with the saved vehicle before the sheet closes.
    let onSaved: (Vehicle?) async -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var currencyCode: String?
    @State private var make: String
    @State private var model: String
    @State private var trim: String
    @State private var year: Int
    @State private var vehicleClass: VehicleClass
    @State private var purchasePriceText = ""
    @State private var purchaseDate = Date()
    @State private var preset: VehicleDepreciationPreset
    @State private var customRateText: String
    @State private var salvageFloorText: String
    @State private var mileageText: String
    @State private var isSaving = false
    @State private var validationMessage: String?
    @State private var errorAlert: ErrorAlert?

    init(mode: Mode, onSaved: @escaping (Vehicle?) async -> Void) {
        self.mode = mode
        self.onSaved = onSaved
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _currencyCode = State(initialValue: nil)
            _make = State(initialValue: "")
            _model = State(initialValue: "")
            _trim = State(initialValue: "")
            _year = State(initialValue: Calendar.current.component(.year, from: Date()))
            _vehicleClass = State(initialValue: .sedan)
            _preset = State(initialValue: .classDefault)
            _customRateText = State(initialValue: "")
            _salvageFloorText = State(initialValue: "10")
            _mileageText = State(initialValue: "")
        case .edit(let vehicle):
            _name = State(initialValue: vehicle.account?.name ?? "")
            _currencyCode = State(initialValue: vehicle.account?.currencyCode)
            _make = State(initialValue: vehicle.make)
            _model = State(initialValue: vehicle.model)
            _trim = State(initialValue: vehicle.trim ?? "")
            _year = State(initialValue: vehicle.year)
            _vehicleClass = State(initialValue: vehicle.vehicleClass == .unknown ? .other : vehicle.vehicleClass)
            _preset = State(initialValue: vehicle.depreciationPreset == .unknown ? .classDefault : vehicle.depreciationPreset)
            _customRateText = State(initialValue: vehicle.customAnnualRatePct.map(EditorAmountParser.text) ?? "")
            _salvageFloorText = State(initialValue: EditorAmountParser.text(vehicle.salvageFloorPct))
            _mileageText = State(initialValue: vehicle.currentMileage.map(String.init) ?? "")
        }
    }

    private var editedVehicle: Vehicle? {
        if case .edit(let vehicle) = mode { return vehicle }
        return nil
    }

    private var maxYear: Int { Calendar.current.component(.year, from: Date()) + 1 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    if editedVehicle == nil {
                        Picker("Currency", selection: $currencyCode) {
                            Text("Choose").tag(String?.none)
                            ForEach(referenceData.userCurrencies) { currency in
                                Text(verbatim: currency.currency.map { "\(currency.currencyCode) · \($0.currency)" } ?? currency.currencyCode)
                                    .tag(String?.some(currency.currencyCode))
                            }
                        }
                    }
                }
                Section("Vehicle") {
                    TextField("Make", text: $make)
                        .textInputAutocapitalization(.words)
                    TextField("Model", text: $model)
                        .textInputAutocapitalization(.words)
                    TextField("Trim (optional)", text: $trim)
                    Stepper(value: $year, in: 1900...maxYear) {
                        LabeledContent("Year") {
                            Text(verbatim: String(year)).monospacedDigit()
                        }
                    }
                    Picker("Class", selection: $vehicleClass) {
                        ForEach(VehicleClass.allKnown, id: \.self) { option in
                            Text(VehicleLabels.vehicleClass(option)).tag(option)
                        }
                    }
                    numberRow("Mileage", text: $mileageText, prompt: "Optional", keyboard: .numberPad)
                }
                if editedVehicle == nil {
                    Section("Purchase") {
                        numberRow("Purchase Price", text: $purchasePriceText, prompt: "0", keyboard: .decimalPad)
                        DatePicker("Purchase Date", selection: $purchaseDate, in: ...Date(), displayedComponents: .date)
                    }
                }
                Section {
                    Picker("Depreciation", selection: $preset) {
                        ForEach(VehicleDepreciationPreset.allKnown, id: \.self) { option in
                            Text(VehicleLabels.preset(option)).tag(option)
                        }
                    }
                    if preset == .custom {
                        numberRow("Annual Rate (%)", text: $customRateText, prompt: "0", keyboard: .decimalPad)
                    }
                    numberRow("Salvage Floor (%)", text: $salvageFloorText, prompt: "10", keyboard: .decimalPad)
                } header: {
                    Text("Depreciation")
                } footer: {
                    Text("The value never drops below the salvage floor, a share of the purchase price.")
                }
                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(editedVehicle == nil ? "New Vehicle" : "Edit Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                    }
                }
            }
            .onAppear {
                if currencyCode == nil {
                    currencyCode = session.baseCurrency?.currencyCode ?? referenceData.userCurrencies.first?.currencyCode
                }
            }
            .errorAlert($errorAlert)
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func numberRow(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        prompt: LocalizedStringKey,
        keyboard: UIKeyboardType
    ) -> some View {
        LabeledContent(title) {
            TextField(prompt, text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validate() -> String? {
        if trimmed(name).isEmpty { return String(localized: "Enter a name.") }
        if trimmed(make).isEmpty || trimmed(model).isEmpty { return String(localized: "Enter the make and model.") }
        if editedVehicle == nil {
            if currencyCode == nil { return String(localized: "Choose a currency.") }
            guard let price = EditorAmountParser.parse(trimmed(purchasePriceText)), price > 0 else {
                return String(localized: "Enter a purchase price greater than zero.")
            }
        }
        if preset == .custom {
            guard let rate = EditorAmountParser.parse(trimmed(customRateText)), (0...100).contains(rate) else {
                return String(localized: "Enter an annual rate between 0 and 100.")
            }
        }
        guard let floor = EditorAmountParser.parse(trimmed(salvageFloorText)), (0...100).contains(floor) else {
            return String(localized: "Enter a salvage floor between 0 and 100.")
        }
        if !trimmed(mileageText).isEmpty, Int(trimmed(mileageText)).map({ $0 >= 0 }) != true {
            return String(localized: "Enter mileage as a whole number.")
        }
        return nil
    }

    private func save() async {
        if let message = validate() {
            withAnimation { validationMessage = message }
            return
        }
        validationMessage = nil
        guard let client = services.client else { return }
        isSaving = true
        defer { isSaving = false }

        let trimText = trimmed(trim)
        let customRate = preset == .custom ? EditorAmountParser.parse(trimmed(customRateText)) : nil
        let salvageFloor = EditorAmountParser.parse(trimmed(salvageFloorText))
        let mileage = Int(trimmed(mileageText))

        do {
            let saved: Vehicle?
            if let vehicle = editedVehicle {
                let request = VehicleUpdateRequest(
                    name: trimmed(name),
                    make: trimmed(make),
                    model: trimmed(model),
                    trim: trimText.isEmpty ? .clear : .set(trimText),
                    year: year,
                    vehicleClass: vehicleClass,
                    depreciationPreset: preset,
                    customAnnualRatePct: customRate.map { .set($0) } ?? .clear,
                    salvageFloorPct: salvageFloor,
                    currentMileage: mileage.map { .set($0) } ?? .clear
                )
                saved = try await client.send(Endpoints.vehicleUpdate(id: vehicle.id, request))
            } else {
                let request = VehicleCreateRequest(
                    name: trimmed(name),
                    currencyCode: currencyCode ?? "",
                    make: trimmed(make),
                    model: trimmed(model),
                    trim: trimText.isEmpty ? nil : trimText,
                    year: year,
                    vehicleClass: vehicleClass,
                    purchasePrice: EditorAmountParser.parse(trimmed(purchasePriceText)) ?? 0,
                    purchaseDate: CalendarDate(date: purchaseDate),
                    depreciationPreset: preset,
                    customAnnualRatePct: customRate,
                    salvageFloorPct: salvageFloor,
                    currentMileage: mileage
                )
                saved = try await client.send(Endpoints.vehicleCreate(request))
            }
            await onSaved(saved)
            dismiss()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}

/// Records a new estimated value for a vehicle: either set outright, or adjusted up or
/// down by an amount. Saved as a balance adjustment on the vehicle account.
struct VehicleValueOverrideSheet: View {
    let account: Account
    let onSaved: () async -> Void

    private enum Mode: Hashable {
        case setTo
        case adjustBy
    }

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .setTo
    @State private var amountText = ""
    @State private var isIncrease = false
    @State private var date = Date()
    @State private var note = ""
    @State private var isSaving = false
    @State private var validationMessage: String?
    @State private var errorAlert: ErrorAlert?

    private var target: Decimal? {
        guard let amount = EditorAmountParser.parse(amountText.trimmingCharacters(in: .whitespaces)) else { return nil }
        switch mode {
        case .setTo: return amount
        case .adjustBy: return account.currentBalance + (isIncrease ? abs(amount) : -abs(amount))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Current Value") {
                        AmountText(account.currentBalance, currencyCode: account.currencyCode)
                    }
                }
                Section {
                    Picker("Mode", selection: $mode) {
                        Text("Set Value").tag(Mode.setTo)
                        Text("Adjust By").tag(Mode.adjustBy)
                    }
                    .pickerStyle(.segmented)
                    if mode == .adjustBy {
                        Picker("Direction", selection: $isIncrease) {
                            Text("Decrease").tag(false)
                            Text("Increase").tag(true)
                        }
                    }
                    LabeledContent(mode == .setTo ? "New Value" : "Amount") {
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    if mode == .adjustBy, let target {
                        LabeledContent("New Value") {
                            AmountText(target, currencyCode: account.currencyCode)
                        }
                    }
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                } footer: {
                    Text("Depreciation continues from the new value on this date.")
                }
                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Override Value")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                    }
                }
            }
            .errorAlert($errorAlert)
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        guard let target, target >= 0 else {
            withAnimation { validationMessage = String(localized: "Enter a value of zero or more.") }
            return
        }
        validationMessage = nil
        guard let client = services.client else { return }
        isSaving = true
        defer { isSaving = false }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await client.send(Endpoints.vehicleValueOverride(
                accountId: account.id,
                VehicleValueOverrideRequest(
                    targetBalance: target,
                    note: trimmedNote.isEmpty ? nil : trimmedNote,
                    time: date
                )
            ))
            await onSaved()
            dismiss()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}

/// Display names for vehicle enums.
enum VehicleLabels {
    static func vehicleClass(_ value: VehicleClass) -> LocalizedStringResource {
        switch value {
        case .sedan: "Sedan"
        case .suv: "SUV"
        case .truck: "Truck"
        case .luxury: "Luxury"
        case .ev: "Electric"
        case .motorcycle: "Motorcycle"
        case .other, .unknown: "Other"
        }
    }

    static func preset(_ value: VehicleDepreciationPreset) -> LocalizedStringResource {
        switch value {
        case .classDefault, .unknown: "Class Default"
        case .slow: "Slow"
        case .average: "Average"
        case .fast: "Fast"
        case .custom: "Custom Rate"
        }
    }
}
