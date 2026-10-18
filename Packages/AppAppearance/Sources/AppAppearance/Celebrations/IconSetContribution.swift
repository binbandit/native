import Foundation

public typealias IconSetID = ContributionID<IconSetContribution>

/// A family of app icons a plugin offers: an entry in `plugin.json`'s `iconSets`. One icon per build
/// channel, each in light and dark, plus how Home dresses up with it. A celebration refers to one;
/// a set no celebration uses is offered as a plain app icon theme.
public struct IconSetContribution: AppearanceContribution {
    public static let kind = ContributionKind.iconSet
    public var rawID: String { id.rawValue }

    public var id: IconSetID
    public var name: LocalizedText
    /// Nil offers no app icon (a Home-only set).
    public var icons: IconSetIcons?
    /// A design-system mark Home draws instead of the plain emblem.
    public var homeMark: String?
    /// Colors for previews, and for Home's two-tone emblem when there's no mark (or this build can't
    /// draw it).
    public var palette: IconSetPalette?
    /// Small Regular icons for the catalogue, shipped with the app so previews work before (or
    /// without) downloading the full set. Plugin sets preview their own icons instead.
    public var thumbnail: IconSetImagePair?

    public init(
        id: IconSetID, name: LocalizedText, icons: IconSetIcons? = nil, homeMark: String? = nil,
        palette: IconSetPalette? = nil, thumbnail: IconSetImagePair? = nil
    ) {
        self.id = id
        self.name = name
        self.icons = icons
        self.homeMark = homeMark
        self.palette = palette
        self.thumbnail = thumbnail
    }
}

extension IconSetContribution: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, icons, home, palette, thumbnail
    }

    private enum HomeKeys: String, CodingKey {
        case mark
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(IconSetID.self, forKey: .id)
        name = try container.decode(LocalizedText.self, forKey: .name)
        icons = try container.decodeIfPresent(IconSetIcons.self, forKey: .icons)
        homeMark =
            try container.contains(.home)
            ? container.nestedContainer(keyedBy: HomeKeys.self, forKey: .home).decodeIfPresent(String.self, forKey: .mark)
            : nil
        palette = try container.decodeIfPresent(IconSetPalette.self, forKey: .palette)
        thumbnail = try container.decodeIfPresent(IconSetImagePair.self, forKey: .thumbnail)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(icons, forKey: .icons)
        if let homeMark {
            var home = container.nestedContainer(keyedBy: HomeKeys.self, forKey: .home)
            try home.encode(homeMark, forKey: .mark)
        }
        try container.encodeIfPresent(palette, forKey: .palette)
        try container.encodeIfPresent(thumbnail, forKey: .thumbnail)
    }
}

/// App icons for every build channel, or a promise of them. A set applies only once all four
/// channels are complete in both appearances, so no build is left on a mismatched icon.
public enum IconSetIcons: Hashable, Sendable {
    case forthcoming
    case channels([AppIconVariant: IconSetImagePair])
    /// Native's own sets that aren't bundled: a signed pack, by edition, downloaded from the release
    /// when someone chooses the celebration (`CelebrationAssets`). Built-in plugins only.
    case pack(String)
}

extension IconSetIcons: Codable {
    private static let packPrefix = "pack:"

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let status = try? container.decode(String.self) {
            if status == "forthcoming" {
                self = .forthcoming
            } else if status.hasPrefix(Self.packPrefix) {
                self = .pack(String(status.dropFirst(Self.packPrefix.count)))
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "\"icons\" is \"forthcoming\" or icons by channel.")
            }
            return
        }
        var channels: [AppIconVariant: IconSetImagePair] = [:]
        for (key, pair) in try container.decode([String: IconSetImagePair].self) {
            guard let variant = AppIconVariant(rawValue: key) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unknown channel \"\(key)\": use stable, beta, nightly or dev.")
            }
            channels[variant] = pair
        }
        self = .channels(channels)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .forthcoming:
            try container.encode("forthcoming")
        case .pack(let edition):
            try container.encode(Self.packPrefix + edition)
        case .channels(let channels):
            try container.encode(Dictionary(uniqueKeysWithValues: channels.map { ($0.key.rawValue, $0.value) }))
        }
    }
}

public struct IconSetImagePair: Codable, Hashable, Sendable {
    public var light: IconSetImageReference
    public var dark: IconSetImageReference

    public init(light: IconSetImageReference, dark: IconSetImageReference) {
        self.light = light
        self.dark = dark
    }
}

/// An image a contribution names. Manifests give paths inside the plugin's folder; Native's own
/// plugins name images compiled into the app.
public enum IconSetImageReference: Hashable, Sendable {
    case path(String)
    case asset(String)
}

extension IconSetImageReference: Codable {
    private enum CodingKeys: String, CodingKey {
        case asset
    }

    public init(from decoder: any Decoder) throws {
        if let path = try? decoder.singleValueContainer().decode(String.self) {
            self = .path(path)
            return
        }
        self = .asset(try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .asset))
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .path(let path):
            var container = encoder.singleValueContainer()
            try container.encode(path)
        case .asset(let name):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .asset)
        }
    }
}

/// An icon set's colors, most prominent first, for each appearance.
public struct IconSetPalette: Codable, Hashable, Sendable {
    public var light: [HexColor]
    public var dark: [HexColor]

    public init(light: [HexColor], dark: [HexColor]) {
        self.light = light
        self.dark = dark
    }

    /// Two colors in each appearance: enough for Home's two links.
    public var isTwoTone: Bool { light.count >= 2 && dark.count >= 2 }
}

/// An sRGB color written "#RRGGBB".
public struct HexColor: Hashable, Sendable, CustomStringConvertible {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init?(_ text: String) {
        guard text.count == 7, text.first == "#", let value = UInt32(text.dropFirst(), radix: 16) else { return nil }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    public var description: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}

extension HexColor: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let color = HexColor(text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "\"\(text)\" isn't a color like \"#F28C1B\".")
        }
        self = color
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
