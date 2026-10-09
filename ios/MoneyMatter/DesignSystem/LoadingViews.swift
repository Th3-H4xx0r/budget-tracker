import MoneyMatterKit
import SwiftUI

/// The lifecycle of one async load, for view models.
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(APIError)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var error: APIError? {
        if case .failed(let error) = self { return error }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

extension LoadState: Equatable where Value: Equatable {}

extension View {
    /// Shows the view as a redacted placeholder while loading, and blocks interaction.
    func redactedWhileLoading(_ isLoading: Bool) -> some View {
        self
            .redacted(reason: isLoading ? .placeholder : [])
            .allowsHitTesting(!isLoading)
            .accessibilityHidden(isLoading)
    }
}

/// A compact failure row with a Retry button, for a card or section that failed to load
/// while the rest of the screen is fine. Drawn as an `ErrorRow`.
struct InlineRetryView: View {
    let message: String
    let retry: () async -> Void

    init(_ message: String, retry: @escaping () async -> Void) {
        self.message = message
        self.retry = retry
    }

    var body: some View {
        ErrorRow(message, retry: retry)
    }
}

/// A full-screen failure state: the error's title and message as an `ErrorRow` with Retry,
/// centred on the screen.
struct LoadFailedView: View {
    let error: APIError
    let retry: () async -> Void

    var body: some View {
        ErrorRow(title: ErrorMessage.title(for: error), message: ErrorMessage.message(for: error), retry: retry)
            .padding(DS.Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Placeholder rows shaped like `TransactionRow`, redacted, for list loading states.
struct TransactionRowsPlaceholder: View {
    var count = 5

    var body: some View {
        ForEach(0..<count, id: \.self) { _ in
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: IconTileMetrics.size * DS.Radius.iconTileFraction, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(width: IconTileMetrics.size, height: IconTileMetrics.size)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Placeholder payee")
                        .font(.headline)
                    Text(verbatim: "Account · 12:00")
                        .font(.subheadline)
                }
                Spacer()
                Text(verbatim: "$00.00")
            }
            .redacted(reason: .placeholder)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    List {
        InlineRetryView("Couldn't load review status") {}
        TransactionRowsPlaceholder(count: 3)
    }
}
