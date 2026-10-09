import MoneyMatterKit
import SwiftUI

/// Creates or edits a deal. Picking a platform on a new deal fills in its default fees.
struct VentureDealFormSheet: View {
    let deal: VentureDeal?
    let onSaved: (VentureDeal) async -> Void

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var platforms: [VenturePlatform] = []
    @State private var name: String
    @State private var platformID: String?
    @State private var currencyCode: String?
    @State private var principalText: String
    @State private var entryFeeText: String
    @State private var investmentDate: Date
    @State private var hasExpectedExit: Bool
    @State private var expectedExitDate: Date
    @State private var spvSubtype: VentureSPVSubtype
    @State private var targetCompany: String
    @State private var entryFeePctText: String
    @State private var mgmtFeePctText: String
    @State private var carryPctText: String
    @State private var hurdlePctText: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var validationMessage: String?
    @State private var errorAlert: ErrorAlert?

    init(deal: VentureDeal?, onSaved: @escaping (VentureDeal) async -> Void) {
        self.deal = deal
        self.onSaved = onSaved
        _name = State(initialValue: deal?.name ?? "")
        _platformID = State(initialValue: deal?.platformId)
        _currencyCode = State(initialValue: deal?.currencyCode)
        _principalText = State(initialValue: deal.map { EditorAmountParser.text($0.principal) } ?? "")
        _entryFeeText = State(initialValue: deal.map { EditorAmountParser.text($0.entryFee) } ?? "")
        _investmentDate = State(initialValue: deal?.investmentDate.startDate() ?? Date())
        _hasExpectedExit = State(initialValue: deal?.expectedExitDate != nil)
        _expectedExitDate = State(initialValue: deal?.expectedExitDate?.startDate()
            ?? Calendar.current.date(byAdding: .year, value: 5, to: Date()) ?? Date())
        _spvSubtype = State(initialValue: deal?.spvSubtype ?? .multiCompany)
        _targetCompany = State(initialValue: deal?.targetCompany ?? "")
        _entryFeePctText = State(initialValue: VentureFormat.percentText(deal?.entryFeePct ?? 0))
        _mgmtFeePctText = State(initialValue: VentureFormat.percentText(deal?.mgmtFeePct ?? 0))
        _carryPctText = State(initialValue: VentureFormat.percentText(deal?.carryPct ?? Decimal(string: "0.2")!))
        _hurdlePctText = State(initialValue: VentureFormat.percentText(deal?.hurdlePct ?? 0))
        _notes = State(initialValue: deal?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Deal Name", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Platform", selection: $platformID) {
                        Text("None").tag(String?.none)
                        ForEach(platforms) { platform in
                            Text(verbatim: platform.name).tag(String?.some(platform.id))
                        }
                    }
                    Picker("Structure", selection: $spvSubtype) {
                        ForEach(VentureSPVSubtype.allKnown, id: \.self) { subtype in
                            Text(VentureLabels.spvSubtype(subtype)).tag(subtype)
                        }
                    }
                    TextField("Target Company (optional)", text: $targetCompany)
                }
                Section("Investment") {
                    Picker("Currency", selection: $currencyCode) {
                        Text("Choose").tag(String?.none)
                        ForEach(referenceData.userCurrencies) { currency in
                            Text(verbatim: currency.currencyCode).tag(String?.some(currency.currencyCode))
                        }
                    }
                    VentureNumberField(title: "Principal", text: $principalText)
                    VentureNumberField(title: "Entry Fee", text: $entryFeeText, prompt: "Auto")
                    DatePicker("Investment Date", selection: $investmentDate, displayedComponents: .date)
                    Toggle("Expected Exit", isOn: $hasExpectedExit.animation())
                    if hasExpectedExit {
                        DatePicker("Exit Date", selection: $expectedExitDate, displayedComponents: .date)
                    }
                }
                Section {
                    VentureNumberField(title: "Entry Fee (%)", text: $entryFeePctText)
                    VentureNumberField(title: "Management Fee (%)", text: $mgmtFeePctText)
                    VentureNumberField(title: "Carry (%)", text: $carryPctText)
                    VentureNumberField(title: "Hurdle (%)", text: $hurdlePctText)
                } header: {
                    Text("Fees")
                } footer: {
                    Text("Leave the entry fee amount empty to derive it from the percentage.")
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(deal == nil ? "New Deal" : "Edit Deal")
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
                    }
                }
            }
            .onChange(of: platformID) { _, newValue in
                guard deal == nil, let platform = platforms.first(where: { $0.id == newValue }) else { return }
                entryFeePctText = VentureFormat.percentText(platform.defaultEntryFeePct)
                mgmtFeePctText = VentureFormat.percentText(platform.defaultMgmtFeePct)
                carryPctText = VentureFormat.percentText(platform.defaultCarryPct)
                hurdlePctText = VentureFormat.percentText(platform.defaultHurdlePct)
            }
            .task {
                if currencyCode == nil {
                    currencyCode = session.baseCurrency?.currencyCode ?? referenceData.userCurrencies.first?.currencyCode
                }
                if let client = services.client {
                    platforms = (try? await client.send(Endpoints.venturePlatforms())) ?? []
                }
            }
            .errorAlert($errorAlert)
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return fail(String(localized: "Enter a deal name.")) }
        guard let currencyCode else { return fail(String(localized: "Choose a currency.")) }
        guard let principal = EditorAmountParser.parse(principalText.trimmingCharacters(in: .whitespaces)), principal > 0 else {
            return fail(String(localized: "Enter a principal greater than zero."))
        }
        let entryFeeTrimmed = entryFeeText.trimmingCharacters(in: .whitespaces)
        let entryFee = entryFeeTrimmed.isEmpty ? nil : EditorAmountParser.parse(entryFeeTrimmed)
        if !entryFeeTrimmed.isEmpty, entryFee == nil { return fail(String(localized: "Enter the entry fee as a number.")) }
        guard let entryPct = VentureFormat.fraction(fromPercentText: entryFeePctText),
              let mgmtPct = VentureFormat.fraction(fromPercentText: mgmtFeePctText),
              let carryPct = VentureFormat.fraction(fromPercentText: carryPctText),
              let hurdlePct = VentureFormat.fraction(fromPercentText: hurdlePctText)
        else { return fail(String(localized: "Enter fee percentages between 0 and 100.")) }
        guard let client = services.client else { return }

        let company = targetCompany.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = VentureDealRequest(
            name: trimmedName,
            currencyCode: currencyCode,
            principal: principal,
            investmentDate: CalendarDate(date: investmentDate),
            platformId: platformID,
            spvSubtype: spvSubtype,
            targetCompany: company.isEmpty ? nil : company,
            entryFeePct: entryPct,
            entryFee: entryFee,
            mgmtFeePct: mgmtPct,
            carryPct: carryPct,
            hurdlePct: hurdlePct,
            expectedExitDate: hasExpectedExit ? CalendarDate(date: expectedExitDate) : nil,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
        validationMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let saved: VentureDeal = if let deal {
                try await client.send(Endpoints.ventureDealUpdate(id: deal.id, request))
            } else {
                try await client.send(Endpoints.ventureDealCreate(request))
            }
            await onSaved(saved)
            dismiss()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func fail(_ message: String) {
        withAnimation { validationMessage = message }
    }
}

