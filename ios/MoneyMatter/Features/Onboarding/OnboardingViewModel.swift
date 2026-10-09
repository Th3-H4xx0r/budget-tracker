import Foundation
import MoneyMatterKit
import Observation

/// Loads the server's currencies and saves the chosen base currency.
@Observable
final class OnboardingViewModel {
    private(set) var currencies: LoadState<[Currency]> = .idle
    var selection: String?
    private(set) var isSaving = false
    var alert: ErrorAlert?

    private let locale: Locale

    init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    /// The device currency, then USD, EUR, and GBP, limited to what the server offers.
    var suggestedCodes: [String] {
        guard let available = currencies.value.map({ Set($0.map(\.code)) }) else { return [] }
        return CurrencyList.suggestedCodes(locale: locale).filter(available.contains)
    }

    func load(using service: any UserServicing) async {
        if case .loaded = currencies { return }
        currencies = .loading
        do {
            let all = try await service.allCurrencies().filter { !$0.isDisabled }
            currencies = .loaded(all)
            if selection == nil { selection = suggestedCodes.first }
        } catch {
            currencies = .failed(APIError(error))
        }
    }

    func reload(using service: any UserServicing) async {
        currencies = .idle
        await load(using: service)
    }

    func save(session: SessionStore) async {
        guard let selection, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await session.completeOnboarding(currencyCode: selection)
        } catch {
            alert = ErrorAlert(error)
        }
    }
}
