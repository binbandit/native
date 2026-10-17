/// A highlighter maps its token kinds onto these shared roles before selecting a color.
public enum CodeTokenRole: String, CaseIterable, Sendable {
    case foreground
    case background
    case comment
    case keyword
    case string
    case constant
    case function
    case variable
    case tag
    case type
    case `operator`
    case regex
    case invalid
    case punctuation
    case insertedForeground
    case insertedBackground
    case deletedForeground
    case deletedBackground
    case changedForeground
    case changedBackground
    case selection
    case lineHighlight
}
