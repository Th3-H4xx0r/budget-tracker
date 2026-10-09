import Foundation

/// Loans split the way the list shows them. Archive wins over paid off.
public struct LoanPartition: Sendable, Hashable {
    public var active: [Loan] = []
    public var paidOff: [Loan] = []
    public var archived: [Loan] = []

    /// Loans the aggregate counts: active and paid off, never archived.
    public var tracked: [Loan] { active + paidOff }
}

/// Portfolio-level figures for the loans list header, in the base currency.
public struct LoanAggregate: Sendable, Hashable {
    public let totalOutstanding: Decimal
    /// 0...100 share of active principal already repaid; nil without active principal.
    public let principalRepaidPercent: Double?
    public let activePrincipal: Decimal?
    public let weightedAPR: Double?
    public let monthlyObligation: Decimal?
    /// The latest payoff date among active loans; nil if any active loan has none.
    public let debtFreeDate: CalendarDate?
    public let interestRemaining: Decimal?
}

/// One month of a payoff schedule.
public struct LoanPayoffPoint: Sendable, Hashable {
    public let month: Int
    public let date: Date
    public let balance: Decimal
}

/// A projected payoff at a fixed monthly payment.
public struct LoanPayoffScenario: Sendable, Hashable {
    public let paysOff: Bool
    public let monthsRemaining: Int?
    public let payoffDate: Date?
    public let totalInterest: Decimal?
    public let points: [LoanPayoffPoint]
}

/// How principal and estimated interest share the total cost of a loan.
public struct LoanCostSplit: Sendable, Hashable {
    public let total: Decimal
    public let principal: Decimal
    public let interest: Decimal
    public let hasInterest: Bool
    public let principalPercent: Double
    public let interestPercent: Double
    /// Interest per unit borrowed, in cents (e.g. 24 for 24¢ per $1).
    public let interestPerUnitCents: Int?
}

/// Pure loan calculations shared by the list and detail screens.
public enum LoanMath {
    static let maxProjectionMonths = 1200

    /// The positive amount owed for a signed (negative-liability) balance.
    public static func outstanding(balance: Decimal) -> Decimal {
        max(0, -balance)
    }

    public static func partition(_ loans: [Loan]) -> LoanPartition {
        var result = LoanPartition()
        for loan in loans {
            if loan.isArchived {
                result.archived.append(loan)
            } else if loan.projection.isPaidOff {
                result.paidOff.append(loan)
            } else {
                result.active.append(loan)
            }
        }
        return result
    }

    /// Aggregates over tracked (non-archived) loans.
    public static func aggregate(_ loans: [Loan]) -> LoanAggregate {
        let active = loans.filter { !$0.projection.isPaidOff }
        let total = loans.reduce(Decimal(0)) { $0 + $1.refOutstanding }

        var principal: Decimal = 0
        var outstanding: Decimal = 0
        for loan in active {
            principal += loan.loanDetails.refOriginalPrincipal
            outstanding += loan.refOutstanding
        }
        var repaidPercent: Double?
        if principal > 0 {
            let raw = (principal - outstanding) / principal * 100
            repaidPercent = min(100, max(0, raw.loanDouble))
        }

        var apr: Double?
        if !active.isEmpty {
            let balanceSum = active.reduce(Decimal(0)) { $0 + $1.refOutstanding }
            if balanceSum <= 0 {
                let sum = active.reduce(Decimal(0)) { $0 + $1.loanDetails.interestRate }
                apr = (sum / Decimal(active.count)).loanDouble
            } else {
                let weighted = active.reduce(Decimal(0)) { $0 + $1.loanDetails.interestRate * $1.refOutstanding }
                apr = (weighted / balanceSum).loanDouble
            }
        }

        let planned = active.compactMap(\.loanDetails.refPlannedPayment)
        let obligation: Decimal? = planned.isEmpty ? nil : planned.reduce(0, +)

        var debtFree: CalendarDate?
        if !active.isEmpty {
            let dates = active.map(\.projection.payoffDate)
            if dates.allSatisfy({ $0 != nil }) {
                debtFree = dates.compactMap { $0 }.max()
            }
        }

        let withInterest = loans.filter { $0.projection.totalInterestRemaining != nil }
        let interest: Decimal? = withInterest.isEmpty
            ? nil
            : withInterest.reduce(Decimal(0)) { $0 + ($1.projection.totalInterestRemaining ?? 0) * $1.refRate }

        return LoanAggregate(
            totalOutstanding: total,
            principalRepaidPercent: repaidPercent,
            activePrincipal: principal > 0 ? principal : nil,
            weightedAPR: apr,
            monthlyObligation: obligation,
            debtFreeDate: debtFree,
            interestRemaining: interest
        )
    }

    /// Banker's rounding, matching the server's cents math.
    static func roundHalfToEven(_ value: Double) -> Int {
        Int(value.rounded(.toNearestOrEven))
    }

    /// The amortizing monthly payment for `principal` over `termMonths` at `interestRate` APR.
    public static func minimumPayment(principal: Decimal, interestRate: Decimal, termMonths: Int?) -> Decimal? {
        guard let termMonths, termMonths > 0, principal > 0 else { return nil }
        let principalValue = principal.loanDouble
        let payment: Double
        if interestRate == 0 {
            payment = principalValue / Double(termMonths)
        } else {
            let monthlyRate = interestRate.loanDouble / 100 / 12
            payment = principalValue * monthlyRate / (1 - pow(1 + monthlyRate, -Double(termMonths)))
        }
        return Decimal((payment * 100).rounded()) / 100
    }

