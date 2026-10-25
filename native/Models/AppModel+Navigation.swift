import ACP
import Foundation

// Where the user is: moving between sessions, back and forward through what they've viewed, and
// which sessions have news they haven't seen.
extension AppModel {
    /// The live sidebar order includes filters and day disclosures while All in view is enabled.
    var sidebarNavigationOrder: [SessionKey] {
        if offersTaskPeek, let order = archiveNavigationOrder { return order.archiveSessionOrder() }
        return sessionList.map(\.id)
    }

    /// Selects the session `offset` places from the selected one in the sidebar, wrapping around.
    func selectSession(offset: Int, in visible: [SessionKey]? = nil) {
        let keys = visible ?? sidebarNavigationOrder
        guard !keys.isEmpty else { return }
        let index = selection.flatMap(keys.firstIndex(of:)).map { $0 + offset } ?? (offset > 0 ? 0 : keys.count - 1)
        selection = keys[(index % keys.count + keys.count) % keys.count]
    }

    var canGoBack: Bool {
        history.canMove(.back, from: selection, isAvailable: catalog.contains)
    }

    var canGoForward: Bool {
        history.canMove(.forward, from: selection, isAvailable: catalog.contains)
    }

    func goBack() {
        move(.back)
    }

    func goForward() {
        move(.forward)
    }

    private func move(_ direction: NavigationHistory<SessionKey>.Direction) {
        guard let destination = history.move(direction, from: selection, isAvailable: catalog.contains) else { return }
        isNavigatingHistory = true
        selection = destination
        isNavigatingHistory = false
    }

    // MARK: - Unread

    func isUnread(_ key: SessionKey) -> Bool {
        unread.contains(key)
    }

    func setUnread(_ key: SessionKey, _ isUnread: Bool) {
        unread.set(key, unread: isUnread)
    }

    /// A turn that ends, a permission request or a question in a session the user isn't looking at leaves its
    /// sidebar row unread. Subagents' news shows on the session they belong to.
    func markUnread(after event: SessionEvent) {
        let context =
            switch event {
            case .turnEnded(let context, _), .turnFailed(let context, _, _, _), .permissionRequested(let context, _),
                .questionAsked(let context, _):
                context
            case .needsUser(let context, _), .failed(let context, _): context
            case .sessionStarted, .promptSent, .usageUpdated: nil as SessionContext?
            }
        guard let context, let key = session(clientID: context.clientID)?.root.key, key != selection,
            catalog.contains(key)
        else { return }
        unread.set(key, unread: true)
    }
}
