import BackgroundTasks
import Foundation
import MoneyMatterKit
import UserNotifications

/// Money as budget alerts and the Home budget card show it: whole amounts without
/// decimals ("$1,388"), others with two ("$12.50").
enum MonthlyBudgetFormat {
    static func money(_ amount: Decimal, currencyCode: String, locale: Locale = .autoupdatingCurrent) -> String {
        var rounded = Decimal()
        var source = amount
        NSDecimalRound(&rounded, &source, 0, .plain)
        let digits = rounded == amount ? 0 : 2
        return amount.formatted(
            .currency(code: currencyCode)
                .locale(locale)
                .precision(.fractionLength(digits))
        )
    }

    /// Whole percent of the budget spent, rounded down: 0.8 reads as 80.
    static func percentUsed(spent: Decimal, budget: Decimal) -> Int {
        guard budget > 0 else { return 0 }
        var percent = spent * 100 / budget
        var floored = Decimal()
        NSDecimalRound(&floored, &percent, 0, .down)
        return NSDecimalNumber(decimal: floored).intValue
    }
}

/// The title and body of a budget notification.
struct MonthlyBudgetAlertMessage: Equatable {
    let title: String
    let body: String

    /// `nil` for `.none` or a snapshot without a budget.
    static func make(
        for threshold: BudgetThreshold,
        snapshot: MonthlySpendingSnapshot,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> MonthlyBudgetAlertMessage? {
        guard let budget = snapshot.budget, snapshot.hasBudget else { return nil }
        let money = { (amount: Decimal) in
            MonthlyBudgetFormat.money(amount, currencyCode: snapshot.currencyCode, locale: locale)
        }
        switch threshold {
        case .none:
            return nil
        case .over:
            let spent = money(snapshot.spent)
            let over = money(snapshot.overBy ?? 0)
            let limit = money(budget)
            return MonthlyBudgetAlertMessage(
                title: String(localized: "Over budget"),
                body: String(localized: "You've spent \(spent) this month, \(over) over your \(limit) budget.")
            )
        case .warning:
            let percent = MonthlyBudgetFormat.percentUsed(spent: snapshot.spent, budget: budget)
            let left = money(snapshot.remaining ?? 0)
            let today = calendar.component(.day, from: now)
            let daysLeft = max(snapshot.month.dayCount(calendar: calendar) - today, 0)
            let body: String = switch daysLeft {
            case 0: String(localized: "\(percent)% of your monthly budget used — \(left) left on the last day of the month.")
            case 1: String(localized: "\(percent)% of your monthly budget used — \(left) left with 1 day to go.")
            default: String(localized: "\(percent)% of your monthly budget used — \(left) left with \(daysLeft) days to go.")
            }
            return MonthlyBudgetAlertMessage(title: String(localized: "Nearing your monthly budget"), body: body)
        }
    }
}

/// Time-sensitive notifications when spending reaches 80 % and 100 % of the monthly budget,
/// once per threshold per month (`BudgetSnapshotStore` keys its bookkeeping by month, so a
/// new month re-arms both), plus the background refresh that keeps them and the widget
/// current while the app is closed.
enum MonthlyBudgetAlerts {
    /// Mirrors the server's `alertsEnabled` so the background refresh and the check can read
    /// it without another request.
    static let alertsEnabledKey = "monthlyBudgetAlertsEnabled"
    static let threadIdentifier = "monthly-budget"
    /// How long after a background refresh the next one may run.
    static let backgroundRefreshInterval: TimeInterval = 2 * 60 * 60

    static var alertsEnabled: Bool {
        get { SharedContainer.defaults.object(forKey: alertsEnabledKey) as? Bool ?? true }
        set { SharedContainer.defaults.set(newValue, forKey: alertsEnabledKey) }
    }

    /// The threshold to notify for `snapshot`: a reached threshold not yet notified this
    /// month, only with alerts on and a budget set.
    static func alertToSend(
        for snapshot: MonthlySpendingSnapshot,
        alertsEnabled: Bool,
        store: BudgetSnapshotStore
    ) -> BudgetThreshold? {
        guard alertsEnabled, snapshot.hasBudget,
              let pending = store.pendingAlert(for: snapshot), pending != .none
        else { return nil }
        return pending
    }

    /// Posts the due alert for `snapshot`, if any, and records it. Nothing is recorded while
    /// notifications aren't authorized, so the alert still fires once they are.
    @discardableResult
    static func check(
        snapshot: MonthlySpendingSnapshot,
        alertsEnabled: Bool = MonthlyBudgetAlerts.alertsEnabled,
        store: BudgetSnapshotStore = BudgetSnapshotStore()
    ) async -> BudgetThreshold? {
        guard let threshold = alertToSend(for: snapshot, alertsEnabled: alertsEnabled, store: store),
              let message = MonthlyBudgetAlertMessage.make(for: threshold, snapshot: snapshot)
        else { return nil }

        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard [.authorized, .provisional, .ephemeral].contains(status) else { return nil }

        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        content.threadIdentifier = threadIdentifier
        content.userInfo = ["url": SharedContainer.homeURL.absoluteString]
        let request = UNNotificationRequest(
            identifier: "\(threadIdentifier)-\(snapshot.month.key)-\(threshold.rawValue)",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            return nil
        }
        store.markNotified(threshold, in: snapshot.month)
        return threshold
    }

    /// Refreshes the widget snapshot and the mirrored alert setting, then posts any due
    /// alert. Returns the fresh snapshot, or `nil` when loading failed.
    @discardableResult
    static func refreshAndCheck(client: APIClient) async -> MonthlySpendingSnapshot? {
        async let settings = try? client.send(Endpoints.monthlyBudgetSettings())
        let snapshot = try? await MonthlyBudgetWidgetSync.refresh(client: client)
        if let settings = await settings {
            alertsEnabled = settings.alertsEnabled
        }
        guard let snapshot else { return nil }
        await check(snapshot: snapshot)
        return snapshot
    }

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: Background refresh

    /// Asks for the next `BGAppRefreshTask` about two hours from now, replacing any pending one.
    static func scheduleBackgroundRefresh(now: Date = .now) {
        let request = BGAppRefreshTaskRequest(identifier: SharedContainer.budgetRefreshTaskIdentifier)
        request.earliestBeginDate = now.addingTimeInterval(backgroundRefreshInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The `.appRefresh` task: reschedules itself, then refreshes and checks with a client
    /// built from the App Group server and shared Keychain token, which don't need the
    /// signed-in UI to have launched.
    static func runBackgroundRefresh() async {
        scheduleBackgroundRefresh()
        guard let server = SharedContainer.server() else { return }
        let tokenReader = SharedKeychainTokenReader(server: server)
        guard tokenReader.accessToken() != nil else { return }
        await refreshAndCheck(client: APIClient(server: server, tokenProvider: tokenReader))
    }

    /// On sign-out: the widget and the background refresh stop using the old account.
    static func sessionEnded() {
        MonthlyBudgetWidgetSync.clear()
        SharedContainer.defaults.removeObject(forKey: alertsEnabledKey)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: SharedContainer.budgetRefreshTaskIdentifier)
    }
}

/// Shows notifications while the app is open and hands a tapped notification's `url` to
/// `DeepLinkInbox`. Set as the notification center delegate at launch.
final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationDelegate()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let text = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: text)
        else { return }
        await MainActor.run {
            DeepLinkInbox.shared.receive(url)
        }
    }
}
