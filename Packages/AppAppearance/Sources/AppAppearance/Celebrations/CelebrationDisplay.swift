/// How long a celebration shows and how it feels. The core observance always shows; `windows` are
/// longer, decorative choices around it, counted in calendar days from the core dates so they work
/// for any calendar.
public struct CelebrationDisplay: Hashable, Sendable {
    public var windows: [CelebrationWindow]
    /// The window someone gets until they choose: `core`, or one of `windows`.
    public var defaultWindow: CelebrationWindow.ID
    public var treatment: Treatment

    public enum Treatment: Hashable, Sendable {
        case festive
        /// A solemn or reflective observance, which should never get a party treatment.
        case quiet
        case unknown(String)
    }

    public init(
        windows: [CelebrationWindow] = [], defaultWindow: CelebrationWindow.ID = .core, treatment: Treatment = .festive
    ) {
        self.windows = windows
        self.defaultWindow = defaultWindow
        self.treatment = treatment
    }

    /// The window to use for a stored choice. A choice the manifest no longer offers falls back to its
    /// default, without changing what's stored, so a calendar update never rewrites a preference.
    public func window(_ id: CelebrationWindow.ID?) -> CelebrationWindow {
        let all = [CelebrationWindow.core] + windows
        return all.first { $0.id == id } ?? all.first { $0.id == defaultWindow } ?? .core
    }

    /// Every choice, core dates first.
    public var choices: [CelebrationWindow] {
        [.core] + windows
    }
}

extension CelebrationDisplay: Codable {
    private enum CodingKeys: String, CodingKey {
        case windows, defaultWindow, treatment
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windows = try container.decodeIfPresent([CelebrationWindow].self, forKey: .windows) ?? []
        defaultWindow = try container.decodeIfPresent(CelebrationWindow.ID.self, forKey: .defaultWindow) ?? .core
        treatment =
            switch try container.decodeIfPresent(String.self, forKey: .treatment) ?? "festive" {
            case "festive": .festive
            case "quiet": .quiet
            case let other: .unknown(other)
            }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(windows, forKey: .windows)
        try container.encode(defaultWindow, forKey: .defaultWindow)
        let treatment =
            switch treatment {
            case .festive: "festive"
            case .quiet: "quiet"
            case .unknown(let other): other
            }
        try container.encode(treatment, forKey: .treatment)
    }
}

/// A span of days around the core observance: Halloween's season reaches 30 days before 31 October
/// and 7 after it.
public struct CelebrationWindow: Codable, Hashable, Sendable, Identifiable {
    public struct ID: RawRepresentable, Hashable, Sendable, Codable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        /// The observance itself, which every celebration has.
        public static let core = ID("core")
    }

    public var id: ID
    public var title: LocalizedText
    public var daysBefore: Int
    public var daysAfter: Int

    /// The longest a window may reach either side, so a mistyped manifest can't decorate all year.
    public static let maximumReach = 60

    public static let core = CelebrationWindow(id: .core, title: "Core dates", daysBefore: 0, daysAfter: 0)

    public init(id: ID, title: LocalizedText, daysBefore: Int, daysAfter: Int) {
        self.id = id
        self.title = title
        self.daysBefore = daysBefore
        self.daysAfter = daysAfter
    }

    public var isCore: Bool { daysBefore == 0 && daysAfter == 0 }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ID.self, forKey: .id)
        title = try container.decode(LocalizedText.self, forKey: .title)
        daysBefore = try container.decodeIfPresent(Int.self, forKey: .daysBefore) ?? 0
        daysAfter = try container.decodeIfPresent(Int.self, forKey: .daysAfter) ?? 0
    }
}
