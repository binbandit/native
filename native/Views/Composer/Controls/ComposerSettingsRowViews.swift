import SwiftUI

/// What a row's gutter holds: the current choice's check, a policy's lock, or the loader while the
/// agent confirms a change. Rows carry no icons.
enum ComposerSettingsMark: Equatable {
    case none, check, lock, loading
}

/// How a row is lit: under the pointer, highlighted by the keyboard (with the focus ring), or as the
/// filter's first match, which Return picks.
enum ComposerSettingsHighlight: Equatable {
    case none, hover, keyboard, match
}

/// The one row anatomy of the settings popover: gutter, name, trailing detail or value. The current
/// choice is marked by its check only, never a fill.
struct ComposerSettingsRow<Name: View, Trailing: View>: View {
    var mark: ComposerSettingsMark = .none
    var highlight: ComposerSettingsHighlight = .none
    var isDimmed = false
    @ViewBuilder let name: () -> Name
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        HStack(spacing: 0) {
            ComposerSettingsGutter(mark: mark)
                .padding(.trailing, DS.Space.sm)
            name()
                .font(DS.ComposerSettings.rowFont)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: DS.Space.lg)
            trailing()
        }
        .foregroundStyle(isDimmed ? .dsTextTertiary : .dsTextPrimary)
        .padding(.horizontal, DS.Space.md)
        .frame(height: DS.ComposerSettings.rowHeight)
        .background(fill, in: shape)
        .overlay {
            if highlight == .keyboard {
                shape.strokeBorder(.dsKeyboardFocusIndicator, lineWidth: 2)
            }
        }
        .contentShape(shape)
        .dsFocusShape(shape)
        .padding(.horizontal, DS.ComposerSettings.popoverInset)
    }

    private var fill: Color {
        switch highlight {
        case .none: .clear
        case .hover: .dsHover
        case .keyboard, .match: .dsSelected
        }
    }
}

extension ComposerSettingsRow where Trailing == EmptyView {
    init(
        mark: ComposerSettingsMark = .none, highlight: ComposerSettingsHighlight = .none, isDimmed: Bool = false,
        @ViewBuilder name: @escaping () -> Name
    ) {
        self.init(mark: mark, highlight: highlight, isDimmed: isDimmed, name: name, trailing: { EmptyView() })
    }
}

struct ComposerSettingsGutter: View {
    let mark: ComposerSettingsMark

    var body: some View {
        Group {
            switch mark {
            case .none: Color.clear
            case .check:
                Image(systemName: "checkmark").font(DS.ComposerSettings.checkFont)
            case .lock:
                Image(systemName: "lock").font(DS.ComposerSettings.lockFont).foregroundStyle(.dsTextTertiary)
            case .loading:
                DotGridLoader(pattern: .waiting).frame(width: DS.Size.navIcon - 2, height: DS.Size.navIcon - 2)
                    .foregroundStyle(.dsTextSecondary)
            }
        }
        .frame(width: DS.ComposerSettings.selectionWidth, height: DS.ComposerSettings.selectionWidth)
        .accessibilityHidden(true)
    }
}

/// A section's header on the text edge, with a lock or a switch at its trailing edge.
struct ComposerSettingsHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Text(title)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Space.sm)
            trailing()
        }
        .font(.dsCaption)
        .foregroundStyle(.dsTextTertiary)
        .frame(height: DS.ComposerSettings.lineHeight)
        .composerSettingsTextEdge()
        .padding(.bottom, DS.Space.xs)
    }
}

extension ComposerSettingsHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// The line under a list: the highlighted or current choice in words, or what went wrong with the
/// one action that fixes it. It reserves the tallest of `reserving`, so the popover keeps its height
/// as the pointer moves.
struct ComposerSettingsCaption: View {
    let text: AttributedString?
    var reserving: [AttributedString] = []
    var isFailure = false
    var isKeyboardFocused = false
    var action: ComposerSettingsTaskRow.Command?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(reserving.enumerated()), id: \.offset) { _, line in
                Text(line).hidden().accessibilityHidden(true)
            }
            if let text {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                    Text(text)
                    if let action {
                        Button(action.title, action: action.action)
                            .composerSettingsCommandFocus(isKeyboardFocused)
                            .buttonStyle(.plain)
                            .font(DS.ComposerSettings.detailMediumFont)
                            .foregroundStyle(.dsTextPrimary)
                            .dsHitTarget(DS.ComposerSettings.lineHeight)
                    }
                }
                .id(text)
                .transition(.opacity)
            }
        }
        .font(DS.ComposerSettings.detailFont)
        .foregroundStyle(isFailure ? .dsDanger : .dsTextSecondary)
        .lineSpacing(DS.Space.xxs)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .composerSettingsTextEdge()
        .padding(.top, DS.Space.xs)
        .animation(.dsQuick, value: text)
    }
}

/// The first line of a page that opens in place: back to Task Settings, and the page's title.
struct ComposerSettingsPageHeader: View {
    let title: String
    var isKeyboardFocused = false
    let onBack: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack {
            Text(title)
                .font(DS.ComposerSettings.rowFont.weight(.medium))
                .foregroundStyle(.dsTextPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                Button(action: onBack) {
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "chevron.left")
                            .font(DS.ComposerSettings.glyphFont)
                            .frame(width: DS.ComposerSettings.selectionWidth)
                        Text("Task Settings")
                    }
                    .font(DS.ComposerSettings.rowFont)
                    .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextSecondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .composerSettingsCommandFocus(isKeyboardFocused)
                .trackHover($isHovered)
                .dsHitTarget(DS.ComposerSettings.rowHeight)
                .accessibilityLabel("Back to Task Settings")
                Spacer(minLength: 0)
            }
        }
        .frame(height: DS.ComposerSettings.rowHeight)
        .padding(.horizontal, DS.ComposerSettings.popoverInset + DS.Space.md)
        .padding(.bottom, DS.Space.xs)
    }
}

extension View {
    /// Puts text on the popover's one text edge, with the rule's inset on the trailing side.
    func composerSettingsTextEdge() -> some View {
        padding(.leading, DS.ComposerSettings.popoverInset + DS.ComposerSettings.textLeading)
            .padding(.trailing, DS.ComposerSettings.ruleInset)
    }

    /// One section of the popover: its padding, and the hairline rule above every section but the
    /// first.
    func composerSettingsSection(ruled: Bool) -> some View {
        padding(.vertical, DS.ComposerSettings.sectionInset)
            .overlay(alignment: .top) {
                if ruled { ComposerSettingsRule() }
            }
    }
}

/// The hairline between the popover's sections. Translucent, so it reads on the popover's material
/// in dark mode too, where the opaque separator color nearly matches it.
struct ComposerSettingsRule: View {
    var body: some View {
        Rectangle()
            .fill(.dsFill)
            .frame(height: 1)
            .padding(.horizontal, DS.ComposerSettings.ruleInset)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Auxiliary commands take the same visible keyboard ring as choice rows.
    func composerSettingsCommandFocus(_ isFocused: Bool) -> some View {
        background(isFocused ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.control))
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .strokeBorder(.dsKeyboardFocusIndicator, lineWidth: 2)
                }
            }
    }
}
