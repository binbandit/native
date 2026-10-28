import ACP
import AIInstructions
import Foundation

extension SessionModel {
    func refineTitleAfterFirstTurn(succeeded: Bool) {
        let messages = state.items.compactMap { item -> TranscriptMessage? in
            if case .message(let message) = item { return message }
            return nil
        }
        guard messages.filter({ $0.role == .user && !$0.wasSteered }).count == 1 else { return }
        let outcome = succeeded ? messages.filter { $0.role == .agent }.map(\.text).joined(separator: "\n") : ""
        Task {
            let previous = services.titles.namedTitle(for: titleKey)
            await services.titles.refineIfNeeded(
                for: titleKey, outcome: outcome, using: services.plugins.titler,
                instructions: AIInstructionsStore.shared.addition(for: .title, in: cwd),
                isAllowed: { self.services.plugins.titler != nil })
            if let title = services.titles.namedTitle(for: titleKey), title != previous {
                services.titleLanded(key, cwd, title)
            }
        }
    }
}
