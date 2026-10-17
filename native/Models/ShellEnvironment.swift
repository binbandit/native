import Foundation

/// The user's login-shell environment, read once and shared. Agents launch with it, and features
/// that run the user's own tools (git, gh) need its PATH just the same.
final class ShellEnvironment {
    private var reading: Task<[String: String], Never>?

    /// The environment, read on first use; `refresh` reads it again, to pick up shell changes.
    func current(refresh: Bool = false) async -> [String: String] {
        if refresh || reading == nil {
            // Callers that arrive while a read is under way share it rather than start their own.
            reading = Task { await LoginShell.environment() }
        }
        return await reading?.value ?? [:]
    }
}
