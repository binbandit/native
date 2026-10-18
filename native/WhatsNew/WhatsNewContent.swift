import Foundation

/// One release's highlights in the What's New sheet. Foundation-only values, so the companion can
/// show the same content. Curated by hand in `WhatsNewCatalog`; the full changelog stays the
/// release notes drafted from conventional commits (docs/releasing.md).
struct WhatsNewRelease: Hashable, Sendable {
    let version: WhatsNewVersion
    let highlights: [WhatsNewHighlight]
}

struct WhatsNewHighlight: Hashable, Sendable, Identifiable {
    /// Stable across releases, e.g. "updates.toolbar-button".
    let id: String
    let title: String
    /// One or two sentences: what it is and why it matters.
    let summary: String
    var preview: WhatsNewPreview?
    var destination: WhatsNewDestination?
}

/// Art for a highlight, all original: an image from the asset catalog, or an SF Symbol that
/// animates once when it appears (still under Reduce Motion).
enum WhatsNewPreview: Hashable, Sendable {
    case image(assetName: String)
    case symbol(String)
}

/// Where "Try It" goes. Ids rather than app types, so the content works on every client.
enum WhatsNewDestination: Hashable, Sendable {
    /// A Settings page, by `SettingsPane.ID` raw value.
    case settings(String)
    case url(URL)
}

/// A marketing version like "1.4.0" or "1.5.0-beta.1", ordered numerically; a prerelease sorts
/// before its release.
struct WhatsNewVersion: Hashable, Sendable, Comparable, CustomStringConvertible {
    let numbers: [Int]
    let prerelease: String?
    let description: String

    init(_ string: String) {
        description = string
        let parts = string.split(separator: "-", maxSplits: 1)
        numbers = (parts.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
        prerelease = parts.count > 1 ? String(parts[1]) : nil
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.numbers.count, rhs.numbers.count)
        for index in 0..<count {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left < right }
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil), (nil, _?): return false
        case (_?, nil): return true
        case (let left?, let right?): return left < right
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(numbers.reversed().drop { $0 == 0 }.reversed() as [Int])
        hasher.combine(prerelease)
    }
}

/// When the sheet appears, as a pure function of what was last seen, so it's easy to reason about.
enum WhatsNewSchedule {
    /// The releases to show after updating from `lastSeen` to `current`, newest first. Nil
    /// `lastSeen` is a brand-new install, which gets the welcome instead.
    static func pending(
        in catalog: [WhatsNewRelease], lastSeen: WhatsNewVersion?, current: WhatsNewVersion
    )
        -> [WhatsNewRelease]
    {
        guard let lastSeen, lastSeen < current else { return [] }
        return catalog.filter { lastSeen < $0.version && $0.version <= current && !$0.highlights.isEmpty }
            .sorted { $0.version > $1.version }
    }

    /// What Help ▸ What's New shows: the newest release with highlights up to this version.
    static func latest(in catalog: [WhatsNewRelease], current: WhatsNewVersion) -> WhatsNewRelease? {
        catalog.filter { $0.version <= current && !$0.highlights.isEmpty }.max { $0.version < $1.version }
    }
}
