import Charts
import MoneyMatterKit
import SwiftUI

/// One loan: summary, balance journey, payoff projection, cost, details, recent payments,
/// and the events timeline, with payment, edit, note, archive, and delete actions.
struct LoanDetailScreen: View {
    let loanID: String
    var initial: Loan?
    var onChange: () -> Void = {}

    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var loan: Loan?
    @State private var loadError: APIError?
    @State private var history: [LoanBalancePoint]?
    @State private var historyFailed = false
    @State private var payments: [Transaction]?
    @State private var paymentsFailed = false
    @State private var alert: ErrorAlert?
    @State private var isEditing = false
    @State private var isPaying = false
    @State private var isLinkingPayments = false
    @State private var isConfirmingArchive = false
    @State private var isConfirmingDelete = false
    @State private var isAddingNote = false
    @State private var noteText = ""
    @State private var isMutating = false

    var body: some View {
        Group {
            if let loan {
                content(loan)
            } else if let loadError {
                LoadFailedView(error: loadError) { await load() }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(loan?.name ?? initial?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .errorAlert($alert)
        .task {
            if loan == nil {
                loan = initial
                await load()
            }
        }
    }

    // MARK: Content

    private func content(_ loan: Loan) -> some View {
        let digits = referenceData.digits(for: loan.currencyCode)
        return ScrollView {
            VStack(spacing: 16) {
                LoanSummaryCard(loan: loan, digits: digits)
                LoanJourneyCard(loan: loan, history: history, failed: historyFailed, digits: digits) {
                    await loadHistory()
                }
                if !loan.projection.isPaidOff {
                    LoanProjectionCard(loan: loan, digits: digits)
                }
                LoanCostCard(loan: loan, digits: digits)
                LoanDetailsCard(loan: loan, digits: digits)
                paymentsCard(loan)
                LoanTimelineCard(loan: loan, digits: digits) {
                    noteText = ""
                    isAddingNote = true
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await load() }
        .sheet(isPresented: $isEditing) {
            LoanFormSheet(loan: loan) { updated in
                self.loan = updated
                onChange()
                Task { await loadHistory() }
            }
        }
        .sheet(isPresented: $isPaying) {
            LoanPaymentSheet(loan: loan) {
                onChange()
                Task {
                    await load()
                    await referenceData.refreshAccounts()
                }
            }
        }
        .sheet(isPresented: $isLinkingPayments) {
            LoanLinkPaymentsSheet(loan: loan) {
                onChange()
                Task {
                    await load()
                    await referenceData.refreshAccounts()
                }
            }
        }
        .confirmationDialog("Archive this loan?", isPresented: $isConfirmingArchive, titleVisibility: .visible) {
            Button("Archive and Exclude from Statistics") { Task { await setArchived(true, excludeFromStats: true) } }
            Button("Archive Only") { Task { await setArchived(true, excludeFromStats: false) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archived loans move to the Archived section and stop counting toward your totals.")
        }
        .confirmationDialog("Delete this loan?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Loan", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the loan and its history.")
        }
        .alert("Add Note", isPresented: $isAddingNote) {
            TextField("Note", text: $noteText, axis: .vertical)
            Button("Cancel", role: .cancel) {}
            Button("Add") { Task { await addNote() } }
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Notes appear in the loan's timeline.")
        }
    }

    private func paymentsCard(_ loan: Loan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: "Recent Payments") {
                if !loan.projection.isPaidOff {
                    Button("Record") { isPaying = true }
                        .font(.subheadline)
                }
            }
            if let payments {
                if payments.isEmpty {
                    Text("No payments recorded yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(payments) { payment in
                        NavigationLink {
                            TransactionDetailScreen(transactionID: payment.id, initial: payment)
                        } label: {
                            ResolvedTransactionRow(transaction: payment, showsDate: true)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if payment.transferNature == .toLoan {
                                Button {
                                    Task { await unlink(payment) }
                                } label: {
                                    Label("Unlink Payment", systemImage: "link.badge.minus")
                                }
                            }
                        }
                        if payment.id != payments.last?.id { Divider() }
                    }
                }
            } else if paymentsFailed {
                InlineRetryView("Couldn't load payments") { await loadPayments() }
            } else {
                TransactionRowsPlaceholder(count: 2)
            }
        }
        .cardStyle()
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if let loan {
            if !loan.projection.isPaidOff && !loan.isArchived {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPaying = true
                    } label: {
                        Label("Record Payment", systemImage: "plus.circle")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        isEditing = true
                    } label: {
                        Label("Edit Loan", systemImage: "pencil")
                    }
                    Button {
                        noteText = ""
                        isAddingNote = true
                    } label: {
                        Label("Add Note", systemImage: "note.text.badge.plus")
                    }
                    if !loan.isArchived {
                        Button {
                            isLinkingPayments = true
                        } label: {
                            Label("Link Existing Payments", systemImage: "link")
                        }
                    }
                    Toggle(isOn: Binding(
                        get: { loan.account.excludeFromStats },
                        set: { newValue in Task { await setExcludeFromStats(newValue) } }
                    )) {
                        Label("Exclude from Statistics", systemImage: "chart.bar.xaxis")
                    }
                    Divider()
                    if loan.isArchived {
                        Button {
                            Task { await setArchived(false, excludeFromStats: false) }
                        } label: {
                            Label("Restore Loan", systemImage: "tray.and.arrow.up")
                        }
                    } else {
                        Button {
                            isConfirmingArchive = true
                        } label: {
                            Label("Archive Loan", systemImage: "archivebox")
                        }
                    }
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete Loan", systemImage: "trash")
                    }
                    .disabled(loan.paymentsCount > 0)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .disabled(isMutating)
            }
        }
    }

    // MARK: Loading

    private func load() async {
        guard let client = services.client else { return }
        do {
            loan = try await client.send(Endpoints.loan(id: loanID))
            loadError = nil
        } catch {
            if loan == nil { loadError = APIError(error) }
        }
        await loadHistory()
        await loadPayments()
    }

    private func loadHistory() async {
        guard let client = services.client else { return }
        do {
            history = try await client.send(Endpoints.loanBalanceHistory(id: loanID))
            historyFailed = false
        } catch {
            historyFailed = history == nil
        }
    }

    private func loadPayments() async {
        guard let client = services.client else { return }
        var query = TransactionListQuery(limit: 10)
        query.accountIds = [loanID]
        query.order = .descending
        do {
            payments = try await client.send(Endpoints.transactions(query))
            paymentsFailed = false
        } catch {
            paymentsFailed = payments == nil
        }
    }

    // MARK: Mutations

    private func setArchived(_ archived: Bool, excludeFromStats: Bool) async {
        guard let client = services.client else { return }
        isMutating = true
        defer { isMutating = false }
        let request = archived
            ? AccountUpdateRequest(status: .archived, excludeFromStats: excludeFromStats ? true : nil)
            : AccountUpdateRequest(status: .active, excludeFromStats: false)
        do {
            let account = try await client.send(Endpoints.updateAccount(id: loanID, request))
            referenceData.upsert(account)
            loan = try await client.send(Endpoints.loan(id: loanID))
            onChange()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func setExcludeFromStats(_ exclude: Bool) async {
        guard let client = services.client else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            let account = try await client.send(Endpoints.updateAccount(id: loanID, AccountUpdateRequest(excludeFromStats: exclude)))
            referenceData.upsert(account)
            loan = try await client.send(Endpoints.loan(id: loanID))
            onChange()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func delete() async {
        guard let client = services.client else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            _ = try await client.send(Endpoints.loanDelete(id: loanID))
            referenceData.removeAccount(id: loanID)
            onChange()
            dismiss()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func unlink(_ payment: Transaction) async {
        guard let client = services.client else { return }
        do {
            let result = try await client.send(Endpoints.loanUnlinkPayment(id: loanID, transactionId: payment.id))
            loan = result.loan
            onChange()
            await loadPayments()
            await loadHistory()
            await referenceData.refreshAccounts()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func addNote() async {
        guard let client = services.client else { return }
        let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            loan = try await client.send(Endpoints.loanAddNote(id: loanID, text: text))
        } catch {
            alert = ErrorAlert(error)
        }
    }
}

// MARK: - Cards

/// Outstanding balance, progress, and the key terms.
private struct LoanSummaryCard: View {
    let loan: Loan
    let digits: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                LoanTypeIcon(type: loan.loanDetails.loanType, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loan.loanDetails.loanType.loanDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let lender = loan.loanDetails.lenderName, !lender.isEmpty {
                        Text(lender).font(.headline)
                    }
                }
                Spacer()
                if loan.isArchived {
                    Text("Archived")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill), in: .capsule)
                }
            }

            if loan.projection.isPaidOff {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Paid Off").font(.title2.weight(.bold))
                        if let date = loan.paidOffAt {
                            Text("Settled on \(date.formatted(date: .long, time: .omitted))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.title)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Outstanding")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(money(loan.outstanding))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("of \(money(loan.loanDetails.originalPrincipal)) borrowed")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(100, max(0, loan.projection.paidToDatePercent.loanDouble)), total: 100) {
                    Text("\(loan.projection.paidToDatePercent.loanDouble, format: .number.precision(.fractionLength(1)))% paid · \(money(loan.projection.paidToDate))")
                        .font(.footnote)
                        .monospacedDigit()
                }
                .tint(.green)
            }

            if let warning = loan.projection.warning, !loan.projection.isPaidOff {
                Label(warningText(warning), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    stat("APR", "\(loan.loanDetails.interestRate.loanDouble.formatted(.number.precision(.fractionLength(0...3))))%")
                    stat("Planned Payment", loan.loanDetails.plannedPayment.map(money))
                }
                if !loan.projection.isPaidOff {
                    GridRow {
                        stat("Payoff", loan.projection.payoffDate.map { $0.startDate().formatted(.dateTime.month(.abbreviated).year()) })
                        stat("Monthly Interest", money(loan.projection.monthlyInterest))
                    }
                }
            }
        }
        .cardStyle()
    }

    private func warningText(_ warning: LoanProjectionWarning) -> String {
        switch warning {
        case .noPlannedPayment: String(localized: "Set a planned payment to see when this loan will be paid off.")
        case .paymentBelowInterest: String(localized: "The planned payment doesn't cover the monthly interest, so the balance won't go down.")
        case .unknown: String(localized: "A payoff date can't be projected.")
        }
    }

    private func money(_ amount: Decimal) -> String {
        MoneyFormat.string(amount, currencyCode: loan.currencyCode, digits: digits)
    }

    private func stat(_ title: LocalizedStringKey, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "—").font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Actual outstanding balance over time, continued by the projected payoff when active.
private struct LoanJourneyCard: View {
    let loan: Loan
    let history: [LoanBalancePoint]?
    let failed: Bool
    let digits: Int?
    let retry: () async -> Void

    private struct Point: Identifiable {
        let id: String
        let date: Date
        let balance: Double
        let series: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Balance Journey") { EmptyView() }
            if let history {
                let points = makePoints(history)
                if points.count < 2 {
                    Text("Not enough history to chart yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    Chart(points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Balance", point.balance),
                            series: .value("Series", point.series)
                        )
                        .foregroundStyle(by: .value("Series", point.series))
                        .lineStyle(point.series == projectedLabel ? StrokeStyle(lineWidth: 2, dash: [5, 4]) : StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.monotone)
                        if point.series == actualLabel {
                            AreaMark(x: .value("Date", point.date), y: .value("Balance", point.balance))
                                .foregroundStyle(.linearGradient(colors: [.blue.opacity(0.25), .blue.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.monotone)
                        }
                    }
                    .chartForegroundStyleScale([actualLabel: Color.blue, projectedLabel: Color.secondary])
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(MoneyFormat.compactString(Decimal(amount), currencyCode: loan.currencyCode))
                                }
                            }
                        }
                    }
                    .frame(height: 200)
                    .accessibilityLabel(Text("Balance journey chart"))
                    .accessibilityValue(Text(summary(points)))
                }
            } else if failed {
                InlineRetryView("Couldn't load balance history", retry: retry)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(height: 200)
                    .accessibilityHidden(true)
            }
        }
        .cardStyle()
    }

    private var actualLabel: String { String(localized: "Actual") }
    private var projectedLabel: String { String(localized: "Projected") }

    private func makePoints(_ history: [LoanBalancePoint]) -> [Point] {
        let calendar = Calendar.current
        let opening = loan.loanDetails.originalPrincipal
        let start = loan.loanDetails.startDate.startDate(in: calendar)
        if loan.projection.isPaidOff {
            let closed = loan.paidOffAt ?? history.last?.date.startDate(in: calendar) ?? .now
            return LoanMath.actualBalanceSeries(history: history, startDate: start, closedDate: closed, openingBalance: opening)
                .map { Point(id: "a\($0.month)", date: $0.date, balance: $0.balance.loanDouble, series: actualLabel) }
        }
        var actual = [Point(id: "start", date: start, balance: opening.loanDouble, series: actualLabel)]
        for (index, entry) in history.sorted(by: { $0.date < $1.date }).enumerated() {
            let date = entry.date.startDate(in: calendar)
            guard date >= start else { continue }
            actual.append(Point(id: "h\(index)", date: date, balance: LoanMath.outstanding(balance: entry.amount).loanDouble, series: actualLabel))
        }
        let today = Date.now
        actual.append(Point(id: "today", date: today, balance: loan.outstanding.loanDouble, series: actualLabel))
        guard let payment = loan.loanDetails.plannedPayment, payment > 0 else { return actual }
        let scenario = LoanMath.payoffScenario(balance: loan.outstanding, interestRate: loan.loanDetails.interestRate, payment: payment, today: today)
        guard scenario.paysOff else { return actual }
        let projected = scenario.points.map {
            Point(id: "p\($0.month)", date: $0.date, balance: $0.balance.loanDouble, series: projectedLabel)
        }
        return actual + projected
    }

    private func summary(_ points: [Point]) -> String {
        let first = points.first.map { MoneyFormat.string(Decimal($0.balance), currencyCode: loan.currencyCode, digits: digits) } ?? ""
        let current = MoneyFormat.string(loan.outstanding, currencyCode: loan.currencyCode, digits: digits)
        return String(localized: "Started at \(first), now \(current)")
    }
}

