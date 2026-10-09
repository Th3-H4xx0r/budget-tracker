import Foundation

/// Plans a user can hold. `earlyAdopter` is a hand-granted lifetime plan, never sold.
public enum SettingsBillingPlan: String, LenientEnum, CaseIterable {
    case essential
    case plus
    case earlyAdopter = "early_adopter"
    case unknown
}

/// Plans that can be bought.
public enum SettingsBillingTier: String, LenientEnum, CaseIterable, Identifiable {
    case essential
    case plus
    case unknown

    public var id: String { rawValue }

    public static let purchasable: [SettingsBillingTier] = [.essential, .plus]
    public static let recommended: SettingsBillingTier = .plus

    /// Headline USD prices, tax excluded; the hosted checkout shows the buyer's currency and tax.
    public func displayPrice(cycle: SettingsBillingCycle) -> Decimal {
        switch (self, cycle) {
        case (.essential, .year): 30
        case (.plus, .month): 8
        case (.plus, .year): 55
        default: 5
        }
    }

    /// What a year costs less when paid yearly.
    public var yearlySavings: Decimal { displayPrice(cycle: .month) * 12 - displayPrice(cycle: .year) }
}

public enum SettingsBillingCycle: String, LenientEnum, CaseIterable, Identifiable {
    case month
    case year
    case unknown

    public var id: String { rawValue }
}

public enum SettingsBillingStatus: String, LenientEnum, CaseIterable {
    case active
    case trialing
    case pastDue = "past_due"
    case paused
    case canceled
    case unknown

    /// Statuses that grant access while the paid period lasts.
    public var isEntitled: Bool { self == .active || self == .trialing || self == .pastDue }
    /// A canceled subscription never charges again.
    public var isTerminal: Bool { self == .canceled }
}

public struct SettingsBillingScheduledChange: Sendable, Hashable, Decodable {
    public enum Action: String, LenientEnum, CaseIterable {
        case cancel
        case resume
        case unknown
    }

    public let action: Action
    public let effectiveAt: Date?
}

public struct SettingsBillingSubscription: Sendable, Hashable, Decodable {
    public let externalSubscriptionId: String
    public let tier: SettingsBillingTier
    public let status: SettingsBillingStatus
    public let billingCycle: SettingsBillingCycle
    public let currentPeriodEndsAt: Date?
    public let scheduledChange: SettingsBillingScheduledChange?

    public init(
        externalSubscriptionId: String,
        tier: SettingsBillingTier,
        status: SettingsBillingStatus,
        billingCycle: SettingsBillingCycle,
        currentPeriodEndsAt: Date?,
        scheduledChange: SettingsBillingScheduledChange? = nil
    ) {
        self.externalSubscriptionId = externalSubscriptionId
        self.tier = tier
        self.status = status
        self.billingCycle = billingCycle
        self.currentPeriodEndsAt = currentPeriodEndsAt
        self.scheduledChange = scheduledChange
    }

    private enum CodingKeys: String, CodingKey {
        case externalSubscriptionId, tier, status, billingCycle, currentPeriodEndsAt, scheduledChange
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        externalSubscriptionId = (try? container.decodeIfPresent(String.self, forKey: .externalSubscriptionId)) ?? ""
        tier = (try? container.decodeIfPresent(SettingsBillingTier.self, forKey: .tier)) ?? .unknown
        status = (try? container.decodeIfPresent(SettingsBillingStatus.self, forKey: .status)) ?? .unknown
        billingCycle = (try? container.decodeIfPresent(SettingsBillingCycle.self, forKey: .billingCycle)) ?? .unknown
        currentPeriodEndsAt = try? container.decodeIfPresent(Date.self, forKey: .currentPeriodEndsAt)
        scheduledChange = try? container.decodeIfPresent(SettingsBillingScheduledChange.self, forKey: .scheduledChange)
    }
}

/// The full entitlements object from `GET /user`, including subscriptions and seats.
public struct SettingsBillingEntitlements: Sendable, Hashable, Decodable {
    public let features: [String]
    public let readOnly: Bool
    public let seats: Int?
    public let plan: SettingsBillingPlan?
    public let trialEndsAt: Date?
    public let subscriptions: [SettingsBillingSubscription]

    public init(
        features: [String] = [],
        readOnly: Bool = false,
        seats: Int? = nil,
        plan: SettingsBillingPlan? = nil,
        trialEndsAt: Date? = nil,
        subscriptions: [SettingsBillingSubscription] = []
    ) {
        self.features = features
        self.readOnly = readOnly
        self.seats = seats
        self.plan = plan
        self.trialEndsAt = trialEndsAt
        self.subscriptions = subscriptions
    }

    private enum CodingKeys: String, CodingKey { case features, readOnly, seats, plan, trialEndsAt, subscriptions }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        features = (try? container.decodeIfPresent([String].self, forKey: .features)) ?? []
        readOnly = (try? container.decodeIfPresent(Bool.self, forKey: .readOnly)) ?? false
        seats = try? container.decodeIfPresent(Int.self, forKey: .seats)
        plan = try? container.decodeIfPresent(SettingsBillingPlan.self, forKey: .plan)
        trialEndsAt = try? container.decodeIfPresent(Date.self, forKey: .trialEndsAt)
        subscriptions = (try? container.decodeIfPresent([SettingsBillingSubscription].self, forKey: .subscriptions)) ?? []
    }
}

/// The parts of `GET /user` the Plan & Billing screen needs.
public struct SettingsBillingAccount: Sendable, Hashable, Decodable {
    public let role: UserRole
    public let entitlements: SettingsBillingEntitlements?

