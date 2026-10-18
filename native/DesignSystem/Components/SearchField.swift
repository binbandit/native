import SwiftUI

/// The one search field: a magnifier, the query, a clear button once something's typed, and an
/// optional trailing accessory (a shortcut hint, a record-keys button). Escape clears it. It's
/// outlined like other inputs and turns the accent when focused or `isHighlighted`, with no fill of
/// its own, so it reads the same on the content pane and on the translucent sidebar.
///
///     SearchField("Filter pull requests", text: $query)
///     SearchField("Search settings", text: $query, focus: $focus, equals: .search) { Kbd("⌘F") }
///
/// The text takes `font`, so a field matches what's around it: Settings' 14pt, the window's 12pt.
public struct SearchField<Field: Hashable, Accessory: View>: View {
    public enum Size: Sendable {
        /// 28pt, beside small buttons and in nav columns.
        case medium
        /// 32pt, beside selects and large buttons.
        case large

        var height: CGFloat {
            switch self {
            case .medium: DS.Size.controlSM
            case .large: DS.Size.controlMD
            }
        }
    }

    let title: String
    @Binding var text: String
    let prompt: Text?
    let size: Size
    let font: Font
    let isHighlighted: Bool
    let focus: FocusState<Field?>.Binding?
    let field: Field
    let accessory: Accessory

    @FocusState private var ownFocus: Field?

    /// - Parameters:
    ///   - title: What the field searches, for VoiceOver; also the prompt unless `prompt` is given.
    ///   - focus: The caller's focus state, so it can move focus here (⌘F) and see when it's here.
    ///   - isHighlighted: Draws the focus outline while the field is busy another way, such as
    ///     recording a shortcut.
    public init(
        _ title: String,
        text: Binding<String>,
        prompt: Text? = nil,
        size: Size = .medium,
        font: Font = .dsBody,
        isHighlighted: Bool = false,
        focus: FocusState<Field?>.Binding,
        equals field: Field,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        _text = text
        self.prompt = prompt
        self.size = size
        self.font = font
        self.isHighlighted = isHighlighted
        self.focus = focus
        self.field = field
        self.accessory = accessory()
    }

    private var focusBinding: FocusState<Field?>.Binding {
        focus ?? $ownFocus
    }

    private var isFocused: Bool {
        focusBinding.wrappedValue == field
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: SearchFieldMetrics.glyph))
                .foregroundStyle(.dsTextSecondary)
                .accessibilityHidden(true)
            TextField(title, text: $text, prompt: (prompt ?? Text(title)).foregroundStyle(.dsTextTertiary))
                .textFieldStyle(.plain)
                .labelsHidden()
                .font(font)
                .foregroundStyle(.dsTextPrimary)
                .focused(focusBinding, equals: field)
            if !text.isEmpty {
                Button("Clear \(title)", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.system(size: SearchFieldMetrics.glyph))
                    .foregroundStyle(.dsTextTertiary)
                    .help("Clear")
            }
            accessory
        }
        .padding(.leading, DS.Space.md + DS.Space.xxs)
        .padding(.trailing, DS.Space.sm)
        .frame(height: size.height)
        .overlay {
            shape.strokeBorder(isFocused || isHighlighted ? Color.dsAccent : Color.dsBorder, lineWidth: 1)
        }
        .onKeyPress(.escape) {
            guard !text.isEmpty else { return .ignored }
            text = ""
            return .handled
        }
    }
}

extension SearchField where Field == Bool {
    /// A field that keeps its own focus.
    public init(
        _ title: String,
        text: Binding<String>,
        prompt: Text? = nil,
        size: Size = .medium,
        font: Font = .dsBody,
        isHighlighted: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        _text = text
        self.prompt = prompt
        self.size = size
        self.font = font
        self.isHighlighted = isHighlighted
        focus = nil
        field = true
        self.accessory = accessory()
    }
}

extension SearchField where Field == Bool, Accessory == EmptyView {
    public init(
        _ title: String,
        text: Binding<String>,
        prompt: Text? = nil,
        size: Size = .medium,
        font: Font = .dsBody
    ) {
        self.init(title, text: text, prompt: prompt, size: size, font: font) { EmptyView() }
    }
}

extension SearchField where Accessory == EmptyView {
    public init(
        _ title: String,
        text: Binding<String>,
        prompt: Text? = nil,
        size: Size = .medium,
        font: Font = .dsBody,
        focus: FocusState<Field?>.Binding,
        equals field: Field
    ) {
        self.init(title, text: text, prompt: prompt, size: size, font: font, focus: focus, equals: field) {
            EmptyView()
        }
    }
}

private enum SearchFieldMetrics {
    /// The magnifier and clear glyphs, a size below the 12–14pt text.
    static let glyph: CGFloat = 12
}

#Preview("Search field") {
    @Previewable @State var empty = ""
    @Previewable @State var typed = "worktree"
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SearchField("Filter pull requests", text: $empty)
            SearchField("Search settings", text: $empty, font: .ds(14)) { Kbd("⌘F") }
            SearchField("Filter skills", text: $typed, size: .large, font: .ds(14))
        }
        .frame(width: 280)
        .padding(DS.Space.xl)
    }
}