/// Payoff at the planned payment, with a what-if extra monthly payment.
private struct LoanProjectionCard: View {
    let loan: Loan
    let digits: Int?
    @State private var extra: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Payoff Projection") { EmptyView() }
            if let planned = loan.loanDetails.plannedPayment, planned > 0 {
                let baseline = LoanMath.payoffScenario(balance: loan.outstanding, interestRate: loan.loanDetails.interestRate, payment: planned, today: .now)
                let scenario = LoanMath.payoffScenario(
                    balance: loan.outstanding,
                    interestRate: loan.loanDetails.interestRate,
                    payment: planned + Decimal(extra),
                    today: .now
                )
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        stat("Payoff Date", scenario.payoffDate?.formatted(.dateTime.month(.abbreviated).year()))
                        stat("Months Left", scenario.monthsRemaining.map { "\($0)" })
                    }
                    GridRow {
                        stat("Interest Left", scenario.totalInterest.map(money))
                        stat("Monthly Payment", money(planned + Decimal(extra)))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Extra per month: \(money(Decimal(extra)))")
                        .font(.subheadline)
                        .monospacedDigit()
                    Slider(value: $extra, in: 0...max(100, planned.loanDouble), step: stepSize(planned)) {
                        Text("Extra monthly payment")
                    }
                    .accessibilityValue(Text(money(Decimal(extra))))
                    if extra > 0, let savedMonths = monthsSaved(baseline, scenario), let savedInterest = interestSaved(baseline, scenario) {
                        Label {
                            Text("Pays off \(savedMonths) months sooner and saves \(money(savedInterest)) in interest.")
                        } icon: {
                            Image(systemName: "sparkles")
                        }
                        .font(.footnote)
                        .foregroundStyle(.green)
                    }
                }
            } else {
                Text("Set a planned payment to project your payoff date and try extra payments.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private func stepSize(_ planned: Decimal) -> Double {
        planned.loanDouble >= 1000 ? 50 : 10
    }

    private func monthsSaved(_ baseline: LoanPayoffScenario, _ scenario: LoanPayoffScenario) -> Int? {
        guard let base = baseline.monthsRemaining, let new = scenario.monthsRemaining else { return nil }
        return max(0, base - new)
    }

    private func interestSaved(_ baseline: LoanPayoffScenario, _ scenario: LoanPayoffScenario) -> Decimal? {
        guard let base = baseline.totalInterest, let new = scenario.totalInterest else { return nil }
        return max(0, base - new)
    }

    private func money(_ amount: Decimal) -> String {
        MoneyFormat.string(amount, currencyCode: loan.currencyCode, digits: digits)
    }

    private func stat(_ title: LocalizedStringKey, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "—").font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Principal versus estimated interest over the life of the loan.
private struct LoanCostCard: View {
    let loan: Loan
    let digits: Int?

    var body: some View {
        let split = LoanMath.costSplit(principal: loan.loanDetails.originalPrincipal, estimatedInterest: loan.projection.estimatedInterestPaid)
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Cost of Borrowing") { EmptyView() }
            Text(money(split.total))
                .font(.title2.weight(.bold))
                .monospacedDigit()
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Rectangle().fill(.blue).frame(width: proxy.size.width * split.principalPercent / 100)
                    Rectangle().fill(.orange)
                }
            }
            .frame(height: 10)
            .clipShape(.capsule)
            .accessibilityHidden(true)
            HStack {
                legend(color: .blue, title: "Principal", value: money(split.principal))
                Spacer()
                legend(color: .orange, title: "Interest Paid (est.)", value: split.hasInterest ? money(split.interest) : "—")
            }
            if let cents = split.interestPerUnitCents {
                Text("About \(cents)¢ of interest for every 1 borrowed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private func money(_ amount: Decimal) -> String {
        MoneyFormat.string(amount, currencyCode: loan.currencyCode, digits: digits)
    }

    private func legend(color: Color, title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }
}

/// Static loan terms.
private struct LoanDetailsCard: View {
    let loan: Loan
    let digits: Int?

    var body: some View {
        let details = loan.loanDetails
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Details") { EmptyView() }
            row("Type", details.loanType.loanDisplayName)
            row("Start Date", details.startDate.startDate().formatted(date: .abbreviated, time: .omitted))
            row("Term", details.termMonths.map(termText))
            row("Minimum Payment", details.minPayment.map(money))
            row("Payment Day", details.paymentDayOfMonth.map { String(localized: "Day \($0)") })
            row("Lender", details.lenderName)
            row("Account Number", details.accountNumber)
            row("Currency", loan.currencyCode)
        }
        .cardStyle()
    }

    private func termText(_ months: Int) -> String {
        let years = months / 12
        let rest = months % 12
        if years == 0 { return String(localized: "\(months) months") }
        if rest == 0 { return String(localized: "\(years) years") }
        return String(localized: "\(years) yr \(rest) mo")
    }

    private func money(_ amount: Decimal) -> String {
        MoneyFormat.string(amount, currencyCode: loan.currencyCode, digits: digits)
    }

    private func row(_ title: LocalizedStringKey, _ value: String?) -> some View {
        LabeledContent(title) {
            Text(value ?? "—").monospacedDigit()
        }
        .font(.subheadline)
    }
}

