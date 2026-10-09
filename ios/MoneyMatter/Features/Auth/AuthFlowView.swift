import SwiftUI

/// The signed-out experience: sign in, with sign up pushed on top.
struct AuthFlowView: View {
    var body: some View {
        NavigationStack {
            SignInView()
        }
    }
}
