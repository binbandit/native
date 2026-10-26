#if DEBUG
import NativePolicy
import SessionTools
import SwiftUI

/// Inert plugin tools for the isolated playtest path; opt in with -taskWellPluginFixture YES.
struct TaskWellFixturePlugin: NativePlugin {
    let manifest = PluginManifest(
        id: "review-kit", name: "Review Kit", description: "Release checks, a runbook and review notes.")
    var capabilities: Set<PolicyCapability>? { [] }

    // Match an installed plugin's admission so a live policy change can revoke an open pane.
    func isAllowed(by policy: NativePolicy) -> Bool { policy.allowsPlugin(manifest.id) }

    var sessionTools: [SessionToolContribution] {
        [
            SessionToolContribution(
                spec: SessionToolSpec(id: "review-kit.checks", places: [.side, .fact, .off], defaultPlace: .side),
                title: "Release verification and acceptance checks", systemImage: "checklist",
                summary: "Check the release branch, narrow Changes layouts and keyboard navigation before landing.",
                fact: { _ in
                    SessionToolFact(
                        text: "APP-42 · Checking narrow Changes layouts and keyboard navigation", accessory: .working)
                },
                pane: { _ in
                    AnyView(
                        EmptyStateView(
                            "Review APP-42", systemImage: "checklist",
                            message: "Check the narrow layout, then the keyboard path."))
                }),
            SessionToolContribution(
                spec: SessionToolSpec(id: "review-kit.runbook", places: [.side, .off], defaultPlace: .off),
                title: "Runbook", systemImage: "book",
                summary: "The project's checks before landing. Starts off until you choose to use it.",
                fact: { _ in SessionToolFact(text: "2 checks before landing") },
                pane: { _ in
                    AnyView(
                        EmptyStateView(
                            "Ready to check", systemImage: "book", message: "Build, then review the changes."))
                }),
            SessionToolContribution(
                spec: SessionToolSpec(id: "review-kit.notes", places: [.fact, .off], defaultPlace: .fact),
                title: "Notes", systemImage: "note.text", summary: "Review notes for the current ticket.",
                fact: { _ in
                    SessionToolFact(text: "APP-42 · Failed: long line wrapping needs another look", accessory: .failed)
                },
                pane: { _ in
                    AnyView(
                        EmptyStateView(
                            "Review notes", systemImage: "note.text",
                            message: "Keep the gutter fixed while the words wrap."))
                }),
            SessionToolContribution(
                spec: SessionToolSpec(id: "changes", places: [.side, .off], defaultPlace: .side),
                title: "Impostor", systemImage: "xmark"),
        ]
    }
}
#endif
