#if os(macOS)
import Foundation
import Security

/// Runs scripts in `native-script-runtime`: a V8 isolate in its own process, signed into the App
/// Sandbox with no network and no files. Each run is a fresh process that ends with the script.
///
/// Scripts run only on hosts. A client (an iPad, a Mac connected to another host) asks its host to
/// run one; this type isn't available there.
public struct ScriptRunner: Sendable {
    /// Where an app embeds the runtime, relative to its bundle.
    public static let embeddedPath = "Contents/Helpers/native-script-runtime"

    public let helper: URL

    /// A runner for the runtime at `helper`. Unless `requireSandbox` is false (for tests of an
    /// unsigned development build), the runtime must carry a valid signature with the App Sandbox
    /// entitlement: without it a script that escaped V8 would have the user's full access.
    public init(helper: URL, requireSandbox: Bool = true) throws {
        guard FileManager.default.isExecutableFile(atPath: helper.path(percentEncoded: false)) else {
            throw ScriptRunnerError.missing(helper)
        }
        if requireSandbox && !Self.isSandboxed(helper) {
            throw ScriptRunnerError.notSandboxed(helper)
        }
        self.helper = helper
    }

    /// The runtime embedded in `bundle`, or nil when this build doesn't include one (cargo wasn't
    /// installed when it was built). Throws if it's there but not sandboxed.
    public static func embedded(in bundle: Bundle = .main) throws -> ScriptRunner? {
        let helper = bundle.bundleURL.appending(path: embeddedPath)
        guard FileManager.default.fileExists(atPath: helper.path(percentEncoded: false)) else { return nil }
        return try ScriptRunner(helper: helper)
    }

    /// Runs `code`, an ES module body with top-level `await`, and returns what it printed and how it
    /// ended. Script failures, including running out of time, are in the result's `failure`; this
    /// throws only when the script can't be started, and `CancellationError` when cancelled.
    public func run(
        _ code: String,
        bindings: [ScriptBinding] = [],
        inputs: [String: String] = [:],
        limits: ScriptLimits = .standard
    ) async throws -> ScriptRunResult {
        _ = try ScriptSession.index(bindings)
        let transport: ScriptProcessTransport
        do {
            transport = try ScriptProcessTransport(
                helper: helper, arguments: ["--max-heap-mib", String(limits.heapMiB)])
        } catch {
            throw ScriptRunnerError.launchFailed(error.localizedDescription)
        }
        return try await ScriptSession.run(
            code: code, bindings: bindings, inputs: inputs, limits: limits, transport: transport)
    }

    /// Whether `helper` has an intact signature that puts it in the App Sandbox.
    static func isSandboxed(_ helper: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(helper as CFURL, [], &staticCode) == errSecSuccess, let staticCode,
            SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess
        else { return false }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
            let information = information as? [String: Any],
            let entitlements = information[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        else { return false }
        return entitlements["com.apple.security.app-sandbox"] as? Bool == true
    }
}

public enum ScriptRunnerError: LocalizedError, Sendable, Hashable {
    case missing(URL)
    case notSandboxed(URL)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missing(let helper):
            "The script runtime isn't at \(helper.path(percentEncoded: false)). Build it with scripts/build-script-runtime.sh."
        case .notSandboxed(let helper):
            "The script runtime at \(helper.path(percentEncoded: false)) isn't signed into the App Sandbox, so it won't be run."
        case .launchFailed(let reason):
            "The script runtime didn't start: \(reason)"
        }
    }
}
#endif
