import ApplicationServices
import Foundation

/// The commands that read and act on the instance's accessibility tree.
struct Driver {
    let instance: Instance
    let app: AXUIElement

    init(instance: Instance) {
        self.instance = instance
        app = AXUIElementCreateApplication(instance.pid)
        AXUIElementSetMessagingTimeout(app, 5)
    }

    /// The app's windows, sheets, popovers and open context menus; the menu bar only when asked.
    func snapshot(menus: Bool = false) -> [Node] {
        // Some elements list the application among their children; it and the menu bar are cut off
        // wherever they turn up, so a walk reads the windows once.
        var skipping: Set<AXUIElement> = [app]
        if !menus, let bar = Accessibility.element(Accessibility.attribute(app, kAXMenuBarAttribute)) {
            skipping.insert(bar)
        }
        // The windows first (the app's children can leave them out), then anything else it shows.
        var roots = Accessibility.attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        roots += Accessibility.children(app).filter { !skipping.contains($0) && !roots.contains($0) }
        return Accessibility.snapshot(roots, skipping: skipping)
    }

    /// The tree, one element a line, indented by depth. Containers with nothing to say are left out
    /// (their children take their place) unless `raw`.
    func tree(depth: Int, raw: Bool, frames: Bool, menus: Bool) -> [String] {
        let nodes = snapshot(menus: menus)
        var shownDepth = [Int](repeating: 0, count: nodes.count)
        var lines: [String] = []
        for (index, node) in nodes.enumerated() {
            let parentDepth = node.parent.map { shownDepth[$0] } ?? -1
            let hidden = !raw && node.isAnonymous
            shownDepth[index] = hidden ? parentDepth : parentDepth + 1
            guard !hidden, shownDepth[index] <= depth else { continue }
            lines.append(String(repeating: "  ", count: max(shownDepth[index], 0)) + node.describe(frames: frames))
        }
        return lines
    }

    /// Every match, numbered as `--nth` counts them, with the nearest named element around it.
    func find(_ query: Query) -> [String] {
        let nodes = snapshot()
        return query.matches(in: nodes).enumerated().map { index, node in
            var line = "[\(index)] " + node.describe(frames: true)
            if let context = context(of: node, in: nodes) { line += "  in " + context }
            return line
        }
    }

    /// The `nth` best match, telling stderr when others matched as well as it did.
    func pick(
        _ query: Query, nth: Int, from nodes: [Node], where usable: (Node) -> Bool = { _ in true }
    )
        throws(DriveError) -> Node
    {
        let matches = query.matches(in: nodes).filter(usable)
        guard nth < matches.count else {
            if matches.isEmpty {
                throw DriveError("nothing matches \(Node.quoted(query.text)); `tree` or `find` shows what's there")
            }
            throw DriveError("only \(matches.count) match \(Node.quoted(query.text)); --nth counts from 0")
        }
        let best = matches.filter { query.rank($0) == query.rank(matches[0]) }.count
        if nth == 0, best > 1 {
            FileHandle.standardError.write(
                Data(
                    "drive: \(best) elements match \(Node.quoted(query.text)) equally; took the first (--nth picks another)\n"
                        .utf8))
        }
        return matches[nth]
    }

    /// Presses a button, menu item or anything with `AXPress`; selects a row that can only be
    /// selected; else presses the nearest pressable element around it, like the button a label is in.
    /// A button that opens a menu goes through `choose`.
    func press(_ query: Query, nth: Int, item: String?) throws(DriveError) -> String {
        let nodes = snapshot()
        let node = try pick(query, nth: nth, from: nodes)
        guard node.enabled else { throw DriveError("\(node.describe()) is disabled") }
        var candidate: Node? = node
        for _ in 0..<4 {
            guard let current = candidate else { break }
            if Accessibility.actions(current.element).contains(kAXPressAction) {
                if ["AXMenuButton", "AXPopUpButton"].contains(current.role) {
                    return try choose(item, from: current, opening: kAXPressAction)
                }
                guard item == nil else { throw DriveError("\(current.describe()) doesn't open a menu; drop --item") }
                return "pressed " + current.describe() + perform(kAXPressAction, on: current.element)
            }
            if current.role != "AXWindow", Accessibility.isSettable(current.element, kAXSelectedAttribute) {
                guard
                    AXUIElementSetAttributeValue(current.element, kAXSelectedAttribute as CFString, kCFBooleanTrue)
                        == .success
                else { throw DriveError("couldn't select \(current.describe())") }
                return "selected " + current.describe()
            }
            candidate = current.parent.map { nodes[$0] }
        }
        let actions = Accessibility.actions(node.element).map(Self.actionName)
        throw DriveError(
            "\(node.describe()) can't be pressed; its actions: "
                + (actions.isEmpty ? "none" : actions.joined(separator: ", ")))
    }

