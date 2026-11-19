import Foundation

public enum AppUpdateRules {
    /// The card shows only while the app is in front, and not for the build the user put off
    /// with "Not Now" during this app session. A newer build shows again.
    public static func shouldShow(_ offer: AppUpdateOffer?, foreground: Bool, laterBuild: Int?) -> Bool {
        guard let offer, foreground else { return false }
        return offer.build != laterBuild
    }
}
