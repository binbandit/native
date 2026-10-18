import Foundation

/// What a celebration changes: the app icon, the Home page, or both. A surface that's left out isn't
/// offered; `forthcoming` lists it in the catalogue without applying it, until its artwork is done.
public struct CelebrationArtwork: Codable, Hashable, Sendable {
    public var appIcon: CelebrationIconArtwork?
    public var home: CelebrationHomeArtwork?
    /// The edition's colors, for previews and for catalogue entries whose artwork isn't done.
    public var palette: CelebrationPalette?

    public init(
        appIcon: CelebrationIconArtwork? = nil, home: CelebrationHomeArtwork? = nil, palette: CelebrationPalette? = nil
    ) {
        self.appIcon = appIcon
        self.home = home
        self.palette = palette
    }
}

/// App icons for every build channel, each in light and dark. An edition applies only once all four
/// channels are complete, so no build is left on a mismatched icon.
public enum CelebrationIconArtwork: Hashable, Sendable {
    case forthcoming
    case channels([AppIconVariant: CelebrationImagePair])
}

extension CelebrationIconArtwork: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let status = try? container.decode(String.self) {
            guard status == "forthcoming" else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "\"appIcon\" is \"forthcoming\" or icons by channel.")
            }
            self = .forthcoming
            return
        }
        var channels: [AppIconVariant: CelebrationImagePair] = [:]
        for (key, pair) in try container.decode([String: CelebrationImagePair].self) {
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
        case .channels(let channels):
            try container.encode(Dictionary(uniqueKeysWithValues: channels.map { ($0.key.rawValue, $0.value) }))
        }
    }
}

public struct CelebrationImagePair: Codable, Hashable, Sendable {
    public var light: CelebrationImageReference
    public var dark: CelebrationImageReference

    public init(light: CelebrationImageReference, dark: CelebrationImageReference) {
        self.light = light
        self.dark = dark
    }
}

/// An image a contribution names. Manifests give paths inside the plugin's folder; Native's own
/// plugins name images compiled into the app.
public enum CelebrationImageReference: Hashable, Sendable {
    case path(String)
    case asset(String)
}

extension CelebrationImageReference: Codable {
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

/// How the Home page dresses up: one of the design system's celebration marks, by id.
public enum CelebrationHomeArtwork: Hashable, Sendable {
    case forthcoming
    case mark(String)
}

extension CelebrationHomeArtwork: Codable {
    private enum CodingKeys: String, CodingKey {
        case mark
    }

    public init(from decoder: any Decoder) throws {
        if let status = try? decoder.singleValueContainer().decode(String.self), status == "forthcoming" {
            self = .forthcoming
            return
        }
        self = .mark(try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .mark))
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .forthcoming:
            var container = encoder.singleValueContainer()
            try container.encode("forthcoming")
        case .mark(let mark):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(mark, forKey: .mark)
        }
    }
}

public struct CelebrationPalette: Codable, Hashable, Sendable {
    public var light: [HexColor]
    public var dark: [HexColor]

    public init(light: [HexColor], dark: [HexColor]) {
        self.light = light
        self.dark = dark
    }
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
        String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

extension HexColor: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let color = HexColor(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "\"\(text)\" isn't a color like \"#F28C1B\".")
        }
        self = color
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
