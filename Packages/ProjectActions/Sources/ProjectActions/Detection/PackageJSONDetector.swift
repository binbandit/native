import Foundation

/// package.json: Install, plus every script, run with the package manager the project uses.
enum PackageJSONDetector {
    static func detect(_ folder: ProjectFolder) -> [ProjectSuggestion] {
        guard folder.has("package.json"), let data = folder.data("package.json"),
            let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return [] }
        let manager = PackageManager.used(by: folder, declared: manifest.packageManager)
        let install = ProjectSuggestion(
            name: "Install", command: "\(manager.rawValue) install", role: .install, source: .packageJSON)
        let scripts = manifest.scripts
            .filter { !isPlaceholder($0.value) && !lifecycleScripts.contains($0.key) }
            .map { name, body in
                ProjectSuggestion.named(
                    name, command: manager.command(running: name), source: .packageJSON, detail: body)
            }
            // JSON objects have no order once decoded; the ranking sorts by role, so names break ties.
            .sorted { $0.name < $1.name }
        return [install] + scripts
    }

    /// npm's own hooks around install and publish, which aren't things to run by hand.
    private static let lifecycleScripts: Set = [
        "preinstall", "install", "postinstall", "prepare", "prepublish", "prepublishOnly", "prepack", "postpack",
    ]

    /// `npm init`'s stand-in test script, which only fails.
    private static func isPlaceholder(_ script: String) -> Bool {
        script.contains("Error: no test specified")
    }

    private struct Manifest: Decodable {
        var scripts: [String: String] = [:]
        var packageManager: String?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            scripts = (try? container.decodeIfPresent([String: String].self, forKey: .scripts)) ?? [:]
            packageManager = try? container.decodeIfPresent(String.self, forKey: .packageManager)
        }

        private enum CodingKeys: String, CodingKey {
            case scripts, packageManager
        }
    }
}

/// The JavaScript package managers, and how each runs a script.
enum PackageManager: String, CaseIterable {
    case npm, pnpm, yarn, bun

    /// The `packageManager` field ("pnpm@9.1.0") wins, then the lockfile, then npm.
    static func used(by folder: ProjectFolder, declared: String?) -> Self {
        if let declared, let name = declared.split(separator: "@").first, let manager = Self(rawValue: String(name)) {
            return manager
        }
        if folder.has("bun.lock") || folder.has("bun.lockb") { return .bun }
        if folder.has("pnpm-lock.yaml") { return .pnpm }
        if folder.has("yarn.lock") { return .yarn }
        return .npm
    }

    /// `npm test`, `pnpm run dev`, `bun run test` (plain `bun test` is Bun's own test runner, not
    /// the script).
    func command(running script: String) -> String {
        switch (self, script) {
        case (.npm, "test"), (.npm, "start"), (.pnpm, "test"), (.yarn, "test"): "\(rawValue) \(script)"
        default: "\(rawValue) run \(Self.quoted(script))"
        }
    }

    /// Script names can hold characters a shell treats specially (`test:unit` is fine, `a b` isn't).
    private static func quoted(_ name: String) -> String {
        let plain = name.allSatisfy { $0.isLetter || $0.isNumber || "-_:./@+=".contains($0) }
        return plain ? name : "'\(name.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
