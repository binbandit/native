import GitHub
import SwiftUI

/// Every file's diff as one flat lazy list: headers, hunks in blocks of a few dozen lines,
/// conversations and notices are all rows, so only what's on screen is ever built, however big a
/// file is. Long lines are cut off where the pane ends, measured here.
struct PullRequestFilesList: View {
    let model: PullRequestPageModel

    @State private var width: CGFloat = 0
    @State private var characterWidth: CGFloat = 0
    @State private var isShiftDown = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let error = model.patchError {
                        NoticeBanner(
                            tone: .warning, title: "Some diffs couldn't load", detail: error.localizedDescription
                        ) {
                            Button("Try Again") { Task { await model.loadNextPatchPage() } }
                                .buttonStyle(.ds(.secondary))
                        }
                        .padding(.bottom, DS.Space.lg)
                    }
                    ForEach(model.rows) { row in
                        PullRequestFilesRowView(
                            model: model, row: row, width: width, characterWidth: characterWidth,
                            isShiftDown: isShiftDown
                        )
                        .fileCardSlice(row.slice)
                    }
                    if model.filesCursor != nil {
                        Text("Loading the rest of the \(model.totalFiles) files…")
                            .font(.dsBody)
                            .foregroundStyle(.dsTextTertiary)
                    }
                }
                .padding(DS.Space.lg)
                .coordinateSpace(.named(PullRequestPageModel.filesSpace))
            }
            .scrollContentBackground(.hidden)
            #if (DEBUG || NATIVE_PERF) && os(macOS)
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
            .onChange(of: model.focusedFile) { _, path in
                guard let path else { return }
                withAnimation(.dsStandard) { proxy.scrollTo("h:\(path)", anchor: .top) }
                model.focusedFile = nil
            }
        }
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
