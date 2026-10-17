import CodeThemes
import Testing

// Parameterized tests otherwise print every palette value in their names.
extension CodeTheme: CustomTestStringConvertible {
    public var testDescription: String { id.rawValue }
}
