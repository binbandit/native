/// An event as metrics, for destinations that take metrics rather than events (Sentry): one count
/// per event, tagged with its enum and version attributes, and one distribution per duration.
/// Names and tags come only from the schema, so `TelemetryMetric.allowlist` can vet them again on
/// the way out.
public struct TelemetryMetric: Hashable, Sendable {
    public enum Value: Hashable, Sendable {
        case count(UInt)
        case milliseconds(Int64)
    }

    public let name: String
    public let value: Value
    public let tags: [String: String]

    /// Every name and tag the schema can produce.
    public struct Allowlist: Hashable, Sendable {
        public let counts: Set<String>
        public let distributions: Set<String>
        public let tagKeys: Set<String>
    }

    public static let allowlist = Allowlist(
        counts: Set(TelemetryEventName.allCases.map(countName)),
        distributions: Set(TelemetryAttributeKey.allCases.filter(\.isDuration).map(distributionName)),
        tagKeys: Set(TelemetryAttributeKey.allCases.filter { !$0.isDuration }.map(\.rawValue)))

    static func countName(_ event: TelemetryEventName) -> String {
        "native.\(event.rawValue)"
    }

    static func distributionName(_ key: TelemetryAttributeKey) -> String {
        "native.\(key.rawValue)"
    }
}

extension TelemetryRecord {
    public var metrics: [TelemetryMetric] {
        let tags = Dictionary(
            uniqueKeysWithValues: attributes.filter { !$0.key.isDuration }.map {
                ($0.key.rawValue, $0.value.description)
            })
        let durations = attributes.compactMap { attribute -> TelemetryMetric? in
            guard attribute.key.isDuration, case .int(let milliseconds) = attribute.value.kind else { return nil }
            return TelemetryMetric(
                name: TelemetryMetric.distributionName(attribute.key), value: .milliseconds(milliseconds), tags: tags)
        }
        return [TelemetryMetric(name: TelemetryMetric.countName(name), value: .count(1), tags: tags)] + durations
    }
}
