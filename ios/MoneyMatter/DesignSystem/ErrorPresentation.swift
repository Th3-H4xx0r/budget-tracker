import MoneyMatterKit
import SwiftUI

/// User-facing copy for API failures.
enum ErrorMessage {
    static func title(for error: APIError) -> String {
        switch error {
        case .planRequired: String(localized: "Not Available on Your Plan")
        case .baseCurrencyChangeInProgress: String(localized: "Base Currency Change in Progress")
        case .network: String(localized: "Can't Connect")
        case .validation: String(localized: "Couldn't Save")
        case .notFound: String(localized: "Not Found")
        case .unauthenticated: String(localized: "Signed Out")
        case .server: String(localized: "Something Went Wrong")
        case .decoding: String(localized: "Unexpected Response")
        }
    }

    static func message(for error: APIError) -> String {
        switch error {
        case .planRequired:
            String(localized: "Your server's plan doesn't allow this action.")
        case .baseCurrencyChangeInProgress:
            String(localized: "Wait for the base currency change to finish, then try again.")
        case .network:
            String(localized: "Check your connection and try again.")
        case .validation(let message, _, _):
            message.isEmpty ? String(localized: "Check the details and try again.") : message
        case .notFound:
            String(localized: "This item no longer exists.")
        case .unauthenticated:
            String(localized: "Your session ended. Sign in again.")
        case .server(_, _, let message):
            message ?? String(localized: "The server couldn't complete the request. Try again later.")
        case .decoding:
            String(localized: "The server sent a response the app can't read. Make sure the app and server are up to date.")
        }
    }

    /// One line for inline retry rows and form footers.
    static func inline(for error: any Error) -> String {
        message(for: APIError(error))
    }
}

/// An alert for a failed action. `nil` for cancellations, which never need one.
struct ErrorAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    init?(_ error: any Error) {
        if error is AuthenticationCancelled || error is CancellationError { return nil }
        let apiError = APIError(error)
        if apiError.isCancellation { return nil }
        self.init(title: ErrorMessage.title(for: apiError), message: ErrorMessage.message(for: apiError))
    }
}

extension View {
    /// Presents `alert` while it's non-nil. Use for mutations: plan required (402), base
    /// currency change in progress (423), and any other failed write.
    func errorAlert(_ alert: Binding<ErrorAlert?>) -> some View {
        self.alert(
            alert.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { alert.wrappedValue != nil },
                set: { if !$0 { alert.wrappedValue = nil } }
            ),
            presenting: alert.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { presented in
            Text(presented.message)
        }
    }
}
