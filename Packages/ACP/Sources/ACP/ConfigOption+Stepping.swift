import Foundation

extension ConfigOption {
    /// The value after the current one, wrapping around: what a control that steps through the
    /// levels (the composer's effort meter) sets next. Nil for an option that isn't a select, or
    /// whose current value it doesn't list: stepping from a value it can't place would land on the
    /// first, lowest level rather than the next one.
    public var valueAfterCurrent: String? {
        guard case .select(let current, let values) = kind,
            let index = values.firstIndex(where: { $0.value == current })
        else { return nil }
        return values[(index + 1) % values.count].value
    }
}
