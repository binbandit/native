import Foundation

extension ConfigOption.SelectOption {
    /// The description without a leading "<name>:" that restates the option's name ("Read Only: looks
    /// around…" for "Read-only"), for showing under the name. Case, spaces and hyphens don't count
    /// in the comparison. Nil when there's no description, or nothing past the name.
    public var descriptionWithoutName: String? {
        guard let description else { return nil }
        guard let colon = description.firstIndex(of: ":"),
            Self.comparable(description[..<colon]) == Self.comparable(name)
        else { return description }
        let rest = description[description.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard let first = rest.first else { return nil }
        return first.uppercased() + rest.dropFirst()
    }

    private static func comparable(_ text: some StringProtocol) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
