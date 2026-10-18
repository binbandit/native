import CryptoKit
import Foundation

/// Native's celebration icons that aren't bundled: one pack per edition, published with each release
/// beside a signed index, downloaded when someone chooses the celebration, verified and cached. A
/// pack that can't be fetched or verified changes nothing: the base icon stays.
///
/// The index is signed with the update key, the same Ed25519 scheme Sparkle uses for releases
/// (`HostUpdater`'s `UpdateSigningKey`); each pack is pinned by the index's SHA-256 and size.
public enum CelebrationAssets {
    /// The index's file name in a release, beside `<index>.sig` (the base64 signature).
    public static let indexName = "celebration-assets.json"
    public static let schema = 1
    /// How many days before an enabled celebration's window its pack is fetched, when it isn't yet.
    public static let leadDays = 7

    public enum Failure: Error, Equatable, LocalizedError {
        case badKey
        case badSignature
        case unsupportedSchema(Int)
        case notInIndex(String)
        case checksumMismatch(String)
        case incomplete(String)

        public var errorDescription: String? {
            switch self {
            case .badKey: "The signing key isn't a valid Ed25519 public key."
            case .badSignature: "The icon index isn't signed by Native."
            case .unsupportedSchema(let schema): "The icon index uses format \(schema); update Native to read it."
            case .notInIndex(let edition): "This release has no icons for \(edition)."
            case .checksumMismatch(let edition): "The \(edition) icons didn't match what the release lists."
            case .incomplete(let edition): "The \(edition) icons are missing a channel or appearance."
            }
        }
    }

    /// The signed list of packs in a release.
    public struct Index: Codable, Hashable, Sendable {
        public struct Pack: Codable, Hashable, Sendable {
            /// The pack's file name in the same release.
            public let file: String
            public let sha256: String
            public let size: Int

            public init(file: String, sha256: String, size: Int) {
                self.file = file
                self.sha256 = sha256
                self.size = size
            }
        }

        public let schema: Int
        /// Dated, so a cache knows which release its pack came from.
        public let version: String
        public let packs: [String: Pack]

        public init(schema: Int = CelebrationAssets.schema, version: String, packs: [String: Pack]) {
            self.schema = schema
            self.version = version
            self.packs = packs
        }
    }

    /// One edition's icons: every channel in light and dark, as PNG data keyed "stable-light".
    public struct Pack: Codable, Hashable, Sendable {
        public let schema: Int
        public let edition: String
        public let images: [String: Data]

        public init(schema: Int = CelebrationAssets.schema, edition: String, images: [String: Data]) {
            self.schema = schema
            self.edition = edition
            self.images = images
        }

        public static func imageName(_ variant: AppIconVariant, isDark: Bool) -> String {
            "\(variant.rawValue)-\(isDark ? "dark" : "light")"
        }
    }

    /// Checks the index's signature with the update key (base64, as Sparkle prints it) and reads it.
    public static func verifiedIndex(_ data: Data, signature: String, publicKey: String) throws -> Index {
        guard let raw = Data(base64Encoded: publicKey.trimmingCharacters(in: .whitespacesAndNewlines)),
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
        else { throw Failure.badKey }
        guard let signature = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)),
            key.isValidSignature(signature, for: data)
        else { throw Failure.badSignature }
        let index = try JSONDecoder().decode(Index.self, from: data)
        guard index.schema <= schema else { throw Failure.unsupportedSchema(index.schema) }
        return index
    }

    /// Checks a downloaded pack against the signed index and that it has every image, as PNG.
    public static func verifiedPack(_ data: Data, edition: String, index: Index) throws -> Pack {
        guard let entry = index.packs[edition] else { throw Failure.notInIndex(edition) }
        guard data.count == entry.size, sha256(data) == entry.sha256.lowercased() else {
            throw Failure.checksumMismatch(edition)
        }
        let pack = try JSONDecoder().decode(Pack.self, from: data)
        let names = AppIconVariant.allCases.flatMap {
            [Pack.imageName($0, isDark: false), Pack.imageName($0, isDark: true)]
        }
        guard pack.edition == edition,
            names.allSatisfy({ pack.images[$0].map(isPNG) ?? false })
        else { throw Failure.incomplete(edition) }
        return pack
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func isPNG(_ data: Data) -> Bool {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    /// The packs to fetch now: enabled celebrations whose icons download, that aren't here or on the
    /// way, and whose window opens within `leadDays` (or is open). Choosing one fetches it at once
    /// regardless; this catches the rest, such as a failed try or a cleared cache.
    public static func packsDue(
        _ events: [CelebrationEvent], preferences: CelebrationPreferences, on day: CivilDate,
        leadDays: Int = leadDays
    ) -> [String] {
        events.map(preferences.styled).compactMap { event in
            let selection = preferences.selection(for: event.id)
            guard selection.isEnabled, selection.appIcon, let pack = event.iconPack,
                case .downloadable(let state) = event.appIcon, state != .downloading,
                let next = event.nextOccurrence(window: selection.window, from: day),
                next.display.first <= day.adding(days: leadDays)
            else { return nil }
            return pack
        }
    }
}

/// Verified packs on disk, one folder per edition (`<root>/<edition>/stable-light.png`), written whole
/// or not at all.
public struct CelebrationAssetCache: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The edition's icons, when every one is here.
    public func icons(for edition: String) -> [AppIconVariant: AppIconImagePair]? {
        let folder = root.appending(path: edition, directoryHint: .isDirectory)
        var icons: [AppIconVariant: AppIconImagePair] = [:]
        for variant in AppIconVariant.allCases {
            let light = folder.appending(path: CelebrationAssets.Pack.imageName(variant, isDark: false) + ".png")
            let dark = folder.appending(path: CelebrationAssets.Pack.imageName(variant, isDark: true) + ".png")
            guard FileManager.default.fileExists(atPath: light.path(percentEncoded: false)),
                FileManager.default.fileExists(atPath: dark.path(percentEncoded: false))
            else { return nil }
            icons[variant] = AppIconImagePair(light: .file(light), dark: .file(dark))
        }
        return icons
    }

    /// Writes a verified pack, replacing any older copy only once the new one is complete.
    public func store(_ pack: CelebrationAssets.Pack) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appending(path: ".\(pack.edition)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        for (name, data) in pack.images {
            try data.write(to: staging.appending(path: name + ".png"), options: .atomic)
        }
        let folder = root.appending(path: pack.edition, directoryHint: .isDirectory)
        if manager.fileExists(atPath: folder.path(percentEncoded: false)) {
            _ = try manager.replaceItemAt(folder, withItemAt: staging)
        } else {
            try manager.moveItem(at: staging, to: folder)
        }
    }
}
