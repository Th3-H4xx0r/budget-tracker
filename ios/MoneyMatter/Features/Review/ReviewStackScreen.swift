import MoneyMatterKit
import SwiftUI

/// The review card stack, presented as a full-screen cover by `AppRouter.presentReviewStack`.
struct ReviewStackScreen: View {
    let request: ReviewStackRequest

    @Environment(AppServices.self) private var services
    /// Created once on appear; building it in `body` would make a new session per evaluation.
    @State private var session: ReviewSession?

    var body: some View {
        if let session {
            ReviewStackContent(request: request, session: session)
        } else {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
                .onAppear {
                    session = services.review.makeReviewSession()
                }
        }
    }
}

/// A committed decision, the trigger for haptics.
private struct ReviewCommit: Equatable {
    let sequence: Int
    let decision: ReviewDecision
}

private struct ReviewStackContent: View {
    let request: ReviewStackRequest
    let session: ReviewSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGSize = .zero
    @State private var cardOpacity: Double = 1
    @State private var isCommitting = false
    @State private var lastCommit: ReviewCommit?
    @State private var alert: ErrorAlert?
    @State private var isClosing = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                content(width: proxy.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            session.onSubmitError = { error, _, _ in
                alert = ErrorAlert(error)
            }
            session.onLoadMoreError = { error in
                alert = ErrorAlert(error)
            }
            if !session.hasStarted {
                await session.start(total: request.expectedTotal)
            }
        }
        .sensoryFeedback(trigger: lastCommit) { _, commit in
            switch commit?.decision {
            case .reviewed: .success
            case .checkLater: .impact(weight: .light)
            case .fraud: .warning
            case nil: nil
            }
        }
        .onChange(of: session.current?.id) { _, newID in
            // VoiceOver moves to the new card instead of staying on a stale element.
            if newID != nil, UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
        }
        .errorAlert($alert)
    }

    // MARK: Content

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        if let transaction = session.current {
            VStack(spacing: 24) {
                Spacer(minLength: 0)
                card(transaction, width: width)
                    .id(transaction.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                Spacer(minLength: 0)
                actionButtons(width: width)
            }
        } else if let error = session.loadError {
            LoadFailedView(error: error) {
                await session.retry()
            }
        } else if session.isFinished {
            finishedState
        } else {
            ProgressView()
        }
    }

    private func card(_ transaction: Transaction, width: CGFloat) -> some View {
        let threshold = width / 3
        return ReviewCardView(transaction: transaction, lean: Double(dragOffset.width / threshold))
            .offset(x: dragOffset.width, y: dragOffset.height * 0.2)
            .rotationEffect(.degrees(Double(dragOffset.width / 20)), anchor: .bottom)
            .opacity(cardOpacity)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard !isCommitting else { return }
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        guard !isCommitting else { return }
                        let distance = value.translation.width
                        if distance > threshold {
                            commit(.reviewed, cardWidth: width)
                        } else if distance < -threshold {
                            commit(.checkLater, cardWidth: width)
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                dragOffset = .zero
                            }
                        }
                    }
            )
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Swipe right if it looks good, left to check later."))
            .accessibilityAction(named: Text("Looks Good")) { commit(.reviewed, cardWidth: width) }
            .accessibilityAction(named: Text("Check Later")) { commit(.checkLater, cardWidth: width) }
            .accessibilityAction(named: Text("Fraud")) { commit(.fraud, cardWidth: width) }
    }

    private func actionButtons(width: CGFloat) -> some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    commit(.fraud, cardWidth: width)
                } label: {
                    Label("Fraud", systemImage: "exclamationmark.shield")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
                .tint(.red)

                Button {
                    commit(.checkLater, cardWidth: width)
                } label: {
                    Label("Check Later", systemImage: "clock")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)

                Button {
                    commit(.reviewed, cardWidth: width)
                } label: {
                    Label("Looks Good", systemImage: "checkmark")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(.green)
            }
            .labelStyle(StackedActionLabelStyle())
            .font(.subheadline.weight(.semibold))
        }
        .disabled(isCommitting)
    }

    private var finishedState: some View {
        ContentUnavailableView {
            Label("All Caught Up", systemImage: "checkmark.seal")
        } description: {
            if session.deferredCount > 0 {
                Text("^[\(session.deferredCount) transaction](inflect: true) saved for later.")
            } else {
                Text("You've reviewed every transaction.")
            }
        } actions: {
            Button("Done") { close() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if isClosing {
                ProgressView()
            } else {
                Button(role: .close) { close() }
            }
        }
        ToolbarItem(placement: .principal) {
            if session.total > 0 {
                Text("\(session.position) of \(session.total)")
                    .font(.headline)
                    .monospacedDigit()
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Undo", systemImage: "arrow.uturn.backward") {
                undo()
            }
            .disabled(!session.canUndo || isCommitting)
        }
    }

    // MARK: Actions

    /// Animates the card off (or fades it with Reduce Motion), then records the decision.
    private func commit(_ decision: ReviewDecision, cardWidth: CGFloat) {
        guard !isCommitting, let expectedID = session.current?.id else { return }
        isCommitting = true
        lastCommit = ReviewCommit(sequence: (lastCommit?.sequence ?? 0) + 1, decision: decision)

        let finish = {
            // A rolled-back write can put another card in front during the animation; then
            // nothing is decided and that card simply appears.
            session.act(decision, expectedID: expectedID)
            var reset = SwiftUI.Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) {
                dragOffset = .zero
            }
            withAnimation(reduceMotion ? .easeIn(duration: 0.15) : .snappy) {
                cardOpacity = 1
            }
            isCommitting = false
        }

        if reduceMotion || decision == .fraud {
            withAnimation(.easeOut(duration: 0.2)) {
                cardOpacity = 0
            } completion: {
                finish()
            }
        } else {
            let direction: CGFloat = decision == .reviewed ? 1 : -1
            withAnimation(.easeIn(duration: 0.22)) {
                dragOffset = CGSize(width: direction * max(cardWidth * 1.5, 400), height: dragOffset.height)
                cardOpacity = 0
            } completion: {
                finish()
            }
        }
    }

    /// The undone card comes back through the card's insertion transition.
    private func undo() {
        _ = withAnimation(reduceMotion ? .easeIn(duration: 0.15) : .snappy) {
            session.undo()
        }
    }

    /// Waits for queued writes first, so a failure still reaches the user (the card comes
    /// back with an alert) instead of being lost behind the dismissed cover.
    private func close() {
        guard !isClosing else { return }
        isClosing = true
        Task {
            await session.whenSettled()
            NotificationCenter.default.post(name: .reviewStatusesDidChange, object: nil)
            isClosing = false
            if alert == nil { dismiss() }
        }
    }
}

/// Icon above title, so three actions fit side by side at large text sizes.
private struct StackedActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) {
            configuration.icon
                .font(.title3)
            configuration.title
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
