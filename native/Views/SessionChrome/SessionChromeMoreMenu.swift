#if DEBUG && NATIVE_SESSION_CHROME_WIP
import SwiftUI

/// A place's "…": its tools that aren't showing a tab right now, and the tools editor.
struct SessionChromeMoreMenu: View {
    let tools: [SessionChromeTool]
    let chrome: SessionChromeModel

    var body: some View {
        Menu {
            ForEach(tools) { tool in
                Button(tool.title, systemImage: tool.systemImage) { chrome.show(tool) }
            }
            if !tools.isEmpty {
                Divider()
            }
            Button("Tools…", systemImage: "slider.horizontal.3") { chrome.isArranging = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.dsCaption)
                .foregroundStyle(.dsTextSecondary)
                .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More Tools")
        .accessibilityLabel("More Tools")
    }
}
#endif
