#if canImport(GhosttyKit)
import AppKit
import GhosttyKit
import OSLog
import Terminal

/// Builds libghostty configs: from Native's settings, or from the user's own Ghostty config with
/// Native's few overrides on top. libghostty reads config only from files, so Native's parts go
/// through private temporary ones.
enum GhosttyConfigBuilder {
    /// A finalized config the caller frees with `ghostty_config_free`, and where it came from.
    struct Built {
        let config: ghostty_config_t
        let status: TerminalConfigStatus
    }

    /// The config for `style`: the user's Ghostty config when `ghostty` is given and it loads
    /// cleanly, otherwise Native's settings (with the reason in the status).
    static func build(_ style: TerminalStyle, ghostty: GhosttyConfigLocations?) -> Built? {
        guard let ghostty else {
            return native(style).map { Built(config: $0, status: .native) }
        }
        let files = ghostty.defaultFiles.filter {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        }
        guard !files.isEmpty else {
            return native(style).map { Built(config: $0, status: .ghosttyNotFound(searched: ghostty.defaultFiles)) }
        }
        let loaded = GhosttyConfigFile.load(ghostty, home: .homeDirectory).map(\.url)
        let (config, diagnostics) = user(files)
        guard let config, diagnostics.isEmpty else {
            if let config { ghostty_config_free(config) }
            return native(style).map {
                Built(config: $0, status: .ghosttyInvalid(files: loaded, diagnostics: diagnostics))
            }
        }
        return Built(config: config, status: .ghostty(files: loaded))
    }

    /// Native's settings alone.
    private static func native(_ style: TerminalStyle) -> ghostty_config_t? {
        let configuration = GhosttyConfiguration(
            settings: style.settings,
            colors: style.colors,
            defaultFont: defaultFont,
            padding: .init(horizontal: Int(DS.Space.lg), vertical: Int(DS.Space.md))
        )
        return withTemporaryFiles([configuration.text]) { paths in
            guard let config = ghostty_config_new() else { return nil }
            load(paths[0], into: config)
            ghostty_config_finalize(config)
            for message in diagnostics(of: config) {
                GhosttyRuntime.logger.warning("Terminal config: \(message, privacy: .public)")
            }
            return config
        }
    }

    /// The user's config files with Native's defaults under them and its overrides over them, the
    /// way Ghostty loads them (`config-file` includes, then themes when finalizing). Ghostty's own
    /// `loadDefaultFiles` isn't used: it writes a template config when none exists, and Native
    /// never writes to the user's Ghostty files.
    private static func user(_ files: [URL]) -> (ghostty_config_t?, [String]) {
        let parts = [GhosttyConfiguration.userConfigDefaults, GhosttyConfiguration.embeddingOverrides]
        let built: (ghostty_config_t?, [String])? = withTemporaryFiles(parts) { paths in
            guard let config = ghostty_config_new() else { return (nil, []) }
            load(paths[0], into: config)
            for file in files {
                load(file.path(percentEncoded: false), into: config)
            }
            ghostty_config_load_recursive_files(config)
            load(paths[1], into: config)
            ghostty_config_finalize(config)
            // Native's own lines never count against the user's config.
            let directory = URL(filePath: paths[0]).deletingLastPathComponent().path(percentEncoded: false)
            var userDiagnostics: [String] = []
            for message in diagnostics(of: config) {
                if message.contains(directory) {
                    GhosttyRuntime.logger.error("Native's terminal overrides: \(message, privacy: .public)")
                } else {
                    userDiagnostics.append(message)
                }
            }
            return (config, userDiagnostics)
        }
        return built ?? (nil, [])
    }

    private static func load(_ path: String, into config: ghostty_config_t) {
        path.withCString { ghostty_config_load_file(config, $0) }
    }

    /// libghostty's problems with a config, each `path:line: message`.
    private static func diagnostics(of config: ghostty_config_t) -> [String] {
        (0..<ghostty_config_diagnostics_count(config)).compactMap { index in
            ghostty_config_get_diagnostic(config, index).message.map { String(cString: $0) }
        }
    }

    /// Writes `contents` to private temporary files for the duration of `body`.
    private static func withTemporaryFiles<Result>(_ contents: [String], _ body: ([String]) -> Result?) -> Result? {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "native-terminal-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let paths = try contents.enumerated().map { index, text in
                let file = directory.appending(path: "native-\(index).conf")
                try text.write(to: file, atomically: true, encoding: .utf8)
                return file.path(percentEncoded: false)
            }
            return body(paths)
        } catch {
            GhosttyRuntime.logger.error(
                "Couldn't write the terminal config: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The design system's code font, Geist Mono, which `DSTypography` registers for the process.
    private static var defaultFont: GhosttyConfiguration.DefaultFont {
        let family = DSTypography.nsFont(size: 12, design: .mono).familyName ?? ""
        // Without Geist the token falls back to the system's private monospaced face, which
        // libghostty can't look up by name.
        guard !family.isEmpty, !family.hasPrefix(".") else {
            return .init(family: "Menlo", isVariable: false)
        }
        return .init(family: family, isVariable: family == "Geist Mono")
    }

    // MARK: Resources

    /// Points libghostty at its resources before it starts: Native's bundled terminfo and shell
    /// integration, and Ghostty.app's themes when it's installed, so `theme = Name` works in the
    /// user's config without Native shipping themes. They're joined with links in Native's caches
    /// folder, because libghostty takes one resources folder and finds terminfo next to it.
    static func prepareResources() {
        guard let bundled = Bundle.main.resourceURL,
            FileManager.default.fileExists(atPath: bundled.appending(path: "terminfo/78/xterm-ghostty").path)
        else {
            GhosttyRuntime.logger.warning("Ghostty's terminfo isn't in the app bundle; terminals use xterm-256color.")
            return
        }
        let fileManager = FileManager.default
        let root = URL.cachesDirectory.appending(path: Bundle.main.bundleIdentifier ?? "Native")
            .appending(path: "ghostty-resources")
        let ghostty = root.appending(path: "ghostty")
        do {
            try? fileManager.removeItem(at: root)
            try fileManager.createDirectory(at: ghostty, withIntermediateDirectories: true)
            try fileManager.createSymbolicLink(
                at: root.appending(path: "terminfo"), withDestinationURL: bundled.appending(path: "terminfo"))
            try fileManager.createSymbolicLink(
                at: ghostty.appending(path: "shell-integration"),
                withDestinationURL: bundled.appending(path: "ghostty/shell-integration"))
            if let themes = GhosttyConfigLocations.ghosttyThemes, fileManager.fileExists(atPath: themes.path) {
                try fileManager.createSymbolicLink(at: ghostty.appending(path: "themes"), withDestinationURL: themes)
            }
            setenv("GHOSTTY_RESOURCES_DIR", ghostty.path(percentEncoded: false), 1)
        } catch {
            GhosttyRuntime.logger.error(
                "Couldn't prepare Ghostty's resources: \(error.localizedDescription, privacy: .public)")
            setenv("GHOSTTY_RESOURCES_DIR", bundled.appending(path: "ghostty").path(percentEncoded: false), 1)
        }
    }
}
#endif
