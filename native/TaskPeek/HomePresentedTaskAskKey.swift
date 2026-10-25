import SwiftUI

/// Home publishes the needs it renders in this window, including its visible Up next rows.
nonisolated enum HomePresentedTaskNeed: Hashable {
    case request(TaskPeekAsk.ID)
    case failure(SessionKey)
}

nonisolated struct HomePresentedTaskAskKey: PreferenceKey {
    static let defaultValue: Set<HomePresentedTaskNeed> = []

    static func reduce(value: inout Set<HomePresentedTaskNeed>, nextValue: () -> Set<HomePresentedTaskNeed>) {
        value.formUnion(nextValue())
    }
}

extension EnvironmentValues {
    @Entry var homePresentedTaskNeeds: Set<HomePresentedTaskNeed> = []
}
