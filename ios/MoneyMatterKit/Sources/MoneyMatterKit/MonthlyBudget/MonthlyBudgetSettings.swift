import Foundation

/// The user's monthly spending budget, stored server-side under the
/// `monthlySpendingBudget` key of `/user/settings`.
public struct MonthlyBudgetSettings: Sendable, Hashable, Codable {
    /// In the base currency; `nil` when no budget is set.
    public var amount: Decimal?
    /// Whether crossing 80 % and 100 % of the budget sends a notification.
    public var alertsEnabled: Bool

    public static let notSet = MonthlyBudgetSettings(amount: nil, alertsEnabled: true)

    public init(amount: Decimal?, alertsEnabled: Bool = true) {
        self.amount = amount
        self.alertsEnabled = alertsEnabled
    }

    /// The amount when it is a usable budget; zero and negative amounts count as unset.
    public var effectiveAmount: Decimal? {
        guard let amount, amount > 0 else { return nil }
        return amount
    }

    private enum CodingKeys: String, CodingKey { case amount, alertsEnabled }

    /// Lenient: `amount` may arrive as a number or a decimal string, and any malformed
    /// field falls back to its default instead of failing the whole settings payload.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let number = try? container.decodeIfPresent(Decimal.self, forKey: .amount) {
            amount = number
        } else if let text = try? container.decodeIfPresent(String.self, forKey: .amount) {
            amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        } else {
            amount = nil
        }
        alertsEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .alertsEnabled)) ?? true
    }

    /// Always writes `amount`, as `null` when unset, so a PATCH can clear the budget.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let amount {
            try container.encode(amount, forKey: .amount)
        } else {
            try container.encodeNil(forKey: .amount)
        }
        try container.encode(alertsEnabled, forKey: .alertsEnabled)
    }
}

/// The `monthlySpendingBudget` slice of `GET /user/settings`; other keys are ignored and a
/// missing or malformed value reads as `.notSet`.
struct MonthlyBudgetUserSettings: Sendable, Decodable {
    let monthlySpendingBudget: MonthlyBudgetSettings

    private enum CodingKeys: String, CodingKey { case monthlySpendingBudget }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monthlySpendingBudget = (try? container.decodeIfPresent(MonthlyBudgetSettings.self, forKey: .monthlySpendingBudget))
            ?? .notSet
    }
}

/// `PATCH /user/settings` body that sends only `monthlySpendingBudget`.
struct MonthlyBudgetSettingsPatch: Encodable, Sendable {
    let monthlySpendingBudget: MonthlyBudgetSettings
}

extension Endpoints {
    /// `GET /user/settings`, decoding only `monthlySpendingBudget`.
    public static func monthlyBudgetSettings() -> Endpoint<MonthlyBudgetSettings> {
        Endpoint<MonthlyBudgetUserSettings>(.get, "/user/settings").map { $0.monthlySpendingBudget }
    }

    /// `PATCH /user/settings` with only `monthlySpendingBudget`; the server deep-merges it and
    /// returns the merged settings.
    public static func patchMonthlyBudgetSettings(_ settings: MonthlyBudgetSettings) -> Endpoint<MonthlyBudgetSettings> {
        Endpoint<MonthlyBudgetUserSettings>(
            .patch,
            "/user/settings",
            body: MonthlyBudgetSettingsPatch(monthlySpendingBudget: settings)
        )
        .map { $0.monthlySpendingBudget }
    }
}
