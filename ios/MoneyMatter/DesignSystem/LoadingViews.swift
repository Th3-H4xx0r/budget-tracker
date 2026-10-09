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
/// while the rest of the screen is fine.
struct InlineRetryView: View {
    let message: String
    let retry: () async -> Void
    @State private var isRetrying = false

    init(_ message: String, retry: @escaping () async -> Void) {
        self.message = message
        self.retry = retry
    }

    var body: some View {
        HStack(spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button {
                isRetrying = true
                Task {
                    await retry()
                    isRetrying = false
                }
            } label: {
                if isRetrying {
                    ProgressView()
                } else {
                    Text("Retry")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRetrying)
        }
        .frame(minHeight: 44)
    }
}

/// A full-screen failure state with a Try Again action.
struct LoadFailedView: View {
    let error: APIError
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(ErrorMessage.title(for: error), systemImage: "exclamationmark.triangle")
        } description: {
            Text(ErrorMessage.message(for: error))
        } actions: {
            Button("Try Again") {
                Task { await retry() }
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Placeholder rows shaped like `TransactionRow`, redacted, for list loading states.
struct TransactionRowsPlaceholder: View {
    var count = 5

    var body: some View {
        ForEach(0..<count, id: \.self) { _ in
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Placeholder payee")
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
