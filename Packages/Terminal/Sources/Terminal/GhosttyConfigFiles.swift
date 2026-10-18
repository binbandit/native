import Foundation

/// Where Ghostty keeps a user's configuration and themes on macOS. Native only ever reads these.
public struct GhosttyConfigLocations: Hashable, Sendable {
    /// `$XDG_CONFIG_HOME/ghostty`, or `~/.config/ghostty`.
    public let configDirectory: URL
    /// `~/Library/Application Support/com.mitchellh.ghostty`.
    public let appSupportDirectory: URL
    /// The themes Ghostty.app ships, when it's installed.
    public let bundledThemes: URL?

    public init(configDirectory: URL, appSupportDirectory: URL, bundledThemes: URL?) {
        self.configDirectory = configDirectory
        self.appSupportDirectory = appSupportDirectory
        self.bundledThemes = bundledThemes
    }

    /// The locations for this user, honoring `XDG_CONFIG_HOME` as Ghostty does.
    public init(environment: [String: String], home: URL, bundledThemes: URL?) {
        let xdg = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(filePath: $0) }
        self.init(
            configDirectory: (xdg ?? home.appending(path: ".config")).appending(path: "ghostty"),
            appSupportDirectory: home.appending(path: "Library/Application Support/com.mitchellh.ghostty"),
            bundledThemes: bundledThemes
        )
    }

    /// The files Ghostty loads at startup, in its order (later ones win): the XDG files, then
    /// Application Support's, each as `config` then `config.ghostty`.
    public var defaultFiles: [URL] {
        [configDirectory, appSupportDirectory].flatMap {
            [$0.appending(path: "config"), $0.appending(path: "config.ghostty")]
        }
    }

    /// The user's own themes, which Ghostty searches before its bundled ones.
    public var userThemes: URL {
        configDirectory.appending(path: "themes")
    }

    /// Where a theme named `name` would be: an absolute path, or the user's themes, then
    /// Ghostty.app's.
    public func themeFiles(named name: String) -> [URL] {
        if name.hasPrefix("/") {
            return [URL(filePath: name)]
        }
        return [userThemes, bundledThemes].compactMap { $0?.appending(path: name) }
    }
}

/// One line of a Ghostty config: `key = value`.
public struct GhosttyConfigEntry: Hashable, Sendable {
    public let key: String
    /// The value with one pair of surrounding quotes removed; empty resets a repeatable key.
    public let value: String
    public let line: Int
}

/// A Ghostty config file's text, read the way Ghostty reads it: one `key = value` per line,
/// whole-line `#` comments, and `config-file` includes (`?` marks one optional) relative to the
/// file that names them.
public struct GhosttyConfigFile: Hashable, Sendable {
    public let url: URL
    public let entries: [GhosttyConfigEntry]

    public init(url: URL, text: String) {
        self.url = url
        entries = text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap {
            index, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { return nil }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            return GhosttyConfigEntry(key: key, value: value, line: index + 1)
        }
    }

    /// The files this one includes, in order.
    public func includes(home: URL) -> [URL] {
        entries.filter { $0.key == "config-file" && !$0.value.isEmpty }.map { entry in
            var path = entry.value.hasPrefix("?") ? String(entry.value.dropFirst()) : entry.value
            if path.count >= 2, path.hasPrefix("\""), path.hasSuffix("\"") {
                path = String(path.dropFirst().dropLast())
            }
            if path.hasPrefix("~/") {
                return home.appending(path: String(path.dropFirst(2)))
            }
            if path.hasPrefix("/") {
                return URL(filePath: path)
            }
            return url.deletingLastPathComponent().appending(path: path)
        }
    }

    /// The user's config as Ghostty loads it: the default files that exist, then every
    /// `config-file` they name, then the ones those name, in order (so an include's values win
    /// over the file that includes it). A file named twice is read once.
    public static func load(_ locations: GhosttyConfigLocations, home: URL) -> [GhosttyConfigFile] {
        var loaded: [GhosttyConfigFile] = []
        var seen = Set<URL>()
        func read(_ url: URL) -> GhosttyConfigFile? {
            let url = url.standardizedFileURL
            guard !seen.contains(url), let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            seen.insert(url)
            let file = GhosttyConfigFile(url: url, text: text)
            loaded.append(file)
            return file
        }
        var pending = locations.defaultFiles.compactMap(read).flatMap { $0.includes(home: home) }
        // Ghostty stops following includes after a fixed number; so does Native.
        var remaining = 64
        while !pending.isEmpty, remaining > 0 {
            remaining -= 1
            if let file = read(pending.removeFirst()) {
                pending += file.includes(home: home)
            }
        }
        return loaded
    }
}

extension Array where Element == GhosttyConfigFile {
    /// Every entry for `key` across the files, in load order.
    public func entries(_ key: String) -> [GhosttyConfigEntry] {
        flatMap { $0.entries.filter { $0.key == key } }
    }

    /// The value Ghostty ends up with for a single-valued key: the last one set.
    public func lastValue(_ key: String) -> String? {
        entries(key).last.map(\.value)
    }
}

extension GhosttyConfigFile {
    /// A libghostty diagnostic with where it is. The C API gives `key: message` without a
    /// location, so this names the last line in the user's files that sets that key, as
    /// `path:line: key: message`. A theme that can't be found is reported against `theme`.
    public static func locate(_ diagnostic: String, in files: [GhosttyConfigFile]) -> String {
        let key: Substring
        if let colon = diagnostic.range(of: ": "),
            diagnostic[..<colon.lowerBound].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
        {
            key = diagnostic[..<colon.lowerBound]
        } else if diagnostic.hasPrefix("theme ") || diagnostic.hasPrefix("failed to load theme") {
            key = "theme"
        } else {
            return diagnostic
        }
        for file in files.reversed() {
            if let entry = file.entries.last(where: { $0.key == key }) {
                return "\(file.url.path(percentEncoded: false)):\(entry.line): \(diagnostic)"
            }
        }
        return diagnostic
    }
}
