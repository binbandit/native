import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The drag under way in the sidebar and where it would drop, after Conductor's `drag.ts`: projects
/// reorder among projects, sessions only within their own project. What's being dragged is tracked
/// here rather than decoded from the pasteboard, and drags carry a private type, so nothing dragged
/// in from elsewhere is mistaken for a reorder.
@Observable
final class SidebarDragState {
    /// A row in the sidebar that can be dragged or dropped on.
    enum Item: Hashable {
        case project(Project.ID)
        case session(SessionKey, in: Project.ID)

        var target: SidebarMoveTarget {
            switch self {
            case .project(let id): .project(id)
            case .session(let key, let project): .session(key, in: project)
            }
        }
    }

    /// Where a drop would land: before (`.top`) or after (`.bottom`) a row.
    struct Drop: Equatable {
        let item: Item
        let edge: VerticalEdge
    }

    private(set) var dragged: Item?
    private(set) var drop: Drop?

    /// The pasteboard type sidebar drags carry. A dynamic type needs no Info.plist declaration and
    /// no other app produces it.
    static let contentType = UTType(filenameExtension: "native-sidebar-item", conformingTo: .data) ?? .data

    /// Starts dragging `item`, returning what the drag carries.
    func begin(_ item: Item) -> NSItemProvider {
        dragged = item
        drop = nil
        let provider = NSItemProvider()
        // The payload is empty: the drop reads `dragged`. Keeping it in-process means it never
        // lands in another app either.
        provider.registerDataRepresentation(forTypeIdentifier: Self.contentType.identifier, visibility: .ownProcess) { completion in
            completion(Data(), nil)
            return nil
        }
        return provider
    }

    /// Whether `dragged` may land next to `item`.
    func accepts(_ item: Item) -> Bool {
        switch (dragged, item) {
        case (.project(let dragged), .project(let target)):
            dragged != target
        case (.session(let dragged, let draggedProject), .session(let target, let targetProject)):
            dragged != target && draggedProject == targetProject
        default:
            false
        }
    }

    func isDragging(_ item: Item) -> Bool {
        dragged == item
    }

    /// The edge of `item` the drop indicator shows at, if the drop would land there.
    func indicatorEdge(for item: Item) -> VerticalEdge? {
        drop?.item == item ? drop?.edge : nil
    }

    fileprivate func hover(_ item: Item, edge: VerticalEdge) {
        drop = accepts(item) ? Drop(item: item, edge: edge) : nil
    }

    fileprivate func leave(_ item: Item) {
        if drop?.item == item {
            drop = nil
        }
    }

    fileprivate func finish() -> (dragged: Item, drop: Drop)? {
        defer {
            dragged = nil
            drop = nil
        }
        guard let dragged, let drop, accepts(drop.item) else { return nil }
        return (dragged, drop)
    }
}

extension View {
    /// Lets the view be dragged to reorder `item`, dimming it while it is (as Conductor does).
    func sidebarDraggable(_ item: SidebarDragState.Item, title: String, state: SidebarDragState) -> some View {
        opacity(state.isDragging(item) ? 0.5 : 1)
            .onDrag {
                state.begin(item)
            } preview: {
                SidebarDragPreview(title: title)
            }
    }

    /// Lets rows of `item`'s kind drop before or after the view, showing Conductor's indicator line.
    /// While `isActive` is false the view ignores drags, so they reach an enclosing target (a project
    /// group under its sessions). `onDrop` gets what was dropped and where.
    func sidebarDropTarget(
        _ item: SidebarDragState.Item,
        state: SidebarDragState,
        isActive: Bool = true,
        onDrop: @escaping (SidebarDragState.Item, SidebarDragState.Drop) -> Void
    ) -> some View {
        modifier(SidebarDropTargetModifier(item: item, state: state, isActive: isActive, onDrop: onDrop))
    }
}

private struct SidebarDropTargetModifier: ViewModifier {
    let item: SidebarDragState.Item
    let state: SidebarDragState
    let isActive: Bool
    let onDrop: (SidebarDragState.Item, SidebarDragState.Drop) -> Void

    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        let edge = state.indicatorEdge(for: item)
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .onDrop(
                of: isActive ? [SidebarDragState.contentType] : [],
                delegate: SidebarDropDelegate(item: item, height: height, state: state, onDrop: onDrop)
            )
            .overlay(alignment: edge == .top ? .top : .bottom) {
                if let edge {
                    SidebarDropIndicator()
                        // Centered in the gap between rows.
                        .offset(y: edge == .top ? -SidebarDropIndicator.gapOffset : SidebarDropIndicator.gapOffset)
                }
            }
    }
}

private struct SidebarDropDelegate: DropDelegate {
    let item: SidebarDragState.Item
    let height: CGFloat
    let state: SidebarDragState
    let onDrop: (SidebarDragState.Item, SidebarDragState.Drop) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        state.accepts(item)
    }

    func dropEntered(info: DropInfo) {
        hover(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        hover(info)
        return DropProposal(operation: state.accepts(item) ? .move : .forbidden)
    }

    func dropExited(info: DropInfo) {
        state.leave(item)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let (dragged, drop) = state.finish() else { return false }
        onDrop(dragged, drop)
        return true
    }

    private func hover(_ info: DropInfo) {
        state.hover(item, edge: info.location.y < height / 2 ? .top : .bottom)
    }
}

/// Conductor's drop indicator: a 2pt rounded line in the ring color across the row.
private struct SidebarDropIndicator: View {
    /// Half the 4pt gap between rows plus half the line, so it sits between them.
    static let gapOffset = DS.Space.xxs + 1

    var body: some View {
        Capsule()
            .fill(.dsTextTertiary)
            .frame(height: DS.Space.xxs)
            .padding(.horizontal, DS.Space.xs)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Conductor's drag ghost: the row's title on a raised, outlined, rounded card.
private struct SidebarDragPreview: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.dsCalloutBook)
            .foregroundStyle(.dsTextPrimary)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .frame(maxWidth: DS.Size.sidebarWidth - DS.Space.xxl, alignment: .leading)
            .background(.dsOverlay, in: .rect(cornerRadius: DS.Radius.row, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                    .strokeBorder(.dsSeparator)
            }
            .fixedSize()
    }
}

extension AppModel {
    /// Applies a sidebar drop: `dragged` lands before or after the row it was dropped on.
    func applySidebarDrop(_ dragged: SidebarDragState.Item, _ drop: SidebarDragState.Drop) {
        switch (dragged, drop.item) {
        case (.project(let source), .project(let target)):
            let ids = projects.all.map(\.id)
            guard let from = ids.firstIndex(of: source), let to = ids.firstIndex(of: target) else { return }
            moveProjects(fromOffsets: [from], toOffset: drop.edge == .top ? to : to + 1)
        case (.session(let source, let project), .session(let target, _)):
            let keys = sessions(in: project).map(\.id)
            guard let from = keys.firstIndex(of: source), let to = keys.firstIndex(of: target) else { return }
            moveSessions(in: project, fromOffsets: [from], toOffset: drop.edge == .top ? to : to + 1)
        default:
            break
        }
    }
}
