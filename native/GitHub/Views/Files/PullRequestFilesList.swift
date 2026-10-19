import GitHub
import SwiftUI

/// Every file's diff as one flat list of rows: headers, hunks in blocks of a few dozen lines,
/// conversations and notices, virtualized so only what's near the screen exists however big the
/// pull request is (`PullRequestFilesStack`). Long lines are cut off where the pane ends, measured
/// here.
struct PullRequestFilesList: View {
    let model: PullRequestPageModel

    @State private var width: CGFloat = 0
    @State private var characterWidth: CGFloat = 0
    @State private var isShiftDown = false

    var body: some View {
        PullRequestFilesStack(
            model: model, rows: model.rows, width: width, characterWidth: characterWidth, isShiftDown: isShiftDown
        )
        #if DEBUG && os(macOS)
        // `-nativeAutoScroll`: scrolls this list by itself, for measuring frame times.
        .task { PlatformAutoScroll.startIfRequested() }
        #endif
        .overlay(alignment: .bottom) { PullRequestSelectionLimitNote(model: model) }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .background(alignment: .topLeading) { characterRuler }
        .trackingShift($isShiftDown)
    }

    /// Ten characters of code, measured once, for the width of one.
    private var characterRuler: some View {
        Text(verbatim: "0000000000")
            .codeTextStyle(.compact)
            .fixedSize()
            .hidden()
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                characterWidth = $0 / 10
            }
            .accessibilityHidden(true)
    }
}

extension View {
    /// Follows the Shift key, for shift-click ranges. iPadOS has no modifier tracking here; there,
    /// "Extend Comment to Here" in a line's menu does the same.
    fileprivate func trackingShift(_ isDown: Binding<Bool>) -> some View {
        #if os(macOS)
        onModifierKeysChanged(mask: .shift) { _, keys in isDown.wrappedValue = keys.contains(.shift) }
        #else
        self
        #endif
    }
}
