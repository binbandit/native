import SwiftUI

/// Usage limits that are close or reached, as `LimitChip`s at the bar's leading edge. The usage feature supplies the statuses and what opening one does; the
/// app passes both in, so the bar doesn't depend on that feature. Shows nothing while no limit is
/// near.
struct LimitsStatusItem: StatusBarItem {
    let statuses: @MainActor () -> [LimitStatus]
    /// Opens a limit's details; without it, the chip's tooltip says it all.
    var onOpen: (@MainActor (LimitStatus) -> Void)?

    let id = "limits"
    let title = "Usage Limits"
    let placement = StatusBarPlacement.leading
    let order = 0

    var content: some View {
        LimitsSegment(statuses: statuses, onOpen: onOpen)
    }
}

private struct LimitsSegment: View {
    let statuses: @MainActor () -> [LimitStatus]
    let onOpen: (@MainActor (LimitStatus) -> Void)?

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            ForEach(statuses()) { status in
                LimitChip(status: status, action: onOpen.map { open in { open(status) } })
            }
        }
    }
}
