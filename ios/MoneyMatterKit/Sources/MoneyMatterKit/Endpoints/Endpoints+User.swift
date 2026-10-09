import Foundation

extension Endpoints {
    struct BaseCurrencyBody: Encodable, Sendable {
        let currencyCode: String
    }

    struct AddCurrenciesBody: Encodable, Sendable {
        struct Item: Encodable, Sendable {
            let currencyCode: String
        }

        let currencies: [Item]
    }

    /// `GET /user`.
    public static func currentUser() -> Endpoint<User> {
        Endpoint(.get, "/user")
    }

    /// `GET /models/currencies` (no auth): every currency the server knows.
    public static func currencies() -> Endpoint<[Currency]> {
        Endpoint(.get, "/models/currencies")
    }

    /// `GET /user/currencies`.
    public static func userCurrencies() -> Endpoint<[UserCurrency]> {
        Endpoint(.get, "/user/currencies")
    }

    /// `GET /user/currencies/base`: `nil` until onboarding sets one.
    public static func baseCurrency() -> Endpoint<UserCurrency?> {
        Endpoint(.get, "/user/currencies/base")
    }

    /// `POST /user/currencies/base`. Fails with 422 when a base currency already exists.
    public static func setBaseCurrency(code: String) -> Endpoint<UserCurrency> {
        Endpoint(.post, "/user/currencies/base", body: BaseCurrencyBody(currencyCode: code))
    }

    /// `POST /user/currencies`: connects more currencies at live rates.
    public static func addUserCurrencies(codes: [String]) -> Endpoint<AddedUserCurrencies> {
        Endpoint(
            .post,
            "/user/currencies",
            body: AddCurrenciesBody(currencies: codes.map { AddCurrenciesBody.Item(currencyCode: $0) })
        )
    }
}
