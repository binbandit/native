import Foundation

public struct TaskInstructionLocation: Codable, Hashable, Sendable {
    public enum Scope: String, Codable, Sendable { case project, user }
    public let scope: Scope
    public let directory: String
    public let environmentKey: String?
    public let names: [String]
    public let firstExisting: Bool

    public init(
        scope: Scope, directory: String = "", environmentKey: String? = nil,
        names: [String], firstExisting: Bool = false
    ) {
        self.scope = scope
        self.directory = directory
        self.environmentKey = environmentKey
        self.names = names
        self.firstExisting = firstExisting
    }
}