    /// Opens the menu `node` shows and picks `item` from it, or, without one, lists its items. Either
    /// way the menu is closed before this returns: an open menu takes the mouse and keys of whoever
    /// is at the Mac, so the driver never leaves one open between commands.
    func choose(_ item: String?, from node: Node, opening action: String) throws(DriveError) -> String {
        let opened = perform(action, on: node.element)
        defer { closeMenus() }
        var items: [Node] = []
        let deadline = Date().addingTimeInterval(2)
        repeat {
            items = snapshot().filter { $0.role == kAXMenuItemRole && $0.name != nil }
            if !items.isEmpty { break }
            usleep(50_000)
        } while Date() < deadline
        guard let item else {
            let lines = items.map { "  " + $0.describe() }
            return (["the menu of \(node.describe())\(opened), closed again; pick one with --item:"] + lines)
                .joined(separator: "\n")
        }
        guard let match = Query(text: item, role: nil).matches(in: items).first else {
            throw DriveError(
                "the menu of \(node.describe()) has no \(Node.quoted(item)); it has: "
                    + items.compactMap { $0.name.map { Node.quoted($0) } }.joined(separator: ", "))
        }
        guard match.enabled else { throw DriveError("\(match.describe()) is disabled") }
        return "chose \(match.describe()) from \(node.describe())" + perform(kAXPressAction, on: match.element)
    }

    /// Closes every menu the app has open: Escape, which a menu takes at once, then `AXCancel` for
    /// any still open.
    private func closeMenus() {
        guard snapshot().contains(where: { $0.role == kAXMenuRole }) else { return }
        try? Keyboard(pid: instance.pid).press("escape")
        usleep(100_000)
        for menu in snapshot().filter({ $0.role == kAXMenuRole }) {
            _ = perform(kAXCancelAction, on: menu.element)
        }
    }

    /// Performs an action, waiting at most 2 s: an action that opens a menu or a modal dialog holds
    /// the app until it closes, so a timeout means it happened and the app is showing something.
    func perform(_ action: String, on element: AXUIElement) -> String {
        AXUIElementSetMessagingTimeout(element, 2)
        switch AXUIElementPerformAction(element, action as CFString) {
        case .success: return ""
        case .cannotComplete: return " (the app is busy; it may be showing a menu or dialog)"
        case let error: return " (AX error \(error.rawValue))"
        }
    }

    /// Writes a text field's or text area's value, as typing would leave it; numbers for switches
    /// and sliders. `-` reads the value from stdin.
    func set(_ query: Query, nth: Int, to text: String) throws(DriveError) -> String {
        let nodes = snapshot()
        let node = try pick(query, nth: nth, from: nodes) { Accessibility.isSettable($0.element, kAXValueAttribute) }
        let value: CFTypeRef
        if Accessibility.attribute(node.element, kAXValueAttribute) is NSNumber {
            guard let number = Double(text) else { throw DriveError("\(node.describe()) takes a number") }
            value = NSNumber(value: number)
        } else {
            value = text as CFString
        }
        guard AXUIElementSetAttributeValue(node.element, kAXValueAttribute as CFString, value) == .success else {
            throw DriveError("\(node.describe()) didn't take the value")
        }
        let now = Accessibility.text(Accessibility.attribute(node.element, kAXValueAttribute)) ?? ""
        let note = now == text ? "" : " (it now reads \(Node.quoted(now)))"
        return "set \(node.shortRole) \(Node.quoted(node.name ?? "")) to \(Node.quoted(text))\(note)"
    }

    enum ScrollDirection: String {
        case up, down, top, bottom, reveal
    }