/// Adds an event to a deal, or edits an existing one's date, amounts, and notes.
/// Events with linked transactions are created on the web, where transactions can be picked.
struct VentureEventFormSheet: View {
    let deal: VentureDeal
    let event: VentureEvent?
    let hasInitialInvestment: Bool
    let onSaved: () async -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var type: VentureEventType
    @State private var date: Date
    @State private var grossText: String
    @State private var navText: String
    @State private var overridesCarry = false
    @State private var gpCarryText = ""
    @State private var lpNetText = ""
    @State private var notes: String
    @State private var isSaving = false
    @State private var validationMessage: String?
    @State private var errorAlert: ErrorAlert?

    init(deal: VentureDeal, event: VentureEvent?, hasInitialInvestment: Bool, onSaved: @escaping () async -> Void) {
        self.deal = deal
        self.event = event
        self.hasInitialInvestment = hasInitialInvestment
        self.onSaved = onSaved
        _type = State(initialValue: event?.type ?? (hasInitialInvestment ? .distribution : .initialInvestment))
        _date = State(initialValue: event?.eventDate.startDate() ?? Date())
        _grossText = State(initialValue: event?.grossAmount.map(EditorAmountParser.text) ?? "")
        _navText = State(initialValue: event?.navAfter.map(EditorAmountParser.text) ?? "")
        _notes = State(initialValue: event?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if event == nil {
                        Picker("Type", selection: $type) {
                            ForEach(VentureEventType.creatable(hasInitialInvestment: hasInitialInvestment), id: \.self) { option in
                                Text(VentureLabels.eventType(option)).tag(option)
                            }
                        }
                    } else {
                        LabeledContent("Type") { Text(VentureLabels.eventType(type)) }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                Section {
                    if type.requiresGrossAmount {
                        VentureNumberField(title: "Gross Amount", text: $grossText)
                    }
                    if type.requiresNavAfter {
                        VentureNumberField(title: "NAV After", text: $navText)
                    }
                    if type == .initialInvestment {
                        LabeledContent("Amount") {
                            AmountText(deal.principal + deal.entryFee, currencyCode: deal.currencyCode)
                        }
                    }
                } footer: {
                    if type == .initialInvestment {
                        Text("The initial investment uses the deal's principal and entry fee.")
                    }
                }
                if event == nil, !type.isNavOnly {
                    Section {
                        LabeledContent("Cash Flow") { Text(VentureLabels.cashFlow(.outOfWallet)) }
                    } footer: {
                        Text("Recorded as moving money outside your tracked accounts.")
                    }
                }
                if event == nil, type.isCarryBearing {
                    Section {
                        Toggle("Override Carry Split", isOn: $overridesCarry.animation())
                        if overridesCarry {
                            VentureNumberField(title: "GP Carry", text: $gpCarryText)
                            VentureNumberField(title: "LP Net Amount", text: $lpNetText)
                        }
                    } footer: {
                        Text("By default the carry is computed from the deal's carry and hurdle.")
                    }
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(event == nil ? "New Event" : "Edit Event")
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
                    }
                }
            }
            .errorAlert($errorAlert)
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func parse(_ text: String) -> Decimal? {
        EditorAmountParser.parse(text.trimmingCharacters(in: .whitespaces))
    }

    private func save() async {
        let gross = type.requiresGrossAmount ? parse(grossText) : nil
        let nav = type.requiresNavAfter ? parse(navText) : nil
        if type.requiresGrossAmount, gross == nil {
            return fail(String(localized: "Enter the gross amount."))
        }
        if type.requiresNavAfter, nav == nil {
            return fail(String(localized: "Enter the NAV after the event."))
        }
        var gpCarry: Decimal?
        var lpNet: Decimal?
        if event == nil, type.isCarryBearing, overridesCarry {
            gpCarry = parse(gpCarryText)
            lpNet = parse(lpNetText)
            if gpCarry == nil || lpNet == nil {
                return fail(String(localized: "Enter both the GP carry and the LP net amount."))
            }
        }
        guard let client = services.client else { return }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        validationMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            if let event {
                _ = try await client.send(Endpoints.ventureEventUpdate(id: event.id, VentureEventUpdateRequest(
                    eventDate: CalendarDate(date: date),
                    grossAmount: gross,
                    navAfter: nav,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                )))
            } else {
                _ = try await client.send(Endpoints.ventureEventCreate(dealId: deal.id, VentureEventCreateRequest(
                    type: type,
                    eventDate: CalendarDate(date: date),
                    cashFlowMode: type.isNavOnly ? .none : .outOfWallet,
                    grossAmount: gross,
                    navAfter: nav,
                    gpCarryOverride: gpCarry,
                    lpNetAmountOverride: lpNet,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                )))
            }
            await onSaved()
            dismiss()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func fail(_ message: String) {
        withAnimation { validationMessage = message }
    }
}

/// Creates or edits a platform and its default fee terms.
struct VenturePlatformFormSheet: View {
    let platform: VenturePlatform?
    let onSaved: () async -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var website: String
    @State private var details: String
    @State private var entryFeePctText: String
    @State private var mgmtFeePctText: String
    @State private var carryPctText: String
    @State private var hurdlePctText: String
    @State private var isSaving = false
    @State private var validationMessage: String?
    @State private var errorAlert: ErrorAlert?

    init(platform: VenturePlatform?, onSaved: @escaping () async -> Void) {
        self.platform = platform
        self.onSaved = onSaved
        _name = State(initialValue: platform?.name ?? "")
        _website = State(initialValue: platform?.website ?? "")
        _details = State(initialValue: platform?.platformDescription ?? "")
        _entryFeePctText = State(initialValue: VentureFormat.percentText(platform?.defaultEntryFeePct ?? 0))
        _mgmtFeePctText = State(initialValue: VentureFormat.percentText(platform?.defaultMgmtFeePct ?? 0))
        _carryPctText = State(initialValue: VentureFormat.percentText(platform?.defaultCarryPct ?? Decimal(string: "0.2")!))
        _hurdlePctText = State(initialValue: VentureFormat.percentText(platform?.defaultHurdlePct ?? 0))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Website (optional)", text: $website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Description (optional)", text: $details, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section {
                    VentureNumberField(title: "Entry Fee (%)", text: $entryFeePctText)
                    VentureNumberField(title: "Management Fee (%)", text: $mgmtFeePctText)
                    VentureNumberField(title: "Carry (%)", text: $carryPctText)
                    VentureNumberField(title: "Hurdle (%)", text: $hurdlePctText)
                } header: {
                    Text("Default Fees")
                } footer: {
                    Text("New deals on this platform start with these fees.")
                }
                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(platform == nil ? "New Platform" : "Edit Platform")
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
                    }
                }
            }
            .errorAlert($errorAlert)
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            withAnimation { validationMessage = String(localized: "Enter a name.") }
            return
        }
        var trimmedWebsite = website.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedWebsite.isEmpty, !trimmedWebsite.contains("://") {
            trimmedWebsite = "https://" + trimmedWebsite
        }
        if !trimmedWebsite.isEmpty, URL(string: trimmedWebsite)?.host() == nil {
            withAnimation { validationMessage = String(localized: "Enter a valid website address.") }
            return
        }
        guard let entryPct = VentureFormat.fraction(fromPercentText: entryFeePctText),
              let mgmtPct = VentureFormat.fraction(fromPercentText: mgmtFeePctText),
              let carryPct = VentureFormat.fraction(fromPercentText: carryPctText),
              let hurdlePct = VentureFormat.fraction(fromPercentText: hurdlePctText)
        else {
            withAnimation { validationMessage = String(localized: "Enter fee percentages between 0 and 100.") }
            return
        }
        guard let client = services.client else { return }
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = VenturePlatformRequest(
            name: trimmedName,
            website: trimmedWebsite.isEmpty ? nil : trimmedWebsite,
            description: trimmedDetails.isEmpty ? nil : trimmedDetails,
            defaultEntryFeePct: entryPct,
            defaultMgmtFeePct: mgmtPct,
            defaultCarryPct: carryPct,
            defaultHurdlePct: hurdlePct
        )
        validationMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            if let platform {
                _ = try await client.send(Endpoints.venturePlatformUpdate(id: platform.id, request))
            } else {
                _ = try await client.send(Endpoints.venturePlatformCreate(request))
            }
            await onSaved()
            dismiss()
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}