    /// Month-by-month payoff of `balance` at `payment` per month, starting `today`.
    public static func payoffScenario(
        balance: Decimal,
        interestRate: Decimal,
        payment: Decimal,
        today: Date,
        calendar: Calendar = .current
    ) -> LoanPayoffScenario {
        let balanceCents = Int((balance.loanDouble * 100).rounded())
        let paymentCents = Int((payment.loanDouble * 100).rounded())
        let rate = interestRate.loanDouble
        let never = LoanPayoffScenario(
            paysOff: false,
            monthsRemaining: nil,
            payoffDate: nil,
            totalInterest: nil,
            points: [LoanPayoffPoint(month: 0, date: today, balance: Decimal(max(0, balanceCents)) / 100)]
        )

        if balanceCents <= 0 {
            return LoanPayoffScenario(
                paysOff: true,
                monthsRemaining: 0,
                payoffDate: today,
                totalInterest: 0,
                points: [LoanPayoffPoint(month: 0, date: today, balance: 0)]
            )
        }
        guard paymentCents > 0 else { return never }
        let firstInterest = roundHalfToEven(Double(balanceCents) * rate / 100 / 12)
        guard paymentCents > firstInterest else { return never }

        let months: Int
        if rate == 0 {
            months = Int((Double(balanceCents) / Double(paymentCents)).rounded(.up))
        } else {
            let monthlyRate = rate / 100 / 12
            let numerator = log(Double(paymentCents) / (Double(paymentCents) - Double(balanceCents) * monthlyRate))
            let value = numerator / log(1 + monthlyRate)
            guard value.isFinite else { return never }
            months = Int(value.rounded(.up))
        }
        guard months > 0, months <= maxProjectionMonths else { return never }

        var totalInterestCents = 0
        var running = balanceCents
        var points = [LoanPayoffPoint(month: 0, date: today, balance: Decimal(balanceCents) / 100)]
        for month in 1...months {
            let interest = roundHalfToEven(Double(max(0, running)) * rate / 100 / 12)
            totalInterestCents += interest
            running = max(0, running + interest - paymentCents)
            let display = month == months ? 0 : running
            let date = calendar.date(byAdding: .month, value: month, to: today) ?? today
            points.append(LoanPayoffPoint(month: month, date: date, balance: Decimal(display) / 100))
        }
        return LoanPayoffScenario(
            paysOff: true,
            monthsRemaining: months,
            payoffDate: calendar.date(byAdding: .month, value: months, to: today),
            totalInterest: Decimal(totalInterestCents) / 100,
            points: points
        )
    }

    /// Monthly outstanding balances from `startDate` to `closedDate`, carrying the last known
    /// history value forward and ending at zero.
    public static func actualBalanceSeries(
        history: [LoanBalancePoint],
        startDate: Date,
        closedDate: Date,
        openingBalance: Decimal,
        calendar: Calendar = .current
    ) -> [LoanPayoffPoint] {
        let totalMonths = max(0, monthsBetween(startDate, closedDate, calendar: calendar))
        if totalMonths == 0 {
            return [
                LoanPayoffPoint(month: 0, date: startDate, balance: openingBalance),
                LoanPayoffPoint(month: 1, date: calendar.date(byAdding: .month, value: 1, to: startDate) ?? startDate, balance: 0),
            ]
        }
        let sorted = history
            .map { (date: $0.date.startDate(in: calendar), balance: outstanding(balance: $0.amount)) }
            .sorted { $0.date < $1.date }
        var points: [LoanPayoffPoint] = []
        var cursor = 0
        var lastKnown = openingBalance
        for month in 0...totalMonths {
            let monthDate = calendar.date(byAdding: .month, value: month, to: startDate) ?? startDate
            while cursor < sorted.count, sorted[cursor].date <= monthDate {
                lastKnown = sorted[cursor].balance
                cursor += 1
            }
            points.append(LoanPayoffPoint(month: month, date: monthDate, balance: month == totalMonths ? 0 : lastKnown))
        }
        return points
    }

    public static func costSplit(principal: Decimal, estimatedInterest: Decimal?) -> LoanCostSplit {
        let hasInterest = (estimatedInterest ?? 0) > 0
        let interest = hasInterest ? (estimatedInterest ?? 0) : 0
        let total = principal + interest
        let principalPercent = total > 0 ? (principal / total * 100).loanDouble : 100
        let interestPercent = total > 0 ? (interest / total * 100).loanDouble : 0
        let perUnit: Int? = hasInterest && principal > 0
            ? Int((interest / principal * 100).loanDouble.rounded())
            : nil
        return LoanCostSplit(
            total: total,
            principal: principal,
            interest: interest,
            hasInterest: hasInterest,
            principalPercent: principalPercent,
            interestPercent: interestPercent,
            interestPerUnitCents: perUnit
        )
    }

    /// Whole calendar months from `start` to `end`.
    public static func monthsBetween(_ start: Date, _ end: Date, calendar: Calendar = .current) -> Int {
        let startParts = calendar.dateComponents([.year, .month], from: start)
        let endParts = calendar.dateComponents([.year, .month], from: end)
        return ((endParts.year ?? 0) - (startParts.year ?? 0)) * 12 + ((endParts.month ?? 0) - (startParts.month ?? 0))
    }

    /// How many months before the scheduled end a loan was closed; nil without a term.
    public static func monthsEarly(startDate: Date, termMonths: Int?, closedDate: Date, calendar: Calendar = .current) -> Int? {
        guard let termMonths, termMonths > 0 else { return nil }
        let scheduledEnd = calendar.date(byAdding: .month, value: termMonths, to: startDate) ?? startDate
        return max(0, monthsBetween(closedDate, scheduledEnd, calendar: calendar))
    }
}

private extension Decimal {
    var loanDouble: Double { NSDecimalNumber(decimal: self).doubleValue }
}
