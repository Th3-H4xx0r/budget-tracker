import SwiftUI

/// Opens the invitation review sheet for any URL the app receives that carries
/// `?invitation_token=`, matching the web dashboard's handling of invite links.
///
/// Attach once near the root of the signed-in UI with `.shareInvitationLinks()`.
struct ShareInvitationLinkHandler: ViewModifier {
    private struct Target: Identifiable {
        let token: String
        var id: String { token }
    }

    @State private var target: Target?

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                if let token = Self.token(in: url) { target = Target(token: token) }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL, let token = Self.token(in: url) { target = Target(token: token) }
            }
            .sheet(item: $target) { target in
                ShareInvitationReviewSheet(token: target.token)
            }
    }

    static func token(in url: URL) -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let token = items.first(where: { $0.name == "invitation_token" })?.value, !token.isEmpty else { return nil }
        return token
    }
}

extension View {
    /// Handles `?invitation_token=` links. See `ShareInvitationLinkHandler`.
    func shareInvitationLinks() -> some View {
        modifier(ShareInvitationLinkHandler())
    }
}