/// The append-only events timeline, newest first.
private struct LoanTimelineCard: View {
    let loan: Loan
    let digits: Int?
    let addNote: () -> Void

    var body: some View {
        let events = loan.loanDetails.events.filter { $0.kind != .unknown }.sorted { $0.at > $1.at }
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Timeline") {
                Button {
                    addNote()
                } label: {
                    Label("Add Note", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel(Text("Add Note"))
            }
            if events.isEmpty {
                Text("Rate, term, and payment changes will show up here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: symbol(event.kind))
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(tint(event.kind), in: .circle)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(event)).font(.subheadline.weight(.medium))
                            if let detail = detail(event) {
                                Text(detail).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                            }
                            Text(event.at.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .cardStyle()
    }

    private func symbol(_ kind: LoanEventKind) -> String {
        switch kind {
        case .rateChange: "percent"
        case .termChange: "calendar"
        case .plannedPaymentChange: "arrow.left.arrow.right"
        case .balanceCorrection: "pencil"
        case .note: "note.text"
        case .paidOff: "checkmark"
        case .unknown: "circle"
        }
    }

    private func tint(_ kind: LoanEventKind) -> Color {
        switch kind {
        case .paidOff: .green
        case .note: .gray
        case .balanceCorrection: .orange
        default: .blue
        }
    }

    private func title(_ event: LoanEvent) -> String {
        switch event.kind {
        case .rateChange: String(localized: "Interest rate changed")
        case .termChange: String(localized: "Term changed")
        case .plannedPaymentChange: String(localized: "Planned payment changed")
        case .balanceCorrection: String(localized: "Balance corrected")
        case .note: event.text ?? String(localized: "Note")
        case .paidOff: String(localized: "Loan paid off")
        case .unknown: String(localized: "Update")
        }
    }

    private func detail(_ event: LoanEvent) -> String? {
        let none = String(localized: "Not set")
        switch event.kind {
        case .rateChange:
            return "\(percent(event.from)) → \(percent(event.to))"
        case .termChange:
            let from = event.from.map { String(localized: "\($0.loanDouble.formatted()) mo") } ?? none
            let to = event.to.map { String(localized: "\($0.loanDouble.formatted()) mo") } ?? none
            return [String("\(from) → \(to)"), event.reason].compactMap { $0 }.joined(separator: " · ")
        case .plannedPaymentChange, .balanceCorrection:
            let from = event.from.map(money) ?? none
            let to = event.to.map(money) ?? none
            return "\(from) → \(to)"
        case .note, .paidOff, .unknown:
            return nil
        }
    }

    private func percent(_ value: Decimal?) -> String {
        guard let value else { return String(localized: "Not set") }
        return "\(value.loanDouble.formatted(.number.precision(.fractionLength(0...3))))%"
    }

    private func money(_ amount: Decimal) -> String {
        MoneyFormat.string(amount, currencyCode: loan.currencyCode, digits: digits)
    }
}
