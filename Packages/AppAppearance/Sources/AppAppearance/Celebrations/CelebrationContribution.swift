import Foundation

/// A celebration's stable, namespaced id, such as `native.halloween`. User preferences are keyed by
/// it, so it never changes once shipped; a regional variant gets an id of its own.
public typealias CelebrationID = ContributionID<CelebrationContribution>

/// A contribution's stable, namespaced id: `<namespace>.<name>`, lowercase. Typed by what it names,
/// so a celebration id can't be passed where an icon set's is expected.
public struct ContributionID<Kind>: RawRepresentable, Hashable, Comparable, Sendable, Codable, CodingKeyRepresentable,
    CustomStringConvertible
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One celebration a plugin offers: an entry in `plugin.json`'s `celebrations`. It's data only;
/// what the user chose lives in `CelebrationPreferences`, never in the manifest.
public struct CelebrationContribution: AppearanceContribution {
    public static let kind = ContributionKind.celebration
    public var rawID: String { id.rawValue }

    // Identity
    public var id: CelebrationID
    public var title: LocalizedText
    /// Other names search should find it by: local names, spellings, the eve.
    public var aliases: [String]
    public var summary: LocalizedText?
    /// Discovery groups such as "cultural", "religious" or "community". They help browsing and never
    /// turn anything on.
    public var tags: [String]

    public var provenance: CelebrationProvenance
    public var calendar: CelebrationCalendar
    public var display: CelebrationDisplay
    /// The icon set it dresses Native in, from any enabled plugin. Nil lists it with its artwork
    /// forthcoming, so it can be browsed but changes nothing.
    public var iconSet: IconSetID?
    public var compatibility: CelebrationCompatibility

    public init(
        id: CelebrationID, title: LocalizedText, aliases: [String] = [], summary: LocalizedText? = nil,
        tags: [String] = [], provenance: CelebrationProvenance = CelebrationProvenance(),
        calendar: CelebrationCalendar, display: CelebrationDisplay = CelebrationDisplay(), iconSet: IconSetID? = nil,
        compatibility: CelebrationCompatibility = CelebrationCompatibility()
    ) {
        self.id = id
        self.title = title
        self.aliases = aliases
        self.summary = summary
        self.tags = tags
        self.provenance = provenance
        self.calendar = calendar
        self.display = display
        self.iconSet = iconSet
        self.compatibility = compatibility
    }

    /// Whether search text finds this celebration: any word of its title, aliases or tags, ignoring
    /// case and accents, so "dia de muertos" finds Día de Muertos.
    public func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let haystack = ([title.fallback] + title.translations.values + aliases + tags)
        return haystack.contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

extension CelebrationContribution: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, aliases, summary = "description", tags, provenance, calendar, display, iconSet, compatibility
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CelebrationID.self, forKey: .id)
        title = try container.decode(LocalizedText.self, forKey: .title)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        summary = try container.decodeIfPresent(LocalizedText.self, forKey: .summary)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        provenance = try container.decodeIfPresent(CelebrationProvenance.self, forKey: .provenance) ?? .init()
        calendar = try container.decode(CelebrationCalendar.self, forKey: .calendar)
        display = try container.decodeIfPresent(CelebrationDisplay.self, forKey: .display) ?? .init()
        iconSet = try container.decodeIfPresent(IconSetID.self, forKey: .iconSet)
        compatibility = try container.decodeIfPresent(CelebrationCompatibility.self, forKey: .compatibility) ?? .init()
    }
}

/// Text with optional translations: `"Halloween"`, or `{"en": "Day of the Dead", "es": "Día de Muertos"}`.
public struct LocalizedText: Hashable, Sendable, ExpressibleByStringLiteral {
    /// Shown when no translation matches the user's languages.
    public let fallback: String
    /// By language code ("es", "pt-BR").
    public let translations: [String: String]

    public init(_ fallback: String, translations: [String: String] = [:]) {
        self.fallback = fallback
        self.translations = translations
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    /// The best text for `languages`, most preferred first ("es-MX" falls back to "es").
    public func resolved(for languages: [String] = Locale.preferredLanguages) -> String {
        for language in languages {
            if let exact = translations[language] { return exact }
            let base = String(language.prefix { $0 != "-" && $0 != "_" })
            if let text = translations[base] { return text }
        }
        return fallback
    }
}

extension LocalizedText: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self.init(text)
            return
        }
        let translations = try container.decode([String: String].self)
        guard let fallback = translations["en"] ?? translations.sorted(by: { $0.key < $1.key }).first?.value else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Text needs at least one language.")
        }
        self.init(fallback, translations: translations)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if translations.isEmpty {
            try container.encode(fallback)
        } else {
            try container.encode(translations)
        }
    }
}