    /// Scrolls the scroll area at or around the match a page, or to an end, through its scroll bar.
    /// `reveal` scrolls the match itself into view.
    func scroll(_ query: Query, nth: Int, _ direction: ScrollDirection) throws(DriveError) -> String {
        let nodes = snapshot()
        let node = try pick(query, nth: nth, from: nodes)
        if direction == .reveal {
            return "revealed " + node.describe() + perform("AXScrollToVisible", on: node.element)
        }
        guard let areaIndex = scrollArea(around: node, in: nodes) else {
            throw DriveError("no scroll area at or around \(node.describe())")
        }
        let area = nodes[areaIndex]
        if let bar = Accessibility.element(Accessibility.attribute(area.element, kAXVerticalScrollBarAttribute)),
            Accessibility.isSettable(bar, kAXValueAttribute)
        {
            let current = (Accessibility.attribute(bar, kAXValueAttribute) as? NSNumber)?.doubleValue ?? 0
            let visible = area.frame?.height ?? 0
            let content = nodes.filter { $0.parent == areaIndex }.compactMap { $0.frame?.height }.max() ?? visible
            let page = content > visible ? visible * 0.85 / (content - visible) : 1
            let target =
                switch direction {
                case .top: 0.0
                case .bottom: 1.0
                case .up: max(0, current - page)
                case .down, .reveal: min(1, current + page)
                }
            guard AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, NSNumber(value: target)) == .success
            else { throw DriveError("\(area.describe()) didn't scroll") }
            return "scrolled \(area.describe()) to \(String(format: "%.2f", target)) of its length"
        }
        // No scroll bar (SwiftUI hides some): bring the first or last element into view instead.
        let inside = nodes[(areaIndex + 1)...].prefix { $0.depth > area.depth }.filter { !$0.isAnonymous }
        let edge: Node? =
            switch direction {
            case .top: inside.first
            case .bottom: inside.last
            default: nil
            }
        guard let edge else {
            throw DriveError("\(area.describe()) has no scroll bar to page; use top, bottom or reveal <element>")
        }
        return "revealed " + edge.describe() + perform("AXScrollToVisible", on: edge.element)
    }

    /// Polls until an element matches (or, `gone`, until none does), every quarter second.
    func wait(_ query: Query, timeout: Double, gone: Bool) throws(DriveError) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let match = query.matches(in: snapshot()).first
            if gone, match == nil { return "gone: " + Node.quoted(query.text) }
            if !gone, let match { return "found " + match.describe() }
            usleep(250_000)
        } while Date() < deadline
        throw DriveError(
            "after \(Int(timeout)) s, \(Node.quoted(query.text)) is \(gone ? "still there" : "not there"); `tree` shows what is"
        )
    }

    /// The text a person would read, in order: static text, text fields, headings and links, under
    /// the match or in every window.
    func text(_ query: Query?, nth: Int) throws(DriveError) -> [String] {
        let nodes = snapshot()
        var scope = nodes[...]
        if let query {
            let node = try pick(query, nth: nth, from: nodes)
            scope = nodes[node.index...].prefix { $0.index == node.index || $0.depth > node.depth }
        }
        var lines: [String] = []
        for node in scope {
            let line: String? =
                switch node.role {
                case "AXStaticText", "AXTextArea", "AXTextField": node.value ?? node.name
                case "AXHeading", "AXLink": node.name ?? node.value
                default: nil
                }
            if let line, !line.isEmpty, line != lines.last { lines.append(line) }
        }
        return lines
    }

    func focused() throws(DriveError) -> String {
        guard let element = Accessibility.element(Accessibility.attribute(app, kAXFocusedUIElementAttribute)),
            let node = Accessibility.snapshot([element], maxDepth: 0).first
        else { throw DriveError("nothing has focus in \(instance.name)") }
        return node.describe(frames: true)
    }

    /// The match's accessibility actions, by the name `action` takes.
    func actions(_ query: Query, nth: Int) throws(DriveError) -> [String] {
        let node = try pick(query, nth: nth, from: snapshot())
        return [node.describe()] + Accessibility.actions(node.element).map { "  " + Self.actionName($0) }
    }

    /// Performs one of the match's actions by name: `AXShowMenu` opens its context menu, and
    /// SwiftUI's named actions go by their names. Never `AXRaise`, which brings the window forward.
    func action(_ query: Query, nth: Int, _ name: String, item: String?) throws(DriveError) -> String {
        guard name.caseInsensitiveCompare("AXRaise") != .orderedSame else {
            throw DriveError("AXRaise brings the window in front of other people's work; not allowed")
        }
        let node = try pick(query, nth: nth, from: snapshot())
        let actions = Accessibility.actions(node.element)
        guard
            let action = actions.first(where: {
                $0 == name || Self.actionName($0).caseInsensitiveCompare(name) == .orderedSame
            })
                ?? actions.first(where: { Self.actionName($0).localizedCaseInsensitiveContains(name) })
        else {
            throw DriveError(
                "\(node.describe()) has no action \(Node.quoted(name)); it has: "
                    + actions.map(Self.actionName).joined(separator: ", "))
        }
        if action == kAXShowMenuAction {
            return try choose(item, from: node, opening: action)
        }
        guard item == nil else { throw DriveError("--item goes with AXShowMenu") }
        return "\(Self.actionName(action)) on \(node.describe())" + perform(action, on: node.element)
    }

    /// SwiftUI names custom actions `Name:Archive\nTarget:…`; this is the `Archive` part.
    static func actionName(_ action: String) -> String {
        guard action.hasPrefix("Name:") else { return action }
        return String(action.dropFirst(5).prefix { $0 != "\n" })
    }

    private func context(of node: Node, in nodes: [Node]) -> String? {
        var parent = node.parent
        while let index = parent {
            let ancestor = nodes[index]
            if let name = ancestor.name { return ancestor.shortRole + " " + Node.quoted(name, limit: 50) }
            parent = ancestor.parent
        }
        return nil
    }

    private func scrollArea(around node: Node, in nodes: [Node]) -> Int? {
        var current: Int? = node.index
        while let at = current {
            if nodes[at].role == kAXScrollAreaRole { return at }
            current = nodes[at].parent
        }
        return nodes[(node.index + 1)...].prefix { $0.depth > node.depth }.first { $0.role == kAXScrollAreaRole }?.index
    }
}
