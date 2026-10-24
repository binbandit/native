import NativeHostProtocol
import Observation
import SwiftUI

/// Window-owned navigation and task state outlive a split view's column transitions.
@Observable
final class CompanionNavigation {
    var selection: CompanionDestination?
    private var tasks: [TaskRoute: CompanionTaskState] = [:]

    func state(for route: TaskRoute) -> CompanionTaskState {
        if let state = tasks[route] { return state }
        let state = CompanionTaskState()
        tasks[route] = state
        return state
    }
}

enum CompanionDestination: Hashable {
    case task(TaskRoute)
    case host(HostID)
    case allTasks(HostID)
}

struct TaskRoute: Hashable {
    let hostID: HostID
    let sessionID: HostSessionID
}
