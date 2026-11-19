import MoneyMatterKit
import Observation
import SwiftUI
import UIKit

/// What the update flow asks of the server.
nonisolated protocol AppUpdateServing: Sendable {
    /// What the server holds relative to `installedBuild`.
    func latest(installedBuild: Int) async throws -> AppUpdateAnswer
    /// Whether iOS has started downloading the build the install `token` names.
    func installStarted(token: String) async throws -> Bool
}

/// The update calls over the signed-in `APIClient`, so they carry the bearer session and the
/// Cloudflare Access headers.
nonisolated struct LiveAppUpdateService: AppUpdateServing {
    let client: APIClient

    func latest(installedBuild: Int) async throws -> AppUpdateAnswer {
        try await client.send(Endpoints.latestAppUpdate(installedBuild: installedBuild))
    }

    func installStarted(token: String) async throws -> Bool {
        try await client.send(Endpoints.appUpdateInstallStarted(token: token))
    }
}

/// Over-the-air updates: asks the server for a newer build, shows it as an offer, and installs
/// it through an `itms-services` link. iOS won't install over a running app, so once it starts
/// downloading the build the app steps out to the Home Screen and quits.
@MainActor
@Observable
final class AppUpdateCenter {
    enum CheckOutcome: Equatable {
        case available
        case upToDate
        /// The server has a newer build but gave no install link (it only does so over https).
        case notInstallable
        /// The server couldn't be asked; the offer in hand is left as it was.
        case failed
    }

    private(set) var offer: AppUpdateOffer?
    private(set) var isChecking = false
    private(set) var installing = false
    private(set) var error: String?
    private(set) var lastOutcome: CheckOutcome?
    private(set) var installWatch: Task<Void, Never>?

    private var foreground = false
    private var wasBackgrounded = true
    private var laterBuild: Int?
    @ObservationIgnored private let overlay = OverlayWindow()
    @ObservationIgnored private var checkTask: Task<CheckOutcome, Never>?
    @ObservationIgnored private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    @ObservationIgnored private var service: (any AppUpdateServing)?
    @ObservationIgnored private let installedBuild: Int
    @ObservationIgnored private let openURL: @MainActor (URL) async -> Bool
    @ObservationIgnored private let quit: @MainActor () -> Void
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private let pollLimit: Int

    /// This build's number (`CFBundleVersion`; `1` is an unstamped dev build, which the server never updates).
    static var bundleBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    init(
        installedBuild: Int = AppUpdateCenter.bundleBuild,
        service: (any AppUpdateServing)? = nil,
        openURL: @escaping @MainActor (URL) async -> Bool = { await UIApplication.shared.open($0) },
        quit: @escaping @MainActor () -> Void = AppUpdateCenter.suspendAndExit,
        pollInterval: Duration = .seconds(1),
        pollLimit: Int = 180
    ) {
        self.installedBuild = installedBuild
        self.service = service
        self.openURL = openURL
        self.quit = quit
        self.pollInterval = pollInterval
        self.pollLimit = pollLimit
    }

    /// Points the center at the connected server's client; `nil` when there is none.
    func use(_ service: (any AppUpdateServing)?) {
        self.service = service
    }

    /// Whether the offer card may show now: in front, and not for a build put off with "Not Now".
    var shouldPresent: Bool {
        AppUpdateRules.shouldShow(offer, foreground: foreground, laterBuild: laterBuild)
    }

    func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .active:
            foreground = true
            // "Not Now" lasts until the app goes away and comes back.
            if wasBackgrounded { laterBuild = nil }
            wasBackgrounded = false
            updatePresentation()
            Task { await check() }
        case .background:
            foreground = false
            wasBackgrounded = true
            updatePresentation()
        default:
            break
        }
    }

    /// Asks the server; a check already under way is joined, not repeated.
    @discardableResult
    func check() async -> CheckOutcome {
        if let checkTask { return await checkTask.value }
        let task = Task { await performCheck() }
        checkTask = task
        let outcome = await task.value
        checkTask = nil
        return outcome
    }

    private func performCheck() async -> CheckOutcome {
        guard let service else { return .failed }
        isChecking = true
        defer {
            isChecking = false
            updatePresentation()
        }
        let outcome: CheckOutcome
        do {
            switch try await service.latest(installedBuild: installedBuild) {
            case .offer(let found):
                offer = found
                outcome = .available
            case .upToDate:
                offer = nil
                outcome = .upToDate
            case .notInstallable:
                offer = nil
                outcome = .notInstallable
            }
        } catch {
            outcome = .failed
        }
        lastOutcome = outcome
        return outcome
    }

    /// A check the user asked for: an offer they put off with "Not Now" comes back.
    @discardableResult
    func checkNow() async -> CheckOutcome {
        laterBuild = nil
        return await check()
    }

    func later() {
        laterBuild = offer?.build
        updatePresentation()
    }

    /// `installing` stays true from the tap until the install watch ends, so a second tap
    /// can't mint a new link and cancel the watch.
    func install() async {
        guard !installing else { return }
        installing = true
        error = nil
        // The watch polls after the app goes to the background behind iOS's install confirm.
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "app-update-watch") { [weak self] in
            self?.endBackgroundWork()
        }
        // The link in hand may be minutes old and links expire, so only a fresh one goes.
        guard await check() != .failed else {
            error = String(localized: "Couldn't reach the server to start the install. Try again.")
            finishInstall()
            return
        }
        guard let offer else {
            finishInstall()
            return
        }
        // iOS takes it from here with its own confirm. The card stays, so a cancelled
        // confirm can be tried again.
        guard await openURL(offer.installURL) else {
            error = String(localized: "iOS couldn't open the install link.")
            finishInstall()
            return
        }
        if let token = offer.installToken {
            watchInstall(token: token)
        } else {
            finishInstall()
        }
    }

    private func finishInstall() {
        installing = false
        endBackgroundWork()
    }

    private func endBackgroundWork() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// iOS fetches the package only after the user taps Install on its confirm, so once the
    /// server has seen that fetch the app steps aside and quits. A Cancel never fetches.
    private func watchInstall(token: String) {
        installWatch = Task { [weak self] in
            guard let self else { return }
            defer { finishInstall() }
            for _ in 0..<pollLimit {
                try? await Task.sleep(for: pollInterval)
                guard !Task.isCancelled else { return }
                if (try? await service?.installStarted(token: token)) == true {
                    quit()
                    return
                }
            }
        }
    }

    private func updatePresentation() {
        if shouldPresent { overlay.show { AppUpdateCard(center: self) } } else { overlay.hide() }
    }

    /// Home first so it reads as stepping aside, not a crash; then gone.
    static func suspendAndExit() {
        let app = UIApplication.shared
        let task = app.beginBackgroundTask(withName: "app-update-quit")
        UIControl().sendAction(#selector(URLSessionTask.suspend), to: app, for: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            _ = task
            exit(0)
        }
    }
}
