/// `${experiment:<id>}` in a data-only plugin's settings, filled with that experiment's value.
public enum ExperimentPlaceholder {
    /// The experiments `text` refers to, in order.
    public static func references(in text: String) -> [String] {
        text.matches(of: pattern).map { String($0.output.1) }
    }

    /// `text` with each placeholder replaced by `value(id)`.
    public static func substitute(in text: String, value: (String) -> String) -> String {
        text.replacing(pattern) { value(String($0.output.1)) }
    }

    private static var pattern: Regex<(Substring, Substring)> {
        /\$\{experiment:([^}]*)\}/
    }
}
