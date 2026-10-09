import MoneyMatterKit
import SafariServices
import SwiftUI

/// Settings › Plan & Billing: the current plan, trial, and entitlements, with Stripe checkout
/// and the customer portal opened in Safari. Self-hosted servers and demo users have no billing.
struct PlanBillingScreen: View {
    @Environment(AppServices.self) private var services

    @State private var state: LoadState<SettingsBillingAccount> = .idle
    @State private var cycle: SettingsBillingCycle = .year
    @State private var pendingAction: String?
    @State private var safariPage: BillingSafariPage?
    @State private var alert: ErrorAlert?

    var body: some View {
        content
            .navigationTitle("Plan & Billing")
            .task { if case .idle = state { await load() } }
            .refreshable { await load() }
            .sheet(item: $safariPage, onDismiss: { Task { await load() } }) { page in
                PlanBillingSafariView(url: page.url)
                    .ignoresSafeArea()
            }
            .errorAlert($alert)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            Form {
                Section("Current Plan") {
                    Text("Plus · Monthly")
                    Text("Renews on January 1")
                }
            }
            .redactedWhileLoading(true)
        case .failed(let error):
            LoadFailedView(error: error) { await load() }
        case .loaded(let account):
            if SettingsBillingOverview.canSeeBilling(account: account), let entitlements = account.entitlements {
                loaded(SettingsBillingOverview(entitlements: entitlements))
            } else {
                ContentUnavailableView {
                    Label("Billing Not Available", systemImage: "creditcard")
                } description: {
                    if account.role == .demo {
                        Text("Demo accounts can't change plans.")
                    } else {
                        Text("This server doesn't use plans. Every feature is included.")
                    }
                }
            }
        }
    }

    private func loaded(_ overview: SettingsBillingOverview) -> some View {
        Form {
            statusSection(overview)
            if overview.showsTrialProgress, let left = overview.trialDaysLeft {
                trialSection(left: left)
            }
            Section {
                Picker("Billing Cycle", selection: $cycle) {
                    Text("Monthly").tag(SettingsBillingCycle.month)
                    Text("Yearly").tag(SettingsBillingCycle.year)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Save up to \(Self.maxYearlySavingsPercent)% with yearly billing. Prices are in USD before tax; checkout shows your local currency.")
            }
            ForEach(SettingsBillingTier.purchasable) { tier in
                tierSection(tier, overview: overview)
            }
            entitlementsSection(overview.entitlements)
            if overview.canManageBilling {
                Section {
                    actionButton(id: "portal") {
                        Label("Manage Billing", systemImage: "creditcard")
                    } perform: {
                        try await client().send(Endpoints.settingsBillingPortal())
                    }
                } footer: {
                    Text("Update your payment method, download invoices, or cancel in the Stripe customer portal.")
                }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func statusSection(_ overview: SettingsBillingOverview) -> some View {
        let entitlements = overview.entitlements
        Section("Current Plan") {
            if let subscription = overview.liveSubscription {
                let endsAt = subscription.scheduledChange?.effectiveAt ?? subscription.currentPeriodEndsAt
                HStack {
                    Text("\(Self.name(subscription.tier)) · \(Self.name(subscription.billingCycle))")
                        .font(.headline)
                    Spacer()
                    statusBadge(for: subscription)
                }
                LabeledContent("Price") {
                    Text("\(Self.usd(subscription.tier.displayPrice(cycle: subscription.billingCycle))) \(Self.per(subscription.billingCycle))")
                        .monospacedDigit()
                }
                if let endsAt {
                    LabeledContent(Self.dateLabel(for: subscription)) {
                        Text(endsAt, format: .dateTime.day().month().year())
                    }
                }
                if let seats = entitlements.seats {
                    LabeledContent("Seats", value: seats.formatted())
                }
                if subscription.status == .pastDue {
                    Text("Your last payment failed. Update your payment method to keep access.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if subscription.status == .paused {
                    Text("Your subscription is paused. Resume it from the billing portal.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if subscription.scheduledChange?.action == .cancel {
                    Text("Your subscription is canceled and won't renew. No further charges.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if subscription.billingCycle == .month {
                    Text("Switch to yearly billing to save \(Self.usd(subscription.tier.yearlySavings)) a year.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let plan = entitlements.plan, plan != .unknown {
                HStack {
                    Text("\(Self.name(plan)), Lifetime")
                        .font(.headline)
                    Spacer()
                    Self.badge(Text("Lifetime"), tint: .green)
                }
                Text("A lifetime plan: no payments due.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let seats = entitlements.seats {
                    LabeledContent("Seats", value: seats.formatted())
                }
            } else if entitlements.readOnly {
                HStack {
                    Text(overview.hasSubscriptions ? "Subscription Ended" : "Trial Ended")
                        .font(.headline)
                    Spacer()
                    Self.badge(Text("Read-Only"), tint: .orange)
                }
                Text("Your data is safe but read-only. Choose a plan to keep adding transactions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let left = overview.trialDaysLeft {
                HStack {
                    Text("Free Trial: \(left) days left")
                        .font(.headline)
                        .monospacedDigit()
                    Spacer()
                    Self.badge(Text("Trial"), tint: .blue)
                }
                if let ends = entitlements.trialEndsAt {
                    LabeledContent("Trial Ends") {
                        Text(ends, format: .dateTime.day().month().year())
                    }
                }
                Text("No card needed during the trial. Restoring backups isn't included in the trial.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No active plan")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func trialSection(left: Int) -> some View {
        let total = SettingsBillingOverview.trialDays
        let used = max(0, total - left)
        let urgent = left <= SettingsBillingOverview.trialUrgentDays
        return Section {
            ProgressView(value: Double(used), total: Double(total)) {
                Text("Trial")
            } currentValueLabel: {
                Text("Day \(used) of \(total)")
                    .monospacedDigit()
            }
            .tint(urgent ? .orange : .accentColor)
        }
    }

    private func tierSection(_ tier: SettingsBillingTier, overview: SettingsBillingOverview) -> some View {
        let action = overview.action(for: tier, cycle: cycle)
        return Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(Self.name(tier))
                        .font(.title3.bold())
                    if overview.isRecommended(tier) {
                        Self.badge(Text("Recommended"), tint: .accentColor)
                    }
                    Spacer()
                    Text("\(Self.usd(tier.displayPrice(cycle: cycle))) \(Self.per(cycle))")
                        .font(.headline)
                        .monospacedDigit()
                }
                Text(Self.summary(tier))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .padding(.vertical, 4)

            switch action {
            case .current:
                Label("Current Plan", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .checkout(let tier, let cycle):
                actionButton(id: "checkout-\(tier.rawValue)") {
                    Text("Get \(Self.name(tier))")
                } perform: {
                    try await client().send(Endpoints.settingsBillingCheckout(tier: tier, cycle: cycle))
                }
            case .portal(let switchPlan):
                actionButton(id: "portal-\(tier.rawValue)") {
                    if switchPlan {
                        Text("Switch to \(Self.name(tier)) (\(Self.name(cycle)))")
                    } else {
                        Text("Manage Billing")
                    }
                } perform: {
                    try await client().send(Endpoints.settingsBillingPortal(switchPlan: switchPlan))
                }
            }
        }
    }

    private func entitlementsSection(_ entitlements: SettingsBillingEntitlements) -> some View {
        Section("Included Features") {
            if entitlements.features.isEmpty {
                Text("No paid features right now.")
                    .foregroundStyle(.secondary)
            }
            ForEach(entitlements.features, id: \.self) { feature in
                Label(Self.featureName(feature), systemImage: Self.featureIcon(feature))
            }
        }
    }

    // MARK: Helpers

    private func actionButton<ButtonLabel: View>(
        id: String,
        @ViewBuilder label: () -> ButtonLabel,
        perform: @escaping () async throws -> URL
    ) -> some View {
        Button {
            Task {
                pendingAction = id
                defer { pendingAction = nil }
                do {
                    safariPage = BillingSafariPage(url: try await perform())
                } catch {
                    alert = ErrorAlert(error)
                }
            }
        } label: {
            HStack {
                label()
                Spacer()
                if pendingAction == id { ProgressView() }
            }
        }
        .disabled(pendingAction != nil)
    }

    private func client() throws -> APIClient {
        guard let client = services.client else { throw APIError.network(URLError(.notConnectedToInternet)) }
        return client
    }

    private func load() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await client.send(Endpoints.settingsBillingAccount()))
        } catch {
            let apiError = APIError(error)
            if !apiError.isCancellation { state = .failed(apiError) }
        }
    }

    @ViewBuilder
    private func statusBadge(for subscription: SettingsBillingSubscription) -> some View {
        switch subscription.status {
        case .pastDue: Self.badge(Text("Past Due"), tint: .red)
        case .paused: Self.badge(Text("Paused"), tint: .orange)
        default:
            if subscription.scheduledChange?.action == .cancel {
                Self.badge(Text("Ending"), tint: .orange)
            } else {
                Self.badge(Text("Active"), tint: .green)
            }
        }
    }

    private static func badge(_ text: Text, tint: Color) -> some View {
        text
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
    }

    private static func dateLabel(for subscription: SettingsBillingSubscription) -> String {
        if subscription.status == .paused { return String(localized: "Resumes On") }
        if subscription.status == .pastDue { return String(localized: "Access Until") }
        if subscription.scheduledChange?.action == .cancel { return String(localized: "Ends On") }
        return String(localized: "Renews On")
    }

    private static var maxYearlySavingsPercent: Int {
        SettingsBillingTier.purchasable.map { tier -> Int in
            let yearAtMonthly = tier.displayPrice(cycle: .month) * 12
            let percent = NSDecimalNumber(decimal: tier.yearlySavings / yearAtMonthly * 100).doubleValue
            return Int(percent.rounded())
        }.max() ?? 0
    }

    private static func usd(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }

    private static func per(_ cycle: SettingsBillingCycle) -> String {
        cycle == .year ? String(localized: "/ year") : String(localized: "/ month")
    }

    private static func name(_ cycle: SettingsBillingCycle) -> String {
        cycle == .year ? String(localized: "Yearly") : String(localized: "Monthly")
    }

    private static func name(_ tier: SettingsBillingTier) -> String {
        switch tier {
        case .essential: String(localized: "Essential")
        case .plus, .unknown: String(localized: "Plus")
        }
    }

    private static func name(_ plan: SettingsBillingPlan) -> String {
        switch plan {
        case .essential: String(localized: "Essential")
        case .plus: String(localized: "Plus")
        case .earlyAdopter, .unknown: String(localized: "Early Adopter")
        }
    }

    private static func summary(_ tier: SettingsBillingTier) -> String {
        switch tier {
        case .essential:
            String(localized: "Imports, investments, your own AI key, backups, MCP, and data export for up to 2 people.")
        case .plus, .unknown:
            String(localized: "Everything in Essential, plus bank connections and built-in AI for up to 5 people.")
        }
    }

    private static func featureName(_ feature: String) -> String {
        switch feature {
        case "bank_providers": String(localized: "Bank connections")
        case "operator_ai": String(localized: "Built-in AI")
        case "backup_export": String(localized: "Backup export")
        case "backup_restore": String(localized: "Backup restore")
        case "data_export": String(localized: "Data export")
        case "attachments": String(localized: "Attachments")
        default: feature.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func featureIcon(_ feature: String) -> String {
        switch feature {
        case "bank_providers": "building.columns"
        case "operator_ai": "sparkles"
        case "backup_export": "externaldrive"
        case "backup_restore": "arrow.counterclockwise"
        case "data_export": "square.and.arrow.up"
        case "attachments": "paperclip"
        default: "checkmark.circle"
        }
    }
}

private struct BillingSafariPage: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Stripe's hosted checkout and portal, shown in-app.
private struct PlanBillingSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
