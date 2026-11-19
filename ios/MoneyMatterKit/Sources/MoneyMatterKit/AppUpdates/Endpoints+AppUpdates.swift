import Foundation

extension Endpoints {
    /// `GET /app-updates/latest`: the offer when the server holds an iOS build newer than
    /// `installedBuild`; otherwise says whether it is up to date or has a build it can't install.
    public static func latestAppUpdate(installedBuild: Int) -> Endpoint<AppUpdateAnswer> {
        var query = QueryBuilder()
        query.add("platform", "ios")
        query.add("build", installedBuild)
        return Endpoint<AppUpdateLatestResponse>(.get, "/app-updates/latest", query: query.items)
            .map { AppUpdateAnswer($0, installed: installedBuild) }
    }

    /// `GET /app-updates/install-status`: whether iOS has started downloading the build the
    /// `token` names.
    public static func appUpdateInstallStarted(token: String) -> Endpoint<Bool> {
        var query = QueryBuilder()
        query.add("token", token)
        return Endpoint<AppUpdateInstallStatusResponse>(.get, "/app-updates/install-status", query: query.items)
            .map(\.started)
    }
}
