import Foundation

/// The agent owns OAuth, including PKCE, state validation and token storage. Native only opens its
/// authorization URL and, when the callback is on another machine, returns the pasted address.
public struct MCPAuthorizationLink: Equatable, Sendable {
    public let url: URL
    private let redirect: URLComponents
    private let state: String

    public init?(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            Self.isWebURL(components),
            Self.value("response_type", in: components) == "code",
            let state = Self.value("state", in: components), !state.isEmpty,
            let address = Self.value("redirect_uri", in: components),
            let redirect = URLComponents(string: address), Self.isLoopback(redirect),
            redirect.scheme == "http", redirect.user == nil, redirect.password == nil,
            redirect.fragment == nil
        else { return nil }
        self.url = url
        self.redirect = redirect
        self.state = state
    }

    /// Never sends arbitrary text to a terminal, or a callback belonging to another sign-in.
    public func callback(_ text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 8_192, !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
            let value = URLComponents(string: text),
            value.scheme == redirect.scheme, value.host == redirect.host, value.port == redirect.port,
            value.path == redirect.path, value.user == nil, value.password == nil, value.fragment == nil,
            Self.value("state", in: value) == state,
            Self.value("code", in: value)?.isEmpty == false || Self.value("error", in: value)?.isEmpty == false
        else { return nil }
        return value.url
    }

    private static func value(_ name: String, in components: URLComponents) -> String? {
        let matches = components.queryItems?.filter { $0.name == name } ?? []
        return matches.count == 1 ? matches.first?.value : nil
    }

    private static func isLoopback(_ components: URLComponents) -> Bool {
        ["localhost", "127.0.0.1", "[::1]", "::1"].contains(components.host?.lowercased() ?? "")
    }

    private static func isWebURL(_ components: URLComponents) -> Bool {
        guard components.user == nil, components.password == nil, components.host?.isEmpty == false else {
            return false
        }
        return components.scheme == "https" || (components.scheme == "http" && isLoopback(components))
    }
}
