import Charts
import MoneyMatterKit
import SwiftUI

/// The loans list: an aggregate card over tracked loans, then active, paid-off, and
/// archived sections.
struct LoansScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var loans: [Loan]?
    @State private var loadError: APIError?
    @State private var isCreating = false
    @State private var showsArchived = false
    @State private var alert: ErrorAlert?

    var body: some View {
        content
            .navigationTitle("Loans")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Label("Add Loan", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isCreating) {
                LoanFormSheet(loan: nil) { _ in
                    Task { await load() }
                }
            }
            .errorAlert($alert)
            .task {
                if loans == nil { await load() }
            }
    }

    @ViewBuilder private var content: some View {
        if let loans {
            if loans.isEmpty {
                ContentUnavailableView {
                    Label("No Loans", systemImage: "banknote")
                } description: {
                    Text("Track a mortgage, car loan, or student loan and see when you'll be debt-free.")
                } actions: {
                    Button("Add Loan") { isCreating = true }
                        .buttonStyle(.borderedProminent)
                }
                .refreshable { await load() }
            } else {
                list(loans)
            }
        } else if let loadError {
            LoadFailedView(error: loadError) { await load() }
        } else {
            placeholder
        }
    }

    private var baseCurrencyCode: String {
        referenceData.userCurrencies.first(where: \.isDefaultCurrency)?.currencyCode
            ?? loans?.first?.currencyCode
            ?? "USD"
    }

    private func list(_ loans: [Loan]) -> some View {
        let partition = LoanMath.partition(loans)
        return List {
            if !partition.tracked.isEmpty {
                Section {
                    LoanAggregateCard(
                        aggregate: LoanMath.aggregate(partition.tracked),
                        loans: partition.tracked,
                        currencyCode: baseCurrencyCode
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            if !partition.active.isEmpty {
                Section("Active") {
                    ForEach(partition.active) { loan in row(loan) }
                }
            }
            if !partition.paidOff.isEmpty {
                Section("Paid Off") {
                    ForEach(partition.paidOff) { loan in row(loan) }
                }
            }
            if !partition.archived.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showsArchived) {
                        ForEach(partition.archived) { loan in row(loan) }
                    } label: {
                        Text("Archived (\(partition.archived.count))")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
    }

    private func row(_ loan: Loan) -> some View {
        NavigationLink {
            LoanDetailScreen(loanID: loan.id, initial: loan) {
                Task { await load() }
            }
        } label: {
            LoanListRow(loan: loan, digits: referenceData.digits(for: loan.currencyCode))
        }
        .swipeActions(edge: .trailing) {
            if loan.isArchived {
                Button {
                    Task { await restore(loan) }
                } label: {
                    Label("Restore", systemImage: "tray.and.arrow.up")
                }
                .tint(.blue)
            }
        }
    }

    private func restore(_ loan: Loan) async {
        guard let client = services.client else { return }
        do {
            let account = try await client.send(Endpoints.updateAccount(
                id: loan.id,
                AccountUpdateRequest(status: .active, excludeFromStats: false)
            ))
            referenceData.upsert(account)
            await load()
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private var placeholder: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "Total outstanding")
                    Text(verbatim: "$000,000.00").font(.largeTitle)
                    Text(verbatim: "00% of principal repaid")
                }
                .redacted(reason: .placeholder)
            }
            Section {
                ForEach(0..<3, id: \.self) { _ in
                    HStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray5)).frame(width: 36, height: 36)
                        VStack(alignment: .leading) {
                            Text(verbatim: "Loan name")
                            Text(verbatim: "Lender · 0.00%").font(.subheadline)
                        }
                        Spacer()
                        Text(verbatim: "$00,000")
                    }
                    .redacted(reason: .placeholder)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func load() async {
        guard let client = services.client else { return }
        do {
            loans = try await client.send(Endpoints.loans())
            loadError = nil
        } catch {
            if loans == nil { loadError = APIError(error) }
        }
    }
}

/// One loan in the list: type icon, name, lender and APR, outstanding amount and progress.
struct LoanListRow: View {
    let loan: Loan
    var digits: Int?

    var body: some View {
        HStack(spacing: 12) {
            LoanTypeIcon(type: loan.loanDetails.loanType)
            VStack(alignment: .leading, spacing: 4) {
                Text(loan.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !loan.projection.isPaidOff && !loan.isArchived {
                    ProgressView(value: min(100, max(0, loan.projection.paidToDatePercent.loanDouble)), total: 100)
                        .tint(.green)
                        .accessibilityLabel(Text("\(loan.projection.paidToDatePercent.loanDouble, format: .number.precision(.fractionLength(0)))% paid"))
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if loan.projection.isPaidOff {
                    Label("Paid Off", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Text(MoneyFormat.string(loan.outstanding, currencyCode: loan.currencyCode, digits: digits))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                }
                Text(trailingCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .opacity(loan.isArchived ? 0.7 : 1)
    }

    private var subtitle: String {
        let apr = loan.loanDetails.interestRate.loanDouble.formatted(.number.precision(.fractionLength(0...3)))
        if let lender = loan.loanDetails.lenderName, !lender.isEmpty {
            return String(localized: "\(lender) · \(apr)% APR")
        }
        return String(localized: "\(loan.loanDetails.loanType.loanDisplayName) · \(apr)% APR")
    }

    private var trailingCaption: String {
        if loan.projection.isPaidOff {
            if let date = loan.paidOffAt {
                return date.formatted(.dateTime.month(.abbreviated).year())
            }
            return String(localized: "Settled")
        }
        if let payoff = loan.projection.payoffDate {
            return String(localized: "Payoff \(payoff.startDate().formatted(.dateTime.month(.abbreviated).year()))")
        }
        return String(localized: "No payoff date")
    }
}

/// A rounded tile with the loan type's symbol.
struct LoanTypeIcon: View {
    let type: LoanType
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: type.loanSymbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(type.loanTint.gradient, in: .rect(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The aggregate header over tracked loans, in the base currency.
struct LoanAggregateCard: View {
    let aggregate: LoanAggregate
    let loans: [Loan]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Outstanding")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(MoneyFormat.string(aggregate.totalOutstanding, currencyCode: currencyCode))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let percent = aggregate.principalRepaidPercent, let principal = aggregate.activePrincipal {
                    Text("\(percent, format: .number.precision(.fractionLength(1)))% of \(MoneyFormat.string(principal, currencyCode: currencyCode)) principal repaid")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !segments.isEmpty {
                Chart(segments, id: \.id) { segment in
                    BarMark(x: .value("Outstanding", segment.amount.loanDouble))
                        .foregroundStyle(segment.type.loanTint)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 12)
                .clipShape(.capsule)
                .accessibilityLabel(Text("Outstanding by loan"))
                .accessibilityValue(Text(segments.map { "\($0.name) \(MoneyFormat.string($0.amount, currencyCode: currencyCode))" }.joined(separator: ", ")))
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    metric("Avg APR", value: aggregate.weightedAPR.map { "\($0.formatted(.number.precision(.fractionLength(2))))%" })
                    metric("Monthly", value: aggregate.monthlyObligation.map { MoneyFormat.string($0, currencyCode: currencyCode) })
                }
                GridRow {
                    metric("Debt-Free", value: aggregate.debtFreeDate.map { $0.startDate().formatted(.dateTime.month(.abbreviated).year()) })
                    metric("Interest Left", value: aggregate.interestRemaining.map { MoneyFormat.string($0, currencyCode: currencyCode) })
                }
            }
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
    }

    private struct Segment {
        let id: String
        let name: String
        let type: LoanType
        let amount: Decimal
    }

    private var segments: [Segment] {
        loans
            .map { Segment(id: $0.id, name: $0.name, type: $0.loanDetails.loanType, amount: $0.refOutstanding) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
    }

    private func metric(_ title: LocalizedStringKey, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension LoanType {
    var loanDisplayName: String {
        switch self {
        case .mortgage: String(localized: "Mortgage")
        case .auto: String(localized: "Auto Loan")
        case .student: String(localized: "Student Loan")
        case .personal: String(localized: "Personal Loan")
        case .heloc: String(localized: "HELOC")
        case .business: String(localized: "Business Loan")
        case .medical: String(localized: "Medical Loan")
        case .other, .unknown: String(localized: "Loan")
        }
    }

    var loanSymbol: String {
        switch self {
        case .mortgage, .heloc: "house.fill"
        case .auto: "car.fill"
        case .student: "graduationcap.fill"
        case .personal: "person.fill"
        case .business: "briefcase.fill"
        case .medical: "cross.case.fill"
        case .other, .unknown: "banknote.fill"
        }
    }

    var loanTint: Color {
        switch self {
        case .mortgage, .heloc: .blue
        case .auto: .orange
        case .student: .purple
        case .personal: .teal
        case .business: .indigo
        case .medical: .pink
        case .other, .unknown: .gray
        }
    }
}

extension Decimal {
    /// For charts and percentages; money math stays in `Decimal`.
    var loanDouble: Double { NSDecimalNumber(decimal: self).doubleValue }
}
