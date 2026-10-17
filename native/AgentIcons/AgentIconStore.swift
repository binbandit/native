import Foundation
import ImageIO
import Observation
import SwiftUI

/// Finds and remembers each agent's icon, trying its `AgentIconSource` in order: the plugin's own
/// image, the installed app's icon, then the ACP registry's. Until one turns up (or when none
/// does) the agent shows a monogram, so there's never an empty slot.
@Observable
final class AgentIconStore {
    static let shared = AgentIconStore()

    private var artworks: [AgentDefinition.ID: AgentIconArtwork] = [:]
    @ObservationIgnored private var lookups: [AgentDefinition.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var images: [ImageKey: Image] = [:]
    @ObservationIgnored private let registry: AgentIconRegistry
    @ObservationIgnored private let pluginsDirectory: URL

    /// App icons are rendered once, big enough for every place an agent icon appears.
    private static let pictureSize = 128

    private struct ImageKey: Hashable {
        let agent: AgentDefinition.ID
        let size: CGFloat
        let scale: CGFloat
    }

    init(registry: AgentIconRegistry = AgentIconRegistry(), pluginsDirectory: URL = PluginRegistry.directory) {
        self.registry = registry
        self.pluginsDirectory = pluginsDirectory
    }

    /// The agent's icon as far as it's known; a monogram until `resolve` finds better.
    func artwork(for agent: AgentDefinition) -> AgentIconArtwork {
        artworks[agent.id] ?? .monogram(for: agent.displayName)
    }

    /// Looks for the agent's icon, once per launch; later calls wait for the first.
    func resolve(_ agent: AgentDefinition) async {
        let lookup = lookups[agent.id] ?? Task { await load(agent) }
        lookups[agent.id] = lookup
        await lookup.value
    }

    func resolve(_ agents: [AgentDefinition]) async {
        for agent in agents {
            await resolve(agent)
        }
    }

    /// Forgets what was found, so the next `resolve` looks again: after the user installs or removes
    /// an app, or a plugin changes its icon.
    func reset() {
        lookups.values.forEach { $0.cancel() }
        lookups = [:]
        images = [:]
        artworks = [:]
    }

    /// The icon as an `Image`, for places that take nothing else, such as menu items. Glyphs and
    /// monograms come back as template images, so menus tint them like their text.
    func image(for agent: AgentDefinition, size: CGFloat, scale: CGFloat) -> Image {
        let key = ImageKey(agent: agent.id, size: size, scale: scale)
        if let image = images[key] { return image }
        let artwork = artwork(for: agent)
        let renderer = ImageRenderer(content: AgentIconArtworkView(artwork: artwork, size: size).foregroundStyle(.black))
        renderer.scale = scale
        guard let cgImage = renderer.cgImage else { return Image(systemName: agent.symbolName) }
        let image = Image(decorative: cgImage, scale: scale).renderingMode(artwork.isTemplate ? .template : .original)
        // Monograms are placeholders; only keep what `resolve` settled on.
        if artworks[agent.id] != nil { images[key] = image }
        return image
    }

    private func load(_ agent: AgentDefinition) async {
        guard let source = agent.manifest.icon, let artwork = await find(source, pluginID: agent.pluginID) else { return }
        guard !Task.isCancelled else { return }
        images = images.filter { $0.key.agent != agent.id }
        artworks[agent.id] = artwork
    }

    private func find(_ source: AgentIconSource, pluginID: String) async -> AgentIconArtwork? {
        if let path = source.path, let artwork = await file(path, pluginID: pluginID) {
            return artwork
        }
        if let image = AgentIconInstalledApps.icon(bundleIDs: source.apps, pixelSize: Self.pictureSize) {
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
        let url = expanded.hasPrefix("/")
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
