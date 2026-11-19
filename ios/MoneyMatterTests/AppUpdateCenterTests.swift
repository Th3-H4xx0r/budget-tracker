import Foundation
import MoneyMatterKit
import SwiftUI
import Testing
@testable import MoneyMatter

private actor StubUpdateService: AppUpdateServing {
    var answer: AppUpdateAnswer
    var fails = false
    var latestDelay: Duration = .zero
    var startedAfter: Int
    private(set) var statusPolls = 0
    private(set) var latestCalls: [Int] = []

    init(offer: AppUpdateOffer?, startedAfter: Int = 1) {
        self.answer = offer.map(AppUpdateAnswer.offer) ?? .upToDate
        self.startedAfter = startedAfter
    }

    func setFails(_ value: Bool) { fails = value }
    func setAnswer(_ value: AppUpdateAnswer) { answer = value }
    func setLatestDelay(_ value: Duration) { latestDelay = value }

    func latest(installedBuild: Int) async throws -> AppUpdateAnswer {
        latestCalls.append(installedBuild)
        try? await Task.sleep(for: latestDelay)
        if fails { throw APIError.network(URLError(.notConnectedToInternet)) }
        return answer
    }

    func installStarted(token: String) async throws -> Bool {
        statusPolls += 1
        return statusPolls >= startedAfter
    }
}

@MainActor
@Suite("AppUpdateCenter")
struct AppUpdateCenterTests {
    private static let offer = AppUpdateOffer(
        build: 7,
        version: "1.1",
        notes: "- New",
        installURL: URL(string: "itms-services://?action=download-manifest&url=https%3A%2F%2Fx.dev%2Fota%2Fm%2Ftok.plist")!
    )

    @Test("A check with a newer build stores the offer for the installed build")
    func checkFindsOffer() async {
        let service = StubUpdateService(offer: Self.offer)
        let center = AppUpdateCenter(installedBuild: 3, service: service)

        let outcome = await center.check()

        #expect(outcome == .available)
        #expect(center.offer == Self.offer)
        #expect(await service.latestCalls == [3])
    }

    @Test("A failed check keeps the offer in hand and reports failure")
    func failedCheckKeepsOffer() async {
        let service = StubUpdateService(offer: Self.offer)
        let center = AppUpdateCenter(installedBuild: 3, service: service)
        await center.check()
        await service.setFails(true)

        #expect(await center.check() == .failed)
        #expect(center.offer == Self.offer)
    }

    @Test("Without a service a check fails")
    func noService() async {
        let center = AppUpdateCenter(installedBuild: 3)
        #expect(await center.check() == .failed)
    }

    @Test("Not Now hides the offer until a user-initiated check")
    func laterAndCheckNow() async {
        let center = AppUpdateCenter(installedBuild: 3, service: StubUpdateService(offer: Self.offer))
        center.scenePhaseChanged(to: .active)
        await center.check()
        #expect(center.shouldPresent)

        center.later()
        #expect(!center.shouldPresent)

        await center.checkNow()
        #expect(center.shouldPresent)
    }

    @Test("Not Now is forgotten once the app returns from the background")
    func laterResetsOnBackground() async {
        let center = AppUpdateCenter(installedBuild: 3, service: StubUpdateService(offer: Self.offer))
        center.scenePhaseChanged(to: .active)
        await center.check()
        center.later()
        #expect(!center.shouldPresent)

        center.scenePhaseChanged(to: .background)
        center.scenePhaseChanged(to: .active)

        #expect(center.shouldPresent)
    }

    @Test("A newer build the server won't give a link for is reported as not installable")
    func notInstallable() async {
        let service = StubUpdateService(offer: Self.offer)
        await service.setAnswer(.notInstallable)
        let center = AppUpdateCenter(installedBuild: 3, service: service)

        #expect(await center.check() == .notInstallable)
        #expect(center.lastOutcome == .notInstallable)
        #expect(center.offer == nil)
    }

    @Test("A check that finds nothing newer drops the offer in hand")
    func upToDateClearsOffer() async {
        let service = StubUpdateService(offer: Self.offer)
        let center = AppUpdateCenter(installedBuild: 3, service: service)
        await center.check()
        await service.setAnswer(.upToDate)

        #expect(await center.check() == .upToDate)
        #expect(center.offer == nil)
    }

    @Test("Overlapping checks share one request")
    func concurrentChecks() async {
        let service = StubUpdateService(offer: Self.offer)
        await service.setLatestDelay(.milliseconds(30))
        let center = AppUpdateCenter(installedBuild: 3, service: service)

        async let first = center.check()
        async let second = center.check()
        let outcomes = await [first, second]

        #expect(outcomes == [.available, .available])
        #expect(await service.latestCalls.count == 1)
    }

    @Test("Installing stays true for the whole watch, so a second tap does nothing")
    func installingDuringWatch() async {
        let service = StubUpdateService(offer: Self.offer, startedAfter: .max)
        var opened = 0
        let center = AppUpdateCenter(
            installedBuild: 3,
            service: service,
            openURL: { _ in opened += 1; return true },
            quit: {},
            pollInterval: .milliseconds(40),
            pollLimit: 3
        )

        await center.install()
        #expect(center.installing)

        await center.install()
        #expect(opened == 1)
        #expect(await service.latestCalls.count == 1)

        await center.installWatch?.value
        #expect(!center.installing)
    }

    @Test("The offer is not presented in the background")
    func notInBackground() async {
        let center = AppUpdateCenter(installedBuild: 3, service: StubUpdateService(offer: Self.offer))
        await center.check()
        #expect(!center.shouldPresent)
    }

    @Test("Install opens the link and quits once the server saw the download")
    func installQuitsOnceStarted() async {
        let service = StubUpdateService(offer: Self.offer, startedAfter: 3)
        var opened: [URL] = []
        var quits = 0
        let center = AppUpdateCenter(
            installedBuild: 3,
            service: service,
            openURL: { opened.append($0); return true },
            quit: { quits += 1 },
            pollInterval: .milliseconds(1),
            pollLimit: 20
        )

        await center.install()
        await center.installWatch?.value

        #expect(opened == [Self.offer.installURL])
        #expect(quits == 1)
        #expect(await service.statusPolls == 3)
    }

    @Test("A cancelled install confirm never quits")
    func installNeverStarted() async {
        let service = StubUpdateService(offer: Self.offer, startedAfter: .max)
        var quits = 0
        let center = AppUpdateCenter(
            installedBuild: 3,
            service: service,
            openURL: { _ in true },
            quit: { quits += 1 },
            pollInterval: .milliseconds(1),
            pollLimit: 5
        )

        await center.install()
        await center.installWatch?.value

        #expect(quits == 0)
        #expect(await service.statusPolls == 5)
    }

    @Test("Install reports an error when the server can't be reached")
    func installWithoutServer() async {
        let service = StubUpdateService(offer: Self.offer)
        await service.setFails(true)
        var opened = false
        let center = AppUpdateCenter(installedBuild: 3, service: service, openURL: { _ in opened = true; return true })

        await center.install()

        #expect(center.error != nil)
        #expect(!opened)
        #expect(!center.installing)
    }

    @Test("Install reports an error when iOS refuses the link")
    func installOpenRefused() async {
        let center = AppUpdateCenter(
            installedBuild: 3,
            service: StubUpdateService(offer: Self.offer),
            openURL: { _ in false }
        )

        await center.install()

        #expect(center.error != nil)
        #expect(center.installWatch == nil)
        #expect(!center.installing)
    }
}
