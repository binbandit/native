import Exec
import Foundation
import Synchronization

/// Runs `"Native Host" pair --json` on another Mac over the user's own SSH: their keys, agent and
/// config, in BatchMode so it never prompts (there's no terminal to type a password into). Add Host
/// reads its events and pairs with the link; the command keeps the host's pairing window open until
/// it ends, and ending it closes the window.
public enum LinkSSHPairing {
    public enum Update: Sendable {
        case event(LinkPairCommandEvent)
        /// The SSH server wants the sign-in approved in a browser first (Tailscale SSH's check
        /// mode, for one): the session waits at this page until someone approves it.
        case needsApproval(URL)
        case ended(Ending)
    }

    /// How the command ended, as far as it matters to whoever is adding the host.
    public enum Ending: Hashable, Sendable {
        /// pair ran, and its events said what happened.
        case ran(exitCode: Int32)
        case ssh(SSHProblem, detail: String)
        case notInstalled
        /// Native is there, from before `pair`; its version when the script could read it.
        case tooOld(version: String?)
        case notAMac
        case failed(detail: String)
    }

    /// What ssh's own words say went wrong.
    public enum SSHProblem: Hashable, Sendable {
        /// It couldn't sign in without a password or passphrase.
        case signIn
        /// This Mac doesn't know, or no longer trusts, the other one's host key.
        case hostKey
        case unknownHost
        /// Nothing answered on the SSH port: Remote Login is off.
        case refused
        case unreachable
        /// The sign-in waited for approval in a browser (at this page) that didn't come in time.
        case notApproved(URL)
        case other
    }

    /// How the remote script ends when it can't run pair at all.
    enum ScriptStatus {
        static let notInstalled: Int32 = 120
        /// Native is there, from before `pair`: its version is on standard output.
        static let tooOld: Int32 = 121
        static let notAMac: Int32 = 122
        /// ssh's own failures: sign-in, host key, name, network.
        static let ssh: Int32 = 255
    }

