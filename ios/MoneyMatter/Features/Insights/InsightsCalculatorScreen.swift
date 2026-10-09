import Charts
import MoneyMatterKit
import SwiftUI

/// Investment calculator (web: `analytics/investment-calculator`). The projection runs on the
/// device; the server only seeds the starting balance and the average monthly net income.
struct InsightsCalculatorScreen: View {
    private static let customIndicatorID = "custom"
    private static let portfolioPrefix = "portfolio:"

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session

    @State private var initialBalance: Double = 0
    @State private var monthlyContribution: Double = 0
    @State private var years: Double = 10
    @State private var annualReturn: Double = InsightsMarketIndicator.all[0].averageAnnualReturn
    @State private var inflation: Double = 3
    @State private var indicatorID = InsightsMarketIndicator.all[0].id
    @State private var window: InsightsNetIncomeWindow = .sixMonths
    @State private var averageNetIncome: LoadState<Double> = .idle
    @State private var seedFailed: APIError?
    @State private var hasSeededBalance = false
    @State private var showsReal = true
    @State private var portfolioReturns: [InsightsPortfolioReturn] = []

    private var currencyCode: String { session.baseCurrency?.currencyCode ?? "USD" }

    private var params: InsightsProjectionParams {
        InsightsProjectionParams(
            initialBalance: initialBalance,
            monthlyContribution: monthlyContribution,
            timeHorizonYears: years,
            annualReturnRate: annualReturn,
            annualInflationRate: inflation
        )
    }

