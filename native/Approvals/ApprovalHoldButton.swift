import ApprovalAnalysis
import SwiftUI

struct ApprovalHoldButton: View {
    let shortcutsEnabled: Bool
    var keyboardHeld = false
    var forceReducedMotion = false
    var didCommit: () -> Void = {}
    let allow: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isEnabled) private var isEnabled
    @State private var hold = ApprovalHold()
    @State private var progress: Double = 0
    @State private var pending: Task<Void, Never>?

    private var allowed: Bool {
        if case .allowed = hold.state { return true }
        return false
    }
    private var confirming: Bool {
        if case .confirming = hold.state { return true }
        return false
    }

    var body: some View {
        Button {
            if PlatformApprovalHold.usesConfirmation { activateConfirmation() }
        } label: {
            ApprovalHoldLabel(
                progress: progress, allowed: allowed, confirming: confirming,
                shortcutsEnabled: shortcutsEnabled)
        }
        .buttonStyle(
            ApprovalActionStyle(
                primary: true, acknowledgesCompletion: allowed,
                sweepProgress: reduceMotion || forceReducedMotion || allowed ? nil : progress,
                pressing: pressed)
        )
        .accessibilityLabel(allowed ? "Allowed" : confirming ? "Confirm Allow" : "Allow, can't be undone")
        .accessibilityHint("Activate twice within five seconds to allow.")
        .accessibilityAction { activateConfirmation() }
        .onChange(of: keyboardHeld) { _, down in
            if PlatformApprovalHold.usesConfirmation {
                if down { activateConfirmation() }
            } else {
                pressed(down)
            }
        }
        .onDisappear {
            // Crossing the threshold commits the answer. Leaving during its acknowledgement
            // must not silently turn an already displayed "Allowed" back into a pending ask.
            if !allowed { pending?.cancel(); hold.cancel() }
        }
        .onChange(of: isEnabled) { _, enabled in if !enabled { cancel() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancel() } }
    }

    private func pressed(_ down: Bool) {
        guard !allowed, !PlatformApprovalHold.usesConfirmation else { return }
        if !down { cancel(); return }
        guard hold.state == .idle else { return }
        hold.begin(at: ProcessInfo.processInfo.systemUptime)
        withAnimation(.linear(duration: ApprovalHold.duration)) { progress = 1 }
        pending = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(ApprovalHold.duration)) } catch { return }
            if hold.advance(to: ProcessInfo.processInfo.systemUptime) { acknowledge() }
        }
    }

    private func cancel() {
        guard !allowed else { return }
        pending?.cancel()
        hold.cancel()
        withAnimation(DS.Approval.cancelAnimation) { progress = 0 }
    }

    private func activateConfirmation() {
        guard !allowed else { return }
        pending?.cancel()
        if hold.accessibleActivate(at: ProcessInfo.processInfo.systemUptime) {
            progress = 1
            acknowledge()
        } else {
            pending = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(ApprovalHold.confirmationDuration)) } catch { return }
                hold.advance(to: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    private func acknowledge() {
        didCommit()
        PlatformApprovalHold.acknowledge()
        pending = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(ApprovalHold.acknowledgementDuration)) } catch { return }
            allow()
        }
    }
}

#if DEBUG
#Preview("Hold to allow - interactive") {
    DSPreviewPair {
        ApprovalHoldButton(shortcutsEnabled: true) {}.padding(DS.Space.xl)
    }
}
#endif
