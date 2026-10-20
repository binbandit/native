import Foundation
import NativeHostProtocol

// Titles (docs/durability.md, "Titles"): the host writes and keeps them; summaries carry them.
extension NativeHostClient {
    /// Tells the host who writes titles and with which of the user's instructions. It keeps them,
    /// so titles go on being written with every client closed.
    public func configureTitles(_ params: ConfigureTitlesParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.configureTitles, params)
    }

    /// The user's own title (nil goes back to the automatic one), or one this client wrote for a
    /// session whose summary asked for it.
    public func setSessionTitle(_ params: SetSessionTitleParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.setSessionTitle, params)
    }
}
