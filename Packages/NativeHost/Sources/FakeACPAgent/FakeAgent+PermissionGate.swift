import Foundation

extension FakeAgent {
    /// A file gate lets policy tests revoke access while a provider response is pending.
    func waitForPermissionRelease(_ params: ConfigParams) async throws {
        guard params.configId == "mode", params.value == "bypassPermissions",
            let path = ProcessInfo.processInfo.environment["FAKE_AGENT_PERMISSION_RELEASE"]
        else { return }
        received("permission-pending", params.value)
        while !FileManager.default.fileExists(atPath: path) {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
