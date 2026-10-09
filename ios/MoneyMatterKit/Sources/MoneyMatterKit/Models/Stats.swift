import Foundation

/// `GET /stats/combined-balance-history`: one day of the balance trend, in the base
/// currency. Loans are negative.
public struct BalancePoint: Sendable, Hashable, Identifiable, Decodable {
    public let date: CalendarDate
    public let accountsBalance: Decimal
    public let portfoliosBalance: Decimal
    public let venturesBalance: Decimal
    public let vehiclesBalance: Decimal
    public let loansBalance: Decimal
    public let totalBalance: Decimal

    public var id: CalendarDate { date }

    public init(
        date: CalendarDate,
        totalBalance: Decimal,
        accountsBalance: Decimal = 0,
        portfoliosBalance: Decimal = 0,
        venturesBalance: Decimal = 0,
        vehiclesBalance: Decimal = 0,
        loansBalance: Decimal = 0
    ) {
        self.date = date
        self.totalBalance = totalBalance
        self.accountsBalance = accountsBalance
        self.portfoliosBalance = portfoliosBalance
        self.venturesBalance = venturesBalance
        self.vehiclesBalance = vehiclesBalance
        self.loansBalance = loansBalance
    }

    private enum CodingKeys: String, CodingKey {
        case date, accountsBalance, portfoliosBalance, venturesBalance, vehiclesBalance, loansBalance, totalBalance
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(CalendarDate.self, forKey: .date)
        accountsBalance = try container.decodeIfPresent(Decimal.self, forKey: .accountsBalance) ?? 0
        portfoliosBalance = try container.decodeIfPresent(Decimal.self, forKey: .portfoliosBalance) ?? 0
        venturesBalance = try container.decodeIfPresent(Decimal.self, forKey: .venturesBalance) ?? 0
        vehiclesBalance = try container.decodeIfPresent(Decimal.self, forKey: .vehiclesBalance) ?? 0
        loansBalance = try container.decodeIfPresent(Decimal.self, forKey: .loansBalance) ?? 0
        totalBalance = try container.decode(Decimal.self, forKey: .totalBalance)
    }
}

/// One slice of `GET /stats/spendings-by-categories`, in the base currency. `amount` is positive.
public struct CategorySpending: Sendable, Hashable, Identifiable {
    /// The category id (the key of the response object).
    public let id: String
    public let name: String
    /// `#rrggbb`.
    public let color: String
    public let amount: Decimal

    public init(id: String, name: String, color: String, amount: Decimal) {
        self.id = id
        self.name = name
        self.color = color
        self.amount = amount
    }
}

/// Decodes the `{[categoryId]: {name, color, amount}}` object into an array sorted by
/// amount, largest first, with ties broken by name.
struct CategorySpendingMap: Decodable {
    let items: [CategorySpending]

    private struct Entry: Decodable {
        let name: String?
        let color: String?
        let amount: Decimal
    }

    init(from decoder: any Decoder) throws {
        let entries = try decoder.singleValueContainer().decode([String: Entry].self)
        items = entries
            .map { CategorySpending(id: $0.key, name: $0.value.name ?? "", color: $0.value.color ?? "#8e8e93", amount: $0.value.amount) }
            .sorted { lhs, rhs in
                lhs.amount != rhs.amount ? lhs.amount > rhs.amount : lhs.name < rhs.name
            }
    }
}

/// `GET /stats/expenses-amount-for-period`: the bare number, in the base currency.
public struct ExpensesTotal: Sendable, Hashable, Decodable {
    public let amount: Decimal

    public init(amount: Decimal) {
        self.amount = amount
    }

    public init(from decoder: any Decoder) throws {
        amount = try decoder.singleValueContainer().decode(Decimal.self)
    }
}
