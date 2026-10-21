/// A session tool's identity: its feature's own stable name for it ("changes", "terminal"). Where
/// the user put each tool is saved by it, so it never changes once shipped.
public struct SessionToolID: RawRepresentable, Hashable, Sendable, Codable, CodingKeyRepresentable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }

    public var description: String { rawValue }
}
