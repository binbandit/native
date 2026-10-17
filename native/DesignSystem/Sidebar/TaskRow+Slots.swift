import SwiftUI

// `TaskRow` initializers for rows that leave one or both slots empty. Swift can't default a
// generic parameter, so each combination is spelled out; they all forward to the full initializer.

extension TaskRow where Leading == EmptyView, Accessory == EmptyView {
    public init(
        title: String,
        status: TaskStatus,
        isSelected: Bool = false,
        isUnread: Bool = false,
        subtitle: String? = nil,
        date: Date? = nil,
        diff: (added: Int, removed: Int)? = nil,
        badge: TaskBadge? = nil,
        indent: TaskRowIndent = .grouped,
        action: @escaping () -> Void,
        onArchive: (() -> Void)? = nil
    ) {
        self.init(
            title: title, status: status, isSelected: isSelected, isUnread: isUnread, subtitle: subtitle,
            date: date, diff: diff, badge: badge, indent: indent, leading: EmptyView(), accessory: EmptyView(),
            action: action, onArchive: onArchive
        )
    }
}

extension TaskRow where Accessory == EmptyView {
    public init(
        title: String,
        status: TaskStatus,
        isSelected: Bool = false,
        isUnread: Bool = false,
        subtitle: String? = nil,
        date: Date? = nil,
        diff: (added: Int, removed: Int)? = nil,
        badge: TaskBadge? = nil,
        indent: TaskRowIndent = .grouped,
        leading: Leading,
        action: @escaping () -> Void,
        onArchive: (() -> Void)? = nil
    ) {
        self.init(
            title: title, status: status, isSelected: isSelected, isUnread: isUnread, subtitle: subtitle,
            date: date, diff: diff, badge: badge, indent: indent, leading: leading, accessory: EmptyView(),
            action: action, onArchive: onArchive
        )
    }
}

extension TaskRow where Leading == EmptyView {
    public init(
        title: String,
        status: TaskStatus,
        isSelected: Bool = false,
        isUnread: Bool = false,
        subtitle: String? = nil,
        date: Date? = nil,
        diff: (added: Int, removed: Int)? = nil,
        badge: TaskBadge? = nil,
        indent: TaskRowIndent = .grouped,
        accessory: Accessory,
        action: @escaping () -> Void,
        onArchive: (() -> Void)? = nil
    ) {
        self.init(
            title: title, status: status, isSelected: isSelected, isUnread: isUnread, subtitle: subtitle,
            date: date, diff: diff, badge: badge, indent: indent, leading: EmptyView(), accessory: accessory,
            action: action, onArchive: onArchive
        )
    }
}

extension TaskRow where Leading == Image, Accessory == EmptyView {
    /// A row led by an SF Symbol, e.g. the agent's.
    public init(
        title: String,
        status: TaskStatus,
        isSelected: Bool = false,
        isUnread: Bool = false,
        subtitle: String? = nil,
        date: Date? = nil,
        diff: (added: Int, removed: Int)? = nil,
        badge: TaskBadge? = nil,
        indent: TaskRowIndent = .grouped,
        leadingSymbol: String,
        action: @escaping () -> Void,
        onArchive: (() -> Void)? = nil
    ) {
        self.init(
            title: title, status: status, isSelected: isSelected, isUnread: isUnread, subtitle: subtitle,
            date: date, diff: diff, badge: badge, indent: indent, leading: Image(systemName: leadingSymbol),
            accessory: EmptyView(), action: action, onArchive: onArchive
        )
    }
}

extension TaskRow where Leading == Image {
    /// A row led by an SF Symbol, with a trailing accessory.
    public init(
        title: String,
        status: TaskStatus,
        isSelected: Bool = false,
        isUnread: Bool = false,
        subtitle: String? = nil,
        date: Date? = nil,
        diff: (added: Int, removed: Int)? = nil,
        badge: TaskBadge? = nil,
        indent: TaskRowIndent = .grouped,
        leadingSymbol: String,
        accessory: Accessory,
        action: @escaping () -> Void,
        onArchive: (() -> Void)? = nil
    ) {
        self.init(
            title: title, status: status, isSelected: isSelected, isUnread: isUnread, subtitle: subtitle,
            date: date, diff: diff, badge: badge, indent: indent, leading: Image(systemName: leadingSymbol),
            accessory: accessory, action: action, onArchive: onArchive
        )
    }
}
