import Foundation
import ImageIO
import Observation
import SwiftUI

/// Finds and remembers each agent's icon in each `AgentIcon.Style`, trying its `AgentIconSource` in
/// order: the plugin's own image, the installed app's icon (tiles only), then the ACP registry's.
/// Until one turns up (or when none does) the agent shows a monogram, so there's never an empty
/// slot.
@Observable
final class AgentIconStore {
    static let shared = AgentIconStore()

    private var artworks: [Lookup: AgentIconArtwork] = [:]
    /// Bumped by `reset`, so views showing an icon look it up again.
    private(set) var generation = 0
    @ObservationIgnored private var lookups: [Lookup: Task<Void, Never>] = [:]
    @ObservationIgnored private var images: [ImageKey: Image] = [:]
    @ObservationIgnored private let registry: AgentIconRegistry
    @ObservationIgnored private let pluginsDirectory: URL

    /// App icons are rendered once, big enough for every place an agent icon appears.
    private static let pictureSize = 128

    private struct Lookup: Hashable {
        let agent: AgentDefinition.ID
        let style: AgentIcon.Style
    }

    private struct ImageKey: Hashable {
        let lookup: Lookup
        let size: CGFloat
        let scale: CGFloat
        let colorScheme: ColorScheme
    }

    init(registry: AgentIconRegistry = AgentIconRegistry(), pluginsDirectory: URL = PluginRegistry.directory) {
        self.registry = registry
        self.pluginsDirectory = pluginsDirectory
    }

    /// The agent's icon as far as it's known; a monogram until `resolve` finds better.
    func artwork(for agent: AgentDefinition, style: AgentIcon.Style = .glyph) -> AgentIconArtwork {
        artworks[Lookup(agent: agent.id, style: style)] ?? .monogram(for: agent.displayName)
    }

    /// Looks for the agent's icon, once per launch and style; later calls wait for the first.
    func resolve(_ agent: AgentDefinition, style: AgentIcon.Style = .glyph) async {
        let key = Lookup(agent: agent.id, style: style)
        let lookup = lookups[key] ?? Task { await load(agent, style: style) }
        lookups[key] = lookup
        await lookup.value
    }

    func resolve(_ agents: [AgentDefinition], style: AgentIcon.Style = .glyph) async {
        for agent in agents {
            await resolve(agent, style: style)
        }
    }

    /// Forgets what was found, so the next `resolve` looks again: after the user installs or removes
    /// an app, or a plugin changes its icon.
    func reset() {
        lookups.values.forEach { $0.cancel() }
        lookups = [:]
        images = [:]
        artworks = [:]
        generation += 1
    }

    /// The icon as an `Image` in the glyph style, for places that take nothing else, such as menu
    /// items. Menus draw it as is (they ignore SwiftUI's template rendering), so it's drawn in the
    /// label color of `colorScheme`, the menu's appearance.
    func image(for agent: AgentDefinition, size: CGFloat, scale: CGFloat, colorScheme: ColorScheme) -> Image {
        let lookup = Lookup(agent: agent.id, style: .glyph)
        let key = ImageKey(lookup: lookup, size: size, scale: scale, colorScheme: colorScheme)
        if let image = images[key] { return image }
        let renderer = ImageRenderer(
            content: AgentIconArtworkView(artwork: artwork(for: agent), size: size)
                .foregroundStyle(.primary)
                .environment(\.colorScheme, colorScheme)
        )
        renderer.scale = scale
        guard let cgImage = renderer.cgImage else { return Image(systemName: agent.symbolName) }
        let image = Image(decorative: cgImage, scale: scale)
        // Monograms are placeholders; only keep what `resolve` settled on.
        if artworks[lookup] != nil { images[key] = image }
        return image
    }

    private func load(_ agent: AgentDefinition, style: AgentIcon.Style) async {
        guard let source = agent.manifest.icon,
            let artwork = await find(source, style: style, pluginID: agent.pluginID)
        else { return }
        guard !Task.isCancelled else { return }
        let lookup = Lookup(agent: agent.id, style: style)
        images = images.filter { $0.key.lookup != lookup }
        artworks[lookup] = artwork
    }

    private func find(_ source: AgentIconSource, style: AgentIcon.Style, pluginID: String) async -> AgentIconArtwork? {
        // Glyphs stay monochrome, so a plugin's bitmap and app icons are for tiles only.
        if let path = source.path, let artwork = await file(path, pluginID: pluginID),
            style == .tile || !artwork.isPicture
        {
            return artwork
        }
        if style == .tile, let image = AgentIconInstalledApps.icon(bundleIDs: source.apps, pixelSize: Self.pictureSize) {
            return .picture(image)
        }
        if let id = source.registry, let data = await registry.icon(for: id), let glyph = AgentIconGlyph(svg: data) {
            return .glyph(glyph)
        }
        return nil
    }

    /// A plugin's image file: an SVG becomes a glyph, anything else a picture.
    private func file(_ path: String, pluginID: String) async -> AgentIconArtwork? {
        let expanded = NSString(string: path).expandingTildeInPath
        let url =
            expanded.hasPrefix("/")
            ? URL(filePath: expanded)
            : pluginsDirectory.appending(path: pluginID, directoryHint: .isDirectory).appending(path: expanded)
        guard let data = await Self.contents(of: url) else { return nil }
        if url.pathExtension.lowercased() == "svg" {
            return AgentIconGlyph(svg: data).map(AgentIconArtwork.glyph)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return .picture(image)
    }

    @concurrent
    private nonisolated static func contents(of url: URL) async -> Data? {
        try? Data(contentsOf: url)
    }
}

extension EnvironmentValues {
    /// Where `AgentIcon` gets icons from; nil means the shared store. Previews can supply their own.
    @Entry var agentIconStore: AgentIconStore?
}
