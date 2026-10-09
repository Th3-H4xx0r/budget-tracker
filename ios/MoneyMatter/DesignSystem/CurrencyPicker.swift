import MoneyMatterKit
import SwiftUI

/// A searchable currency list with suggested currencies pinned on top. Used directly by
/// onboarding, and pushed by `CurrencyPickerLink` from forms.
struct CurrencyList: View {
    let currencies: [Currency]
    /// Codes shown in a "Suggested" section, in order.
    var pinnedCodes: [String] = []
    /// Shown above the list, e.g. to explain what the choice affects.
    var prompt: LocalizedStringKey?
    @Binding var selection: String?

    @State private var query = ""

    var body: some View {
        List {
            if let prompt, query.isEmpty {
                Section {
                } footer: {
                    Text(prompt)
                }
            }
            if query.isEmpty, !pinned.isEmpty {
                Section("Suggested") {
                    ForEach(pinned) { row(for: $0) }
                }
            }
            Section(query.isEmpty ? "All Currencies" : "Results") {
                ForEach(filtered) { row(for: $0) }
            }
        }
        .searchable(text: $query, prompt: "Search by name or code")
        .overlay {
            if !query.isEmpty, filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private var pinned: [Currency] {
        let byCode = Dictionary(currencies.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        return pinnedCodes.compactMap { byCode[$0] }
    }

    private var filtered: [Currency] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let sorted = currencies.sorted { $0.code < $1.code }
        guard !trimmed.isEmpty else { return sorted }
        return sorted.filter {
            $0.code.localizedCaseInsensitiveContains(trimmed) || $0.currency.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func row(for currency: Currency) -> some View {
        Button {
            selection = currency.code
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currency.currency)
                        .foregroundStyle(.primary)
                    Text(currency.code)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selection == currency.code {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(selection == currency.code ? .isSelected : [])
    }

    /// The device locale's currency, then USD, EUR, and GBP, without duplicates.
    static func suggestedCodes(locale: Locale = .autoupdatingCurrent) -> [String] {
        var codes: [String] = []
        for code in [locale.currency?.identifier, "USD", "EUR", "GBP"].compactMap(\.self) where !codes.contains(code) {
            codes.append(code)
        }
        return codes
    }
}

/// A form row that shows the selected currency and pushes a `CurrencyList` to change it.
/// Must sit inside a `NavigationStack`.
struct CurrencyPickerLink: View {
    let title: LocalizedStringKey
    let currencies: [Currency]
    var pinnedCodes: [String] = []
    @Binding var selection: String?

    var body: some View {
        NavigationLink {
            CurrencyList(currencies: currencies, pinnedCodes: pinnedCodes, selection: $selection)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            LabeledContent(title) {
                Text(selection ?? String(localized: "None"))
            }
        }
    }
}

#Preview {
    @Previewable @State var selection: String? = "EUR"
    NavigationStack {
        CurrencyList(
            currencies: [
                Currency(code: "USD", currency: "US Dollar"),
                Currency(code: "EUR", currency: "Euro"),
                Currency(code: "JPY", currency: "Yen", digits: 0),
            ],
            pinnedCodes: ["USD"],
            selection: $selection
        )
        .navigationTitle("Currency")
    }
}
