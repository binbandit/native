/// Several tasks picked at once for a bulk action, the way a Mac list picks them: ⌘-click adds or
/// removes one, ⇧-click picks the run from the last one clicked, select all picks a list. The
/// anchor is where a ⇧-click's run starts.
public struct TaskListSelection<ID: Hashable & Sendable>: Equatable, Sendable {
    public private(set) var ids: Set<ID> = []
    public private(set) var anchor: ID?

    public init() {}

    public var isEmpty: Bool { ids.isEmpty }
    public var count: Int { ids.count }

    public func contains(_ id: ID) -> Bool {
        ids.contains(id)
    }

    /// ⌘-click: adds `id`, or takes it out if it's in. Starting from nothing, `current` (the task
    /// on screen) comes along, so ⌘-clicking a second task picks both.
    public mutating func toggle(_ id: ID, current: ID? = nil) {
        if ids.isEmpty, let current, current != id {
            ids.insert(current)
        }
        if ids.remove(id) == nil {
            ids.insert(id)
        }
        anchor = id
    }

    /// ⇧-click: picks every task between the anchor (or `current`, without one) and `id` in
    /// `order`, replacing what was picked. Without either, or with one missing from `order`, it
    /// picks `id` alone.
    public mutating func extend(to id: ID, in order: [ID], current: ID? = nil) {
        guard let end = order.firstIndex(of: id) else { return }
        let start = (anchor ?? current).flatMap(order.firstIndex(of:)) ?? end
        ids = Set(order[min(start, end)...max(start, end)])
        if anchor == nil { anchor = order[start] }
    }

    /// Picks all of `order`; the first becomes the anchor.
    public mutating func selectAll(_ order: [ID]) {
        ids = Set(order)
        anchor = order.first
    }

    public mutating func clear() {
        ids = []
        anchor = nil
    }

    /// Lets go of tasks that are gone (archived, deleted, filtered out).
    public mutating func keep(only existing: Set<ID>) {
        ids.formIntersection(existing)
        if let anchor, !existing.contains(anchor) {
            self.anchor = nil
        }
    }

    /// The picked tasks in `order`, for acting on them in the list's order.
    public func ordered(by order: [ID]) -> [ID] {
        order.filter(ids.contains)
    }
}
