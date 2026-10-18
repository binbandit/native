import SwiftUI
import Terminal

/// A task's terminal: a resize divider, the tab bar, and the selected tab's terminal or the state
/// that stands in for it (shell exited, didn't start, terminal unavailable in this build).
struct TerminalPanel: View {
    static let minHeight: CGFloat = 120
    /// Room the transcript and composer always keep above the panel.
    static let minContentAbove: CGFloat = 220

    let panel: TerminalPanelModel
    let store: TerminalStore
    let maxHeight: CGFloat

    var body: some View {
        @Bindable var preferences = store.preferences
        let height = min(max(preferences.panelHeight, Self.minHeight), maxHeight)
        VStack(spacing: 0) {
            TerminalResizeDivider(height: $preferences.panelHeight, range: Self.minHeight...maxHeight)
            TerminalTabBar(panel: panel, showsTabs: store.availability == .available)
                .background(.dsSurfaceSunken.opacity(store.backgroundOpacity))
            if case .ghosttyInvalid(_, let diagnostics) = store.configStatus {
                TerminalConfigNotice(diagnostics: diagnostics, reload: store.reloadGhosttyConfig)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: height)
        .background { backdrop }
        .confirmationDialog(
            "Close this terminal?",
            isPresented: isConfirmingClose,
            titleVisibility: .visible,
            presenting: panel.confirmingClose
        ) { id in
            Button("Close Terminal", role: .destructive) { panel.close(id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("A program is still running in it, and closing the terminal ends it.")
        }
    }

    @ViewBuilder private var content: some View {
        switch store.availability {
        case .available:
            if let tab = panel.tabs.selected {
                TerminalTabContent(panel: panel, tab: tab)
            }
        case .notBuilt:
            TerminalUnavailableView()
                .background(.dsSurfaceSunken.opacity(store.backgroundOpacity))
        case .failed(let reason):
            ErrorState(
                "The terminal couldn't start",
                recovery: reason,
                suggestion: "Quit and reopen Native to try again.",
                layout: .pane
            )
        }
    }

    /// Behind a translucent terminal, a blur of what's behind the window, as the sidebar has; the
    /// tab bar and the terminal each lay their own color over it at the terminal's opacity.
    @ViewBuilder private var backdrop: some View {
        if store.backgroundOpacity < 1 {
            #if os(macOS)
            DSBehindWindowMaterial(material: .underWindowBackground)
            #else
            Rectangle().fill(.thinMaterial)
            #endif
        } else {
            Color.dsSurfaceSunken
        }
    }

    private var isConfirmingClose: Binding<Bool> {
        Binding(
            get: { panel.confirmingClose != nil },
            set: { if !$0 { panel.confirmingClose = nil } }
        )
    }
}

/// The panel's top edge: a hairline that resizes the panel when dragged.
private struct TerminalResizeDivider: View {
    @Binding var height: Double
    let range: ClosedRange<CGFloat>
    @State private var startHeight: Double?

    /// How far each VoiceOver or keyboard adjustment moves the divider.
    private static let step: Double = 40

    var body: some View {
        Rectangle()
            .fill(.dsSeparator)
            .frame(height: 1)
            .overlay {
                // A taller strip than the hairline, so it's easy to grab.
                Color.clear
                    .frame(height: DS.Space.md)
                    .contentShape(.rect)
                    .pointerStyle(.rowResize)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = startHeight ?? clamped(height)
                                startHeight = start
                                height = clamped(start - value.translation.height)
                            }
                            .onEnded { _ in startHeight = nil }
                    )
            }
            .accessibilityElement()
            .accessibilityLabel("Terminal height")
            .accessibilityValue("\(Int(clamped(height))) points")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: height = clamped(height + Self.step)
                case .decrement: height = clamped(height - Self.step)
                @unknown default: break
                }
            }
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// Above the terminal when the user's Ghostty config didn't load: what's wrong in a line, what
/// Native did, and where to see it all.
private struct TerminalConfigNotice: View {
    let diagnostics: [String]
    let reload: () -> Void
    @Environment(SettingsPresentation.self) private var settings

    var body: some View {
        NoticeBanner(
            tone: .warning,
            title: "Your Ghostty config didn't load, so Native's terminal settings are in use",
            detail: diagnostics.first
        ) {
            Button("Show All") { settings.open(.terminal) }
                .buttonStyle(.ds(.ghost))
            Button("Reload", action: reload)
                .buttonStyle(.ds(.secondary))
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.bottom, DS.Space.xs)
    }
}