    var body: some View {
        let points = InsightsProjection.points(params)
        let summary = InsightsProjection.summary(params, points: points)
        Form {
            Section {
                summaryCards(summary)
                chart(points)
                Toggle("Show in Today's Money", isOn: $showsReal)
            } footer: {
                Text("Projections assume a constant return and monthly contributions at each month's end. Past returns don't guarantee future results.")
            }

            Section("Starting Point") {
                LabeledContent("Initial Balance") {
                    TextField("Initial Balance", value: $initialBalance, format: .currency(code: currencyCode))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                }
                LabeledContent("Monthly Contribution") {
                    TextField("Monthly Contribution", value: $monthlyContribution, format: .currency(code: currencyCode))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                }
                Picker("Average Net Income", selection: $window) {
                    Text("3 Mo").tag(InsightsNetIncomeWindow.threeMonths)
                    Text("6 Mo").tag(InsightsNetIncomeWindow.sixMonths)
                    Text("12 Mo").tag(InsightsNetIncomeWindow.twelveMonths)
                    Text("All").tag(InsightsNetIncomeWindow.all)
                }
                .pickerStyle(.segmented)
                switch averageNetIncome {
                case .loaded(let average):
                    Button {
                        monthlyContribution = average
                    } label: {
                        HStack {
                            Text("Use Average Net Income")
                            Spacer()
                            Text(average, format: .currency(code: currencyCode))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                case .failed(let error):
                    InlineRetryView(ErrorMessage.message(for: error)) { await loadAverage(apply: false) }
                case .idle, .loading:
                    Text("Calculating average net income…")
                        .foregroundStyle(.secondary)
                        .redactedWhileLoading(true)
                }
                if let seedFailed {
                    InlineRetryView(ErrorMessage.message(for: seedFailed)) { await seedBalance() }
                }
            }

            Section("Assumptions") {
                VStack(alignment: .leading) {
                    LabeledContent("Time Horizon") {
                        Text("\(Int(years)) years")
                            .monospacedDigit()
                    }
                    Slider(value: $years, in: 1...50, step: 1) {
                        Text("Time Horizon")
                    }
                    .accessibilityValue(Text("\(Int(years)) years"))
                }
                Picker("Annual Return", selection: $indicatorID) {
                    ForEach(InsightsMarketIndicator.all) { indicator in
                        Text(verbatim: "\(indicator.label) (\(indicator.averageAnnualReturn.formatted())%)").tag(indicator.id)
                    }
                    if !portfolioReturns.isEmpty {
                        Section("Your Portfolios") {
                            ForEach(portfolioReturns) { portfolio in
                                if let rate = portfolio.annualizedReturn {
                                    Text(verbatim: "\(portfolio.portfolioName) (\(rate.formatted(.number.precision(.fractionLength(0...2))))%)")
                                        .tag(Self.portfolioPrefix + portfolio.portfolioId)
                                }
                            }
                        }
                    }
                    Text("Custom").tag(Self.customIndicatorID)
                }
                if indicatorID == Self.customIndicatorID {
                    LabeledContent("Custom Return") {
                        TextField("Custom Return", value: $annualReturn, format: .number.precision(.fractionLength(0...2)))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                        Text(verbatim: "%")
                    }
                }
                Stepper(value: $inflation, in: 0...20, step: 0.5) {
                    LabeledContent("Inflation") {
                        Text("\(inflation.formatted(.number.precision(.fractionLength(0...1))))%")
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Investment Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: indicatorID) { _, id in
            if let indicator = InsightsMarketIndicator.all.first(where: { $0.id == id }) {
                annualReturn = indicator.averageAnnualReturn
            } else if id.hasPrefix(Self.portfolioPrefix),
                      let rate = portfolioReturns.first(where: { Self.portfolioPrefix + $0.portfolioId == id })?.annualizedReturn {
                annualReturn = (rate * 100).rounded() / 100
            }
        }
        .task {
            guard !hasSeededBalance else { return }
            async let balance: Void = seedBalance()
            async let average: Void = loadAverage(apply: true)
            async let returns: Void = loadPortfolioReturns()
            _ = await (balance, average, returns)
        }
        .onChange(of: window) { _, _ in
            Task { await loadAverage(apply: true) }
        }
    }

    // MARK: Pieces

    private func summaryCards(_ summary: InsightsProjectionSummary) -> some View {
        let finalValue = showsReal ? summary.realFinalValue : summary.nominalFinalValue
        let growth = showsReal ? summary.realGrowth : summary.nominalGrowth
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(showsReal ? "Final Value in Today's Money" : "Final Value")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(finalValue, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    metric("Total Invested", value: summary.totalInvested)
                    metric("Contributions", value: summary.totalContributions)
                }
                GridRow {
                    metric("Growth", value: growth, isGain: growth >= 0)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Real Multiplier")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(verbatim: "×\(summary.realMultiplier.formatted(.number.precision(.fractionLength(2))))")
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func metric(_ title: LocalizedStringKey, value: Double, isGain: Bool? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(isGain == true ? Color.green : Color.primary)
        }
    }

    private func chart(_ points: [InsightsProjectionPoint]) -> some View {
        // One point per year keeps the chart light for long horizons.
        let yearly = points.filter { $0.month % 12 == 0 || $0.month == points.last?.month }
        let valueLabel = showsReal ? String(localized: "Value (Today's Money)") : String(localized: "Value")
        let investedLabel = String(localized: "Total Invested")
        return Chart {
            ForEach(yearly) { point in
                AreaMark(x: .value("Year", point.year), y: .value("Amount", point.totalInvested))
                    .foregroundStyle(by: .value("Series", investedLabel))
                    .opacity(0.3)
                LineMark(x: .value("Year", point.year), y: .value("Amount", showsReal ? point.real : point.nominal))
                    .foregroundStyle(by: .value("Series", valueLabel))
                    .interpolationMethod(.monotone)
            }
        }
        .chartForegroundStyleScale([valueLabel: Color.accentColor, investedLabel: Color.gray])
        .chartXAxisLabel("Years")
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(MoneyFormat.compactString(Decimal(amount), currencyCode: currencyCode))
                    }
                }
            }
        }
        .frame(height: 220)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Projected growth over \(Int(years)) years")
        .accessibilityValue(
            "\(MoneyFormat.spokenString(Decimal((showsReal ? points.last?.real : points.last?.nominal) ?? 0), currencyCode: currencyCode))"
        )
    }

    // MARK: Seeding

    /// Seeds the initial balance once with today's combined balance.
    private func seedBalance() async {
        guard let client = services.client else { return }
        let today = CalendarDate(date: .now)
        do {
            let points = try await client.send(Endpoints.combinedBalanceHistory(from: today, to: today))
            seedFailed = nil
            if !hasSeededBalance, let total = points.first?.totalBalance, total > 0 {
                initialBalance = NSDecimalNumber(decimal: total).doubleValue
                hasSeededBalance = true
            }
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation { seedFailed = apiError }
        }
    }

    /// The user's portfolios with enough history, offered as annual return choices.
    private func loadPortfolioReturns() async {
        guard let client = services.client else { return }
        if let returns = try? await client.send(Endpoints.insightsPortfolioReturns()) {
            portfolioReturns = returns.filter { $0.annualizedReturn != nil }
        }
    }

    /// Loads the window's average monthly net income; `apply` copies it into the contribution.
    private func loadAverage(apply: Bool) async {
        guard let client = services.client else { return }
        let range = window.range(today: CalendarDate(date: .now))
        if averageNetIncome.value == nil { averageNetIncome = .loading }
        do {
            let report = try await client.send(Endpoints.cashFlow(from: range.from, to: range.to, granularity: .monthly))
            let average = InsightsNetIncomeWindow.averageNetIncome(report)
            averageNetIncome = .loaded(average)
            if apply, average > 0 { monthlyContribution = average }
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation, averageNetIncome.value == nil { averageNetIncome = .failed(apiError) }
        }
    }
}
