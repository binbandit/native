import SwiftUI

/// Starts or stops an AI draft. Disabled with the reason when Apple Intelligence isn't available.
struct DraftWithAIButton: View {
    let isDrafting: Bool
    let action: () -> Void

    var body: some View {
        let unavailable = PullRequestDrafter.unavailableReason
        Button(action: action) {
            Label(isDrafting ? "Stop Drafting" : "Draft with AI", systemImage: isDrafting ? "stop.fill" : "sparkles")
        }
        .buttonStyle(.ds(.ghost))
        .disabled(unavailable != nil)
        .help(unavailable ?? "Write the title and description from this branch's commits and changes, on this Mac")
    }
}
