import Foundation
import Testing
@testable import MoneyMatterKit

@Suite("MoneyFormat")
struct MoneyFormatTests {
    private let enUS = Locale(identifier: "en_US")

    @Test("Formats with the currency's minor digits")
    func digits() {
        #expect(MoneyFormat.string(Decimal(string: "1234.5")!, currencyCode: "USD", digits: 2, locale: enUS) == "$1,234.50")
        #expect(MoneyFormat.string(Decimal(string: "1234.6")!, currencyCode: "JPY", digits: 0, locale: enUS) == "¥1,235")
        #expect(MoneyFormat.string(10, currencyCode: "EUR", locale: enUS) == "€10.00")
    }

    @Test("Negative amounts get a leading minus")
    func negative() {
        let text = MoneyFormat.string(Decimal(string: "-84.21")!, currencyCode: "USD", digits: 2, locale: enUS)
        #expect(text.contains("84.21"))
        #expect(text.hasPrefix("-") || text.hasPrefix("\u{2212}"))
    }

    @Test("Sign display can force or hide the sign")
    func signDisplay() {
        #expect(MoneyFormat.string(Decimal(string: "12.5")!, currencyCode: "USD", digits: 2, sign: .always, locale: enUS) == "+$12.50")
        #expect(MoneyFormat.string(-5, currencyCode: "USD", digits: 2, sign: .never, locale: enUS) == "$5.00")
    }

    @Test("Spoken amounts read the sign as a word")
    func spoken() {
        #expect(MoneyFormat.spokenString(Decimal(string: "-84.21")!, currencyCode: "USD", digits: 2, locale: enUS) == "minus $84.21")
        #expect(MoneyFormat.spokenString(Decimal(string: "84.21")!, currencyCode: "USD", digits: 2, locale: enUS) == "$84.21")
        #expect(MoneyFormat.spokenString(-1, currencyCode: "USD", digits: 2, minusWord: "мінус", locale: enUS) == "мінус $1.00")
    }

    @Test("Currency symbols come from the locale")
    func symbols() {
        #expect(MoneyFormat.symbol(for: "USD", locale: enUS) == "$")
        #expect(MoneyFormat.symbol(for: "EUR", locale: enUS) == "€")
    }

    @Test("Rounding goes half away from zero")
    func rounding() {
        #expect(MoneyFormat.rounded(Decimal(string: "1.005")!, digits: 2) == Decimal(string: "1.01"))
        #expect(MoneyFormat.rounded(Decimal(string: "-2.345")!, digits: 2) == Decimal(string: "-2.35"))
        #expect(MoneyFormat.rounded(Decimal(string: "7.5")!, digits: 0) == 8)
    }
}