    /// Whether `text` can go to ssh as a destination: `me@mac-mini.local`, `mini`, or an alias from
    /// the user's ssh config. Never an option (a leading dash), never spaces or a link.
    public static func isDestination(_ text: String) -> Bool {
        !text.isEmpty && !text.hasPrefix("-") && !text.contains("://")
            && text.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value != 0x7F && !$0.properties.isWhitespace }
    }

    /// Where the script looks for Native, as shell words: `$HOME` expands on the other Mac.
    public static let applicationFolders = ["'/Applications'", #""$HOME"/'Applications'"#]

    /// The script ssh runs. `sh -s` reads it from standard input, so the remote login shell (zsh,
    /// fish, anything) only has to start sh. It finds Native (`NATIVE_APP` if that Mac sets it,
    /// then this Mac's own edition first, so Native Nightly pairs with Native Nightly), checks its
    /// helper has `pair`, and runs it.
    public static func script(
        grants: LinkGrants, appName: String, folders: [String] = applicationFolders
    ) -> String {
        var flags = ["--json"]
        if grants.runCommands { flags.append("--run-commands") }
        if grants.manageHost { flags.append("--install-updates") }
        if grants.managePlugins { flags.append("--manage-plugins") }
        var names: [String] = []
        for name in [appName, "Native.app", "Native Nightly.app"] where name.hasSuffix(".app") && !names.contains(name)
        {
            names.append(name)
        }
        let candidates = names.flatMap { name in folders.map { "\($0)/\(quoted(name))" } }
        return """
            [ "$(uname -s)" = Darwin ] || exit \(ScriptStatus.notAMac)
            found=""
            for app in ${NATIVE_APP:+"$NATIVE_APP"} \(candidates.joined(separator: " ")); do
                if [ -d "$app" ]; then found=$app; break; fi
            done
            [ -n "$found" ] || exit \(ScriptStatus.notInstalled)
            helper="$found/Contents/Library/LoginItems/Native Host.app/Contents/MacOS/Native Host"
            # An older helper ignores its arguments and would start serving a host, so check first.
            # The whole folder: a development build keeps its code in a library beside the executable.
            if [ ! -x "$helper" ] || ! /usr/bin/grep -rqa \(quoted(LinkPairCommand.marker)) "${helper%/*}"; then
                /usr/bin/defaults read "$found/Contents/Info" CFBundleShortVersionString 2>/dev/null
                exit \(ScriptStatus.tooOld)
            fi
            exec "$helper" \(LinkPairCommand.name) \(flags.joined(separator: " "))

            """
    }

    #if os(macOS)
    /// Starts pair on `destination`; the stream yields each event it prints, then how it ended.
    /// Ending the stream's iteration stops ssh. `ssh` is the executable to run, on `environment`'s PATH.
    public static func pair(
        destination: String, grants: LinkGrants, appName: String, environment: [String: String],
        ssh: String = "ssh", folders: [String] = applicationFolders
    ) -> AsyncStream<Update> {
        let (stream, continuation) = AsyncStream.makeStream(of: Update.self)
        let lines = LineBuffer()
        let errorLines = LineBuffer()
        let askedForApproval = Mutex(false)
        let command = Command(
            ssh,
            [
                "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15", "--",
                destination, "/bin/sh -s",
            ],
            environment: environment,
            standardInput: Data(script(grants: grants, appName: appName, folders: folders).utf8),
            // A connection-sharing master ssh may keep the output open after this one exits.
            outputEndsAtExit: true)
        let running = Task {
            do {
                let result = try await LocalCommandRunner().run(command) { output in
                    let isOutput = output.stream == .standardOutput
                    for line in (isOutput ? lines : errorLines).append(output.data) {
                        if isOutput, let event = LinkPairCommandEvent(line: line) {
                            continuation.yield(.event(event))
                        } else if let url = approvalURL(in: line) {
                            let isFirst = askedForApproval.withLock { asked in
                                defer { asked = true }
                                return !asked
                            }
                            if isFirst { continuation.yield(.needsApproval(url)) }
                        }
                    }
                }
                continuation.yield(.ended(ending(result)))
            } catch is CancellationError {
                // Whoever stopped it isn't listening anymore.
            } catch {
                continuation.yield(.ended(.failed(detail: error.localizedDescription)))
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in running.cancel() }
        return stream
    }
    #endif

    static func ending(_ result: CommandResult) -> Ending {
        let detail = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        // Waiting for a browser approval ends however the server ends it; what it printed says why.
        if ![LinkPairCommand.ExitStatus.paired, LinkPairCommand.ExitStatus.failed].contains(result.exitCode),
            let url = (result.errorOutput + "\n" + result.output).split(separator: "\n").lazy
                .compactMap({ approvalURL(in: String($0)) }).first
        {
            return .ssh(.notApproved(url), detail: detail)
        }
        switch result.exitCode {
        case ScriptStatus.ssh:
            return .ssh(problem(in: detail), detail: detail)
        case ScriptStatus.notInstalled: return .notInstalled
        case ScriptStatus.notAMac: return .notAMac
        case ScriptStatus.tooOld:
            let version = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .tooOld(version: version.isEmpty ? nil : version)
        case LinkPairCommand.ExitStatus.paired, LinkPairCommand.ExitStatus.failed:
            return .ran(exitCode: result.exitCode)
        default:
            let detail = [result.errorOutput, result.output].joined(separator: "\n")
            return .failed(detail: detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func problem(in stderr: String) -> SSHProblem {
        func says(_ phrases: String...) -> Bool { phrases.contains { stderr.localizedCaseInsensitiveContains($0) } }
        if says("Host key verification failed", "REMOTE HOST IDENTIFICATION HAS CHANGED") { return .hostKey }
        if says("Permission denied", "Too many authentication failures") { return .signIn }
        if says("Could not resolve hostname", "nodename nor servname") { return .unknownHost }
        if says("Connection refused") { return .refused }
        if says("timed out", "No route to host", "Network is unreachable", "Host is down") { return .unreachable }
        return .other
    }

    /// The page a line sends the user to for approving the sign-in: "# To authenticate, visit:
    /// https://login.tailscale.com/a/…". Only a line that asks for it, so an ordinary URL in a
    /// login banner isn't taken for one.
    static func approvalURL(in line: String) -> URL? {
        let asks = ["authenticate", "approve", "visit", "additional check"].contains {
            line.localizedCaseInsensitiveContains($0)
        }
        guard asks, let start = line.range(of: "https://") else { return nil }
        let link = line[start.lowerBound...].prefix { !$0.isWhitespace && $0 != "\"" && $0 != "'" }
        return URL(string: String(link))
    }

    static func quoted(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: #"'\''"#))'"
    }
}

/// Splits output that arrives in pieces into whole lines.
private final class LineBuffer: Sendable {
    private let pending = Mutex(Data())

    func append(_ data: Data) -> [String] {
        pending.withLock { pending in
            pending.append(data)
            var lines: [String] = []
            while let newline = pending.firstIndex(of: 0x0A) {
                lines.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
                pending.removeSubrange(pending.startIndex...newline)
            }
            return lines
        }
    }
}