    public init(role: UserRole, entitlements: SettingsBillingEntitlements?) {
        self.role = role
        self.entitlements = entitlements
    }

    private enum CodingKeys: String, CodingKey { case role, entitlements }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = (try? container.decodeIfPresent(UserRole.self, forKey: .role)) ?? .unknown
        entitlements = try? container.decodeIfPresent(SettingsBillingEntitlements.self, forKey: .entitlements)
    }
}

/// What the screen offers for one tier.
public enum SettingsBillingTierAction: Sendable, Hashable {
    /// The user's current plan: nothing to buy.
    case current
    /// Hosted checkout for a new subscription.
    case checkout(tier: SettingsBillingTier, cycle: SettingsBillingCycle)
    /// The customer portal, optionally on its plan-switch flow.
    case portal(switchPlan: Bool)
}

/// Plan & Billing state derived from entitlements, mirroring the web view model.
public struct SettingsBillingOverview: Sendable, Hashable {
    public static let trialDays = 40
    public static let trialUrgentDays = 7
    /// Self-hosted servers grant every feature with this many seats; billing has no meaning there.
    static let selfHostSeats = 10

    public let entitlements: SettingsBillingEntitlements
    public let now: Date

    public init(entitlements: SettingsBillingEntitlements, now: Date = .now) {
        self.entitlements = entitlements
        self.now = now
    }

    /// The web shows billing only on cloud servers and never to demo users. The API has no
    /// explicit flag, so a self-hosted server is recognized by its fixed self-host seat grant.
    public static func canSeeBilling(account: SettingsBillingAccount) -> Bool {
        guard account.role != .demo, let entitlements = account.entitlements else { return false }
        return entitlements.seats != selfHostSeats
    }

    /// The subscription the plan card speaks for: not canceled and still inside its period.
    public var liveSubscription: SettingsBillingSubscription? {
        entitlements.subscriptions.first { subscription in
            guard !subscription.status.isTerminal, let ends = subscription.currentPeriodEndsAt else { return false }
            return ends > now
        }
    }

    /// The tier the user currently pays for, if the subscription still grants access.
    public var activeTier: SettingsBillingTier? {
        guard let subscription = liveSubscription, subscription.status.isEntitled else { return nil }
        return subscription.tier
    }

    /// The tier of the most recent ended subscription, offered as "Subscribe Again".
    public var lastTier: SettingsBillingTier? {
        guard liveSubscription == nil else { return nil }
        return entitlements.subscriptions.first { $0.status.isTerminal }?.tier
    }

    public var hasSubscriptions: Bool { !entitlements.subscriptions.isEmpty }

    /// Whole days left in the free trial, or `nil` when there's no trial running.
    public var trialDaysLeft: Int? {
        guard let ends = entitlements.trialEndsAt, entitlements.plan == nil else { return nil }
        guard !entitlements.subscriptions.contains(where: { !$0.status.isTerminal }) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: ends)).day ?? 0
        return max(0, days)
    }

    public var showsTrialProgress: Bool {
        trialDaysLeft != nil && liveSubscription == nil && !entitlements.readOnly
    }

    public func isCurrent(_ tier: SettingsBillingTier, cycle: SettingsBillingCycle) -> Bool {
        if entitlements.plan?.rawValue == tier.rawValue { return true }
        return activeTier == tier && liveSubscription?.billingCycle == cycle
    }

    public func isRecommended(_ tier: SettingsBillingTier) -> Bool {
        activeTier == nil && entitlements.plan == nil && tier == (lastTier ?? SettingsBillingTier.recommended)
    }

    public func action(for tier: SettingsBillingTier, cycle: SettingsBillingCycle) -> SettingsBillingTierAction {
        if isCurrent(tier, cycle: cycle) { return .current }
        if activeTier != nil { return .portal(switchPlan: true) }
        if liveSubscription != nil { return .portal(switchPlan: false) }
        return .checkout(tier: tier, cycle: cycle)
    }

    /// The portal manages payment methods, invoices, and cancellation once the user has ever subscribed.
    public var canManageBilling: Bool { hasSubscriptions }
}

extension Endpoints {
    struct SettingsBillingCheckoutBody: Encodable, Sendable {
        let tier: String
        let cycle: String
    }

    struct SettingsBillingPortalBody: Encodable, Sendable {
        let flow: String?
    }

    struct SettingsBillingURLResponse: Decodable, Sendable {
        let url: URL
    }

    /// `GET /user`, decoded for its role and full entitlements.
    public static func settingsBillingAccount() -> Endpoint<SettingsBillingAccount> {
        Endpoint(.get, "/user")
    }

    /// `POST /billing/checkout`: a Stripe-hosted checkout URL. 404 on self-hosted servers.
    public static func settingsBillingCheckout(tier: SettingsBillingTier, cycle: SettingsBillingCycle) -> Endpoint<URL> {
        Endpoint<SettingsBillingURLResponse>(
            .post,
            "/billing/checkout",
            body: SettingsBillingCheckoutBody(tier: tier.rawValue, cycle: cycle.rawValue)
        )
        .map(\.url)
    }

    /// `POST /billing/portal`: the Stripe customer portal, optionally on its plan-switch flow.
    public static func settingsBillingPortal(switchPlan: Bool = false) -> Endpoint<URL> {
        Endpoint<SettingsBillingURLResponse>(
            .post,
            "/billing/portal",
            body: SettingsBillingPortalBody(flow: switchPlan ? "subscription_update" : nil)
        )
        .map(\.url)
    }
}
