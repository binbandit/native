import ACP
import Foundation

/// The agent identity survives closing and reopening a host task.
public struct HostTaskIdentity: Codable, Hashable, Sendable {
    public var agentID: String
    public var agentSessionID: SessionID

    public init(agentID: String, agentSessionID: SessionID) {
        self.agentID = agentID
        self.agentSessionID = agentSessionID
    }
}

public struct HostCoordinator: Codable, Hashable, Sendable {
    public var task: HostTaskIdentity
    public var hostSessionID: HostSessionID?
    public var projectPath: String
    public var assignments: [HostTaskIdentity]

    public init(
        task: HostTaskIdentity, projectPath: String, assignments: [HostTaskIdentity],
        hostSessionID: HostSessionID? = nil
    ) {
        self.task = task
        self.hostSessionID = hostSessionID
        self.projectPath = projectPath
        self.assignments = assignments
    }
}

public struct NewCoordinatorParams: Codable, Sendable {
    public var task: NewSessionParams
    public var assignments: [HostTaskIdentity]

    public init(task: NewSessionParams, assignments: [HostTaskIdentity]) {
        self.task = task
        self.assignments = assignments
    }
}

public extension HostProtocol.Method {
    static let newCoordinator = "_native/coordinators/new"
    static let listCoordinators = "_native/coordinators/list"
    static let setCoordinator = "_native/coordinators/set"
    static let coordinatorsChanged = "_native/coordinators/changed"
}
