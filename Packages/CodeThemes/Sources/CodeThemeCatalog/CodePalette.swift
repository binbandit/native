public struct CodePalette: Sendable, Hashable {
    public let foreground: CodeColor
    public let background: CodeColor
    public let comment: CodeColor
    public let keyword: CodeColor
    public let string: CodeColor
    public let constant: CodeColor
    public let function: CodeColor
    public let variable: CodeColor
    public let tag: CodeColor
    public let type: CodeColor
    public let `operator`: CodeColor
    public let regex: CodeColor
    public let invalid: CodeColor
    public let punctuation: CodeColor
    public let insertedForeground: CodeColor
    public let insertedBackground: CodeColor
    public let deletedForeground: CodeColor
    public let deletedBackground: CodeColor
    public let changedForeground: CodeColor
    public let changedBackground: CodeColor
    public let selection: CodeColor
    public let lineHighlight: CodeColor
    /// Roles set a weight heavier than the code around them, for a theme whose hierarchy leans on
    /// weight as well as hue (Native's dark keywords). Empty for most themes.
    public let strong: Set<CodeTokenRole>

    public init(
        foreground: CodeColor,
        background: CodeColor,
        comment: CodeColor,
        keyword: CodeColor,
        string: CodeColor,
        constant: CodeColor,
        function: CodeColor,
        variable: CodeColor,
        tag: CodeColor,
        type: CodeColor,
        operator: CodeColor,
        regex: CodeColor,
        invalid: CodeColor,
        punctuation: CodeColor,
        insertedForeground: CodeColor,
        insertedBackground: CodeColor,
        deletedForeground: CodeColor,
        deletedBackground: CodeColor,
        changedForeground: CodeColor,
        changedBackground: CodeColor,
        selection: CodeColor,
        lineHighlight: CodeColor,
        strong: Set<CodeTokenRole> = []
    ) {
        self.foreground = foreground
        self.background = background
        self.comment = comment
        self.keyword = keyword
        self.string = string
        self.constant = constant
        self.function = function
        self.variable = variable
        self.tag = tag
        self.type = type
        self.operator = `operator`
        self.regex = regex
        self.invalid = invalid
        self.punctuation = punctuation
        self.insertedForeground = insertedForeground
        self.insertedBackground = insertedBackground
        self.deletedForeground = deletedForeground
        self.deletedBackground = deletedBackground
        self.changedForeground = changedForeground
        self.changedBackground = changedBackground
        self.selection = selection
        self.lineHighlight = lineHighlight
        self.strong = strong
    }

    public subscript(role: CodeTokenRole) -> CodeColor {
        switch role {
        case .foreground: foreground
        case .background: background
        case .comment: comment
        case .keyword: keyword
        case .string: string
        case .constant: constant
        case .function: function
        case .variable: variable
        case .tag: tag
        case .type: type
        case .operator: `operator`
        case .regex: regex
        case .invalid: invalid
        case .punctuation: punctuation
        case .insertedForeground: insertedForeground
        case .insertedBackground: insertedBackground
        case .deletedForeground: deletedForeground
        case .deletedBackground: deletedBackground
        case .changedForeground: changedForeground
        case .changedBackground: changedBackground
        case .selection: selection
        case .lineHighlight: lineHighlight
        }
    }
}
