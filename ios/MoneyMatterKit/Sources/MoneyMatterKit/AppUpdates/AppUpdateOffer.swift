import Foundation

/// A newer build the server is offering, from `GET /app-updates/latest`.
public struct AppUpdateOffer: Equatable, Sendable {
    public let build: Int
    public let version: String
    public let notes: String
    /// An `itms-services://` link that makes iOS download and install the build.
    public let installURL: URL
    /// Bytes to download; 0 when the server didn't say.
    public let size: Int64

    public init(build: Int, version: String, notes: String, installURL: URL, size: Int64 = 0) {
        self.build = build
        self.version = version
        self.notes = notes
        self.installURL = installURL
        self.size = size
    }

    /// The link's token, which names it to `GET /app-updates/install-status`: the last path
    /// component, minus `.plist`, of the manifest URL inside `itms-services://?…&url=…/ota/m/<token>.plist`.
    public var installToken: String? {
        guard let inner = URLComponents(url: installURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value,
              let name = URL(string: inner)?.lastPathComponent, name.hasSuffix(".plist")
        else { return nil }
        let token = String(name.dropLast(".plist".count))
        return token.isEmpty ? nil : token
    }
}

/// What `GET /app-updates/latest` came to for an installed build.
public enum AppUpdateAnswer: Equatable, Sendable {
    /// Nothing newer than the installed build.
    case upToDate
    case offer(AppUpdateOffer)
    /// A newer build exists but the server gave no usable install link (it withholds the link
    /// unless its address is https), so it can't be installed from here.
    case notInstallable

    init(_ response: AppUpdateLatestResponse, installed: Int) {
        guard response.available, let build = response.build, build > installed else {
            self = .upToDate
            return
        }
        guard let link = response.installUrl, let url = URL(string: link), url.scheme != nil else {
            self = .notInstallable
            return
        }
        self = .offer(AppUpdateOffer(
            build: build,
            version: response.version ?? "",
            notes: (response.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            installURL: url,
            size: response.size ?? 0
        ))
    }
}

/// The body of `GET /app-updates/latest`.
struct AppUpdateLatestResponse: Decodable, Sendable {
    let available: Bool
    let build: Int?
    let version: String?
    let notes: String?
    let size: Int64?
    let installUrl: String?
}

/// The body of `GET /app-updates/install-status`.
struct AppUpdateInstallStatusResponse: Decodable, Sendable {
    let started: Bool
}
