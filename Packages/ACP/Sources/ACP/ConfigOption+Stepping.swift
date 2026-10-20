import Foundation

extension ConfigOption {
    /// The value after the current one: what a control that steps up through the levels (the
    /// composer's effort meter) sets next. Nil at the last value, since wrapping around would drop the
    /// session from its highest level to its lowest without a word, and nil for an option that isn't
    /// a select or whose current value it doesn't list, since stepping from a value it can't place
    /// would land on the lowest level too.
    public var valueAfterCurrent: String? {
        guard case .select(let current, let values) = kind,
            let index = values.firstIndex(where: { $0.value == current }), index + 1 < values.count
        else { return nil }
        return values[index + 1].value
    }
}
