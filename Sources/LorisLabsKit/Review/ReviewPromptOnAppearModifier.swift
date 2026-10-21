import SwiftUI
import StoreKit

/// Waits for a real completion and a quiet, active scene. Navigation never records a completion.
public struct ReviewPromptOnAppearModifier: ViewModifier {
    private let manager: SmartReviewPromptManager
    private let isIdle: Bool
    private let additionalEligibility: @MainActor () -> Bool
    @State private var interacting = false
    @Environment(\.scenePhase) private var scenePhase
    #if !os(tvOS) && !os(watchOS)
    @Environment(\.requestReview) private var requestReview
    #endif

    public init(manager: SmartReviewPromptManager, isIdle: Bool = true,
                additionalEligibility: @escaping @MainActor () -> Bool = { true }) {
        self.manager = manager; self.isIdle = isIdle
        self.additionalEligibility = additionalEligibility
    }
    private struct Context: Equatable {
        let completion: UUID?
        let active: Bool
        let idle: Bool
    }
    public func body(content: Content) -> some View {
        #if os(tvOS) || os(watchOS)
        content
        #else
        let context = Context(completion: manager.completionToken, active: scenePhase == .active,
                              idle: isIdle && !interacting && !manager.interactionInProgress)
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in interacting = true }
                .onEnded { _ in interacting = false }
        )
        .onDisappear { manager.cancelPendingReview() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { manager.cancelPendingReview() }
        }
        .task(id: context) {
            await manager.requestAfterPause(isSceneActive: { context.active },
                                            isIdle: { context.idle && additionalEligibility() }) {
                requestReview()
            }
        }
        #endif
    }
}

public extension View {
    /// Attach to a completion scene; set isIdle=false during sheets, alerts, editing or navigation.
    /// additionalEligibility rechecks native window/modal state immediately before the attempt.
    func reviewPromptWhenIdle(_ manager: SmartReviewPromptManager, isIdle: Bool = true,
                             additionalEligibility: @escaping @MainActor () -> Bool = { true }) -> some View {
        modifier(ReviewPromptOnAppearModifier(manager: manager, isIdle: isIdle,
                                             additionalEligibility: additionalEligibility))
    }
    /// Compatibility entry point. Also requires recordCompletedAction() in the current session.
    func reviewPromptOnAppear(_ manager: SmartReviewPromptManager) -> some View {
        reviewPromptWhenIdle(manager)
    }
}
