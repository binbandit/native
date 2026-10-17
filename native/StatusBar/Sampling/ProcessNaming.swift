import Foundation

/// Readable names for processes from their arguments. Agents run as runtimes (node, bun, python)
/// whose executable name says nothing, so the script or package they run names them instead.
nonisolated enum ProcessNaming {
    private static let runtimes: Set<String> = ["node", "bun", "deno", "python", "python3", "ruby", "sh", "bash", "zsh", "env"]

    /// - Parameters:
    ///   - arguments: The process's argv; npm rewrites argv[0] to its title, such as
    ///     "npm exec @agentclientprotocol/claude-agent-acp@0.93.0".
    ///   - fallback: The kernel's short name, used when the arguments can't be read.
    static func name(arguments: [String], fallback: String) -> String {
        guard let first = arguments.first, !first.isEmpty else { return fallback }
        let words = first.split(separator: " ").map(String.init)
        if words.count > 1, let tool = words.first, ["npm", "npx", "pnpm", "bunx"].contains(tool) {
            return words.dropFirst().last(where: { !$0.hasPrefix("-") }).map(packageName) ?? tool
        }
        let executable = (first as NSString).lastPathComponent
        guard runtimes.contains(executable) else { return executable.isEmpty ? fallback : executable }
        // A runtime: name it after the first argument that isn't a flag, usually its script.
        guard let script = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) else { return executable }
        return "\(executable) \(scriptName(script))"
    }

    /// "@scope/claude-agent-acp@0.93.0" -> "claude-agent-acp".
    static func packageName(_ specifier: String) -> String {
        var name = specifier
        if let at = name.dropFirst().firstIndex(of: "@") {
            name = String(name[..<at])
        }
        return name.split(separator: "/").last.map(String.init) ?? name
    }

    /// A script inside an installed package is named by its package; anything else by its file.
    static func scriptName(_ path: String) -> String {
        let components = path.split(separator: "/").map(String.init)
        if let index = components.lastIndex(of: "node_modules"), index + 1 < components.count {
            let package = components[index + 1]
            if package.hasPrefix("@"), index + 2 < components.count {
                return components[index + 2]
            }
            return package
        }
        return (path as NSString).lastPathComponent
    }
}
