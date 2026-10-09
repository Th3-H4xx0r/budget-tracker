import Foundation

/// Currency formatting for `Decimal` amounts.
public enum MoneyFormat {
    public enum SignDisplay: Sendable {
        /// A minus for negatives only.
        case automatic
        /// A plus for positives as well, e.g. for changes.
        case always
        /// No sign at all; the caller conveys direction another way.
        case never
    }

    /// `-$84.21`. `digits` is the currency's minor-unit count from the API; when nil the
    /// ISO default for `currencyCode` is used.
    public static func string(
        _ amount: Decimal,
        currencyCode: String,
        digits: Int? = nil,
        sign: SignDisplay = .automatic,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        var style = Decimal.FormatStyle.Currency(code: currencyCode, locale: locale)
        if let digits {
            style = style.precision(.fractionLength(max(0, digits)))
        }
        switch sign {
        case .automatic:
            return amount.formatted(style)
        case .always:
            return amount.formatted(style.sign(strategy: .always(showZero: false)))
        case .never:
            return abs(amount).formatted(style)
        }
    }

    /// A compact form for chart axes and tight rows, e.g. `$1.2K`.
    public static func compactString(
        _ amount: Decimal,
        currencyCode: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        amount.formatted(
            Decimal.FormatStyle.Currency(code: currencyCode, locale: locale)
                .notation(.compactName)
                .precision(.significantDigits(1...3))
        )
    }

    /// A VoiceOver label such as "minus $84.21", which VoiceOver reads as "minus 84 dollars
    /// and 21 cents". The leading word is passed in so the app can localize it.
    public static func spokenString(
        _ amount: Decimal,
        currencyCode: String,
        digits: Int? = nil,
        minusWord: String = "minus",
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let magnitude = string(abs(amount), currencyCode: currencyCode, digits: digits, sign: .automatic, locale: locale)
        return amount < 0 ? "\(minusWord) \(magnitude)" : magnitude
    }

    /// The symbol for `currencyCode` in `locale`, e.g. `$` or `€`, for amount fields.
    public static func symbol(for currencyCode: String, locale: Locale = .autoupdatingCurrent) -> String {
        var components = Locale.Components(locale: locale)
        components.currency = Locale.Currency(currencyCode)
        let localized = Locale(components: components)
        return localized.currencySymbol ?? currencyCode
    }

    /// Rounds half away from zero to `digits` decimal places, e.g. before sending an amount
    /// typed with more precision than the currency has.
    public static func rounded(_ amount: Decimal, digits: Int) -> Decimal {
        var value = amount
        var result = Decimal()
        NSDecimalRound(&result, &value, max(0, digits), .plain)
        return result
    }
}
