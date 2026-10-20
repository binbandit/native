import SessionTools
import SwiftUI

/// The workbench under the composer: its strip is the handle and the tab bar at once, every shell
/// and run a tab of its own beside any other workbench tool with something to show. It exists only
/// while it has a tab; closed, only the strip shows.
struct SessionToolsWorkbench: View {
    let tabs: [SessionToolContribution]
    /// The open tool, whose pane shows under the strip.
    let open: SessionToolContribution?
    let context: (SessionToolContribution) -> SessionToolContext
    let select: (SessionToolID) -> Void
    let close: () -> Void
    /// The most the pane may take, so the conversation and the composer keep their room.
    let maxHeight: CGFloat

    @AppStorage("sessionTools.workbenchHeight") private var height = Double(SessionToolMetrics.workbenchHeight)
    @State private var dragStart: Double?

    var body: some View {
        VStack(spacing: 0) {
            resizeEdge
            HStack(spacing: DS.Space.sm) {
                SessionToolsStrip(tools: tabs, open: open?.id, context: context, select: select)
                Spacer(minLength: 0)
                if let open {
                    open.stripAccessory?(context(open))
                }
                IconButton(
                    open == nil ? "Show Workbench" : "Hide Workbench",
                    systemImage: open == nil ? "chevron.up" : "chevron.down"
                ) {
                    if open == nil {
                        tabs.first.map { select($0.id) }
                    } else {
                        close()
                    }
                }
            }
            .padding(.horizontal, DS.Space.md)
            .frame(height: SessionToolMetrics.stripHeight)
            if let open {
                SeparatorLine()
                open.pane?(context(open))
                    .frame(height: clamped(height))
            }
        }
        .background(.dsBackground)
    }

    private func clamped(_ value: Double) -> CGFloat {
        min(
            max(CGFloat(value), SessionToolMetrics.workbenchMinHeight),
            max(maxHeight, SessionToolMetrics.workbenchMinHeight))
    }

    /// The strip's top edge, dragged to resize the pane while it's open.
    private var resizeEdge: some View {
        SeparatorLine()
            .overlay {
                if open != nil {
                    Color.clear
                        .frame(height: DS.Space.md)
                        .contentShape(.rect)
                        #if os(macOS)
                    .pointerStyle(.rowResize)
                        #endif
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { value in
                                    let start = dragStart ?? Double(clamped(height))
                                    dragStart = start
                                    height = Double(clamped(start - value.translation.height))
                                }
                                .onEnded { _ in dragStart = nil }
                        )
                        .accessibilityElement()
                        .accessibilityLabel("Workbench height")
                        .accessibilityValue("\(Int(clamped(height))) points")
                        .accessibilityAdjustableAction { direction in
                            let step = Double(DS.Space.xxxl)
                            height = Double(clamped(height + (direction == .increment ? step : -step)))
                        }
                }
            }
    }
}