/// Where a celebration's dates and meaning come from, so they can be checked and kept current.
public struct CelebrationProvenance: Codable, Hashable, Sendable {
    public var sources: [URL]
    public var publisher: String?
    /// Who sets the dates: a church calendar, a ministry, a moon-sighting authority.
    public var authority: String?
    public var dataVersion: String?
    public var reviewed: CivilDate?
    /// The years the dates are published for, for annual tables; nil for a rule that holds every year.
    public var coverage: Coverage?

    public struct Coverage: Codable, Hashable, Sendable {
        public var from: Int
        public var through: Int

        public init(from: Int, through: Int) {
            self.from = from
            self.through = through
        }
    }

    public init(
        sources: [URL] = [], publisher: String? = nil, authority: String? = nil, dataVersion: String? = nil,
        reviewed: CivilDate? = nil, coverage: Coverage? = nil
    ) {
        self.sources = sources
        self.publisher = publisher
        self.authority = authority
        self.dataVersion = dataVersion
        self.reviewed = reviewed
        self.coverage = coverage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sources = try container.decodeIfPresent([URL].self, forKey: .sources) ?? []
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        authority = try container.decodeIfPresent(String.self, forKey: .authority)
        dataVersion = try container.decodeIfPresent(String.self, forKey: .dataVersion)
        reviewed = try container.decodeIfPresent(CivilDate.self, forKey: .reviewed)
        coverage = try container.decodeIfPresent(Coverage.self, forKey: .coverage)
    }
}

/// When a celebration happens: its rule, the tradition the rule belongs to, and how a day begins.
public struct CelebrationCalendar: Hashable, Sendable {
    public var rule: CelebrationRule
    /// The named tradition or region the dates follow, such as "Mexico" or "Gregorian civil calendar".
    public var tradition: String?
    public var boundary: CelebrationBoundary
    /// Dates that await confirmation, such as a moon sighting.
    public var isProvisional: Bool

    public init(
        rule: CelebrationRule, tradition: String? = nil, boundary: CelebrationBoundary = .civilDay,
        isProvisional: Bool = false
    ) {
        self.rule = rule
        self.tradition = tradition
        self.boundary = boundary
        self.isProvisional = isProvisional
    }
}

extension CelebrationCalendar: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, start, end, tradition, boundary, provisional
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case CelebrationRule.fixedKind:
            let start = try container.decode(MonthDay.self, forKey: .start)
            rule = .fixed(start: start, end: try container.decodeIfPresent(MonthDay.self, forKey: .end) ?? start)
        default:
            rule = .unsupported(kind: kind)
        }
        tradition = try container.decodeIfPresent(String.self, forKey: .tradition)
        boundary = try container.decodeIfPresent(CelebrationBoundary.self, forKey: .boundary) ?? .civilDay
        isProvisional = try container.decodeIfPresent(Bool.self, forKey: .provisional) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch rule {
        case .fixed(let start, let end):
            try container.encode(CelebrationRule.fixedKind, forKey: .kind)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
        case .unsupported(let kind):
            try container.encode(kind, forKey: .kind)
        }
        try container.encodeIfPresent(tradition, forKey: .tradition)
        try container.encode(boundary, forKey: .boundary)
        try container.encode(isProvisional, forKey: .provisional)
    }
}

/// How a celebration's day begins. Only civil days are resolved today; the others are kept so the
/// catalogue can say a festival starts the evening before, and decorations follow the civil date.
public enum CelebrationBoundary: Hashable, Sendable, Codable {
    case civilDay
    case sunset
    case nightfall
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "civil-day": self = .civilDay
        case "sunset": self = .sunset
        case "nightfall": self = .nightfall
        case let other: self = .unknown(other)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .civilDay: try container.encode("civil-day")
        case .sunset: try container.encode("sunset")
        case .nightfall: try container.encode("nightfall")
        case .unknown(let other): try container.encode(other)
        }
    }
}

/// Which manifest format and Native version a contribution needs.
public struct CelebrationCompatibility: Codable, Hashable, Sendable {
    /// The `celebrations` format version; this build reads `supportedManifestVersion` and older.
    public var manifestVersion: Int
    /// The oldest Native that can show it, such as "1.4".
    public var minimumNativeVersion: String?

    public static let supportedManifestVersion = 1

    public init(manifestVersion: Int = 1, minimumNativeVersion: String? = nil) {
        self.manifestVersion = manifestVersion
        self.minimumNativeVersion = minimumNativeVersion
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manifestVersion = try container.decodeIfPresent(Int.self, forKey: .manifestVersion) ?? 1
        minimumNativeVersion = try container.decodeIfPresent(String.self, forKey: .minimumNativeVersion)
    }
}
