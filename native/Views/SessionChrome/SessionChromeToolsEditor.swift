#if DEBUG && NATIVE_SESSION_CHROME_WIP
import SwiftUI

/// Tools, over the session: every feature that can put something on this screen, where each one
/// lives, and the ones turned off. In D it's a map of the window, and a tool moves by dragging it
/// to a place or from its menu; in A, B and C each tool is on (in that direction's one place) or
/// off. Changes apply as they're made.
struct SessionChromeToolsEditor: View {
    let chrome: SessionChromeModel

    var body: some View {
        let places = chrome.direction.places
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Tools")
                    .font(.dsTitle3)
                    .foregroundStyle(.dsTextPrimary)
                Text(
                    places.count > 1
                        ? "Put each tool where you want it, or turn it off. With every tool off, a task is the conversation and the composer."
                        : "Turn on the tools you use. With every tool off, a task is the conversation and the composer."
                )
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            if places.count > 1 {
                map
            } else if let place = places.first {
                SessionChromePlaceWell(place: place, chrome: chrome)
            }
            SessionChromePlaceWell(place: nil, chrome: chrome)
            HStack(spacing: DS.Space.md) {
                Text(
                    places.count > 1 ? "Drag a tool, or click it for its places." : "Click a tool to turn it on or off."
                )
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                Spacer()
                Button("Reset") { chrome.reset() }
                    .buttonStyle(.ds(.ghost))
                Button("Done") { chrome.isArranging = false }
                    .buttonStyle(.ds(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Space.xl)
        .frame(width: SessionChromeMetrics.editorWidth)
        .background(.dsBackground, in: RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous).strokeBorder(.dsBorder, lineWidth: 1)
        }
        .dsShadow(DS.Shadow.modal)
        .background {
            Button("Close Tools") { chrome.isArranging = false }
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
    }

    /// The window as a map: the header over the conversation, the side panel beside it, the
    /// workbench under it.
    private var map: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            VStack(spacing: DS.Space.md) {
                SessionChromePlaceWell(place: .header, chrome: chrome)
                VStack(spacing: DS.Space.xs) {
                    Text("Conversation")
                        .font(.dsBodyMedium)
                    Text("and the composer, always")
                        .font(.dsCaption)
                }
                .foregroundStyle(.dsTextTertiary)
                .frame(maxWidth: .infinity, minHeight: SessionChromeMetrics.editorConversationHeight)
                .background(.dsSurfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                SessionChromePlaceWell(place: .bottom, chrome: chrome)
            }
            SessionChromePlaceWell(place: .side, chrome: chrome)
                .frame(width: SessionChromeMetrics.editorSideWidth)
        }
    }
}

/// One place in the tools editor, holding its tools; nil is Off.
private struct SessionChromePlaceWell: View {
    let place: SessionChromePlace?
    let chrome: SessionChromeModel

    @State private var isTargeted = false

    var body: some View {
        let tools = place.map { chrome.arrangement.tools(in: $0) } ?? chrome.arrangement.off
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                Text(place?.title ?? "Off")
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                Text(place?.summary ?? "Not on this screen. Their commands still work.")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
            }
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: SessionChromeMetrics.editorChipMinWidth), spacing: DS.Space.sm,
                        alignment: .leading)
                ],
                alignment: .leading, spacing: DS.Space.sm
            ) {
                ForEach(tools) { tool in
                    SessionChromeToolChip(tool: tool, place: place, chrome: chrome)
                }
            }
            .frame(minHeight: DS.Size.controlSM, alignment: .topLeading)
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            isTargeted ? Color.dsSelected : .clear,
            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(
                    place == nil ? Color.dsSeparator : .dsBorder,
                    style: StrokeStyle(lineWidth: 1, dash: SessionChromeMetrics.editorDash))
        }
        .dropDestination(for: String.self) { items, _ in
            let dropped = items.compactMap(SessionChromeTool.init(rawValue:))
            for tool in dropped {
                chrome.move(tool, to: place)
            }
            return !dropped.isEmpty
        } isTargeted: {
            isTargeted = $0
        }
    }
}

/// A tool in the editor: drag it to a place, or pick one from its menu.
private struct SessionChromeToolChip: View {
    let tool: SessionChromeTool
    let place: SessionChromePlace?
    let chrome: SessionChromeModel

    var body: some View {
        Menu {
            ForEach(chrome.direction.places) { option in
                Toggle(
                    option.title, isOn: Binding(get: { place == option }, set: { _ in chrome.move(tool, to: option) }))
            }
            Divider()
            Toggle("Off", isOn: Binding(get: { place == nil }, set: { _ in chrome.move(tool, to: nil) }))
        } label: {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: tool.systemImage)
                    .font(.dsCaption)
                    .foregroundStyle(place == nil ? .dsTextTertiary : .dsTextSecondary)
                Text(tool.title)
                    .font(.dsBodyMedium)
                    .foregroundStyle(place == nil ? .dsTextSecondary : .dsTextPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Space.md)
            .frame(maxWidth: .infinity, minHeight: DS.Size.controlSM, alignment: .leading)
            .background(
                place == nil ? Color.clear : .dsSurfaceRaised,
                in: RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous).strokeBorder(.dsBorder, lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .draggable(tool.rawValue)
        .help(tool.summary)
        .accessibilityLabel("\(tool.title), \(place?.title ?? "off")")
    }
}
#endif
