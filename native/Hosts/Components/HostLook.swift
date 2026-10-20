import NativeHostProtocol
import SwiftUI

/// How a device looks wherever it shows (Settings ▸ Hosts, the device picker, a session's badge): a
/// symbol and a color the user picks, so two Mac minis tell apart at a glance.
nonisolated struct HostLook: Codable, Hashable, Sendable {
    var symbol: HostSymbol
    var tint: HostTint

    /// This Mac in graphite: color is for the machines the user added.
    static func thisMac(machineName: String) -> HostLook {
        HostLook(symbol: HostSymbol.guess(fromMachineName: machineName) ?? .laptop, tint: .graphite)
    }

    /// A paired host's look until the user picks one: a symbol from its name, and a color picked by
    /// its id, so it keeps the same color whatever else is added or removed.
    static func suggested(machineName: String, id: UUID) -> HostLook {
        let colors = HostTint.allCases.filter { $0 != .graphite }
        return HostLook(
            symbol: HostSymbol.guess(fromMachineName: machineName) ?? .server,
            tint: colors[Int(id.uuid.0) % colors.count])
    }

    /// The look `device` has until the user picks one; `name` is what the device is called.
    @MainActor static func fallback(for device: SessionDevice, named name: String) -> HostLook {
        switch device {
        case .thisMac: .thisMac(machineName: PlatformDevice.name)
        case .remote(let id): .suggested(machineName: name, id: id.rawValue)
        }
    }
}

/// The machines a host can be drawn as.
nonisolated enum HostSymbol: String, Codable, CaseIterable, Identifiable, Sendable {
    case mini
    case studio
    case laptop
    case desktop
    case tower
    case server
    case pc
    case cloud

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .mini: "macmini"
        case .studio: "macstudio"
        case .laptop: "laptopcomputer"
        case .desktop: "desktopcomputer"
        case .tower: "macpro.gen3"
        case .server: "server.rack"
        case .pc: "pc"
        case .cloud: "cloud"
        }
    }

    var title: String {
        switch self {
        case .mini: "Mac mini"
        case .studio: "Mac Studio"
        case .laptop: "Laptop"
        case .desktop: "Desktop"
        case .tower: "Mac Pro"
        case .server: "Server"
        case .pc: "PC"
        case .cloud: "Cloud"
        }
    }

    /// A symbol for a machine called `name` ("Brayden's Mac mini" draws as a Mac mini), or nil when
    /// the name doesn't say.
    static func guess(fromMachineName name: String) -> HostSymbol? {
        let name = name.lowercased()
        let hints: [(String, HostSymbol)] = [
            ("mini", .mini), ("studio", .studio), ("macbook", .laptop), ("laptop", .laptop), ("imac", .desktop),
            ("mac pro", .tower), ("server", .server), ("linux", .server), ("ubuntu", .server),
        ]
        return hints.first { name.contains($0.0) }?.1
    }
}

/// A host's color: one of the palettes Native's app icons come in, each contrast-checked in light
/// and dark, so a host glyph reads on every surface.
nonisolated enum HostTint: String, Codable, CaseIterable, Identifiable, Sendable {
    case graphite
    case cobalt
    case fern
    case ember
    case prism
    case glass
    case dusk

    var id: Self { self }

    var title: String {
        switch self {
        case .graphite: "Graphite"
        case .cobalt: "Cobalt"
        case .fern: "Fern"
        case .ember: "Ember"
        case .prism: "Prism"
        case .glass: "Glass"
        case .dusk: "Dusk"
        }
    }

    /// The icon theme palette the color comes from. Arcade is left out: its hue flips between light
    /// and dark, so a host would change color with the appearance.
    var palette: DSAccentPalette {
        switch self {
        case .graphite: .original
        case .cobalt: .cobalt
        case .fern: .fern
        case .ember: .ember
        case .prism: .prism
        case .glass: .glass
        case .dusk: .nightly
        }
    }
}
