import Foundation

public struct TaskInstructionFile: Equatable, Sendable, Identifiable {
    public let url: URL
    public let scope: TaskInstructionLocation.Scope
    public let bytes: Int?
    public var id: URL { url }
}
