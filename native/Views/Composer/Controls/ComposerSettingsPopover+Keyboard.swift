import ACP
import SwiftUI

/// Letters typed within a second of each other, for jumping to a row by its name as menus do.
struct ComposerSettingsTypeAhead {
    private(set) var text = ""
    private var last = Date.distantPast

    mutating func append(_ characters: String, at now: Date = .now) -> String {
        text = now.timeIntervalSince(last) < 1 ? text + characters : characters
        last = now
        return text
    }
}

// The keys `docs/keyboard.md` lists under "Task settings": arrows walk every row across sections,
// Tab jumps between sections, Return chooses and closes, Space chooses and stays, Escape clears the
// filter, then leaves a page, then closes.
extension ComposerSettingsPopover {
    /// The rows the keyboard reaches, by section, skipping headers and locked levels.
    var sections: [[Target]] {
        if isStopped { return onRestart == nil ? [] : [[.restart]] }
        switch page {
        case .choices(let id):
            return [[.back] + (rows.first { $0.id == id }.map(pageTargets) ?? [])]
        case .model:
            let retry: [Target] =
                failure?.optionID == settings.model?.option.id && failure?.retry != nil ? [.retry] : []
            return [
                [.back] + (fastMode == nil ? [] : [.fastMode]) + (modelList?.rows.map { .model($0.id) } ?? []) + retry
            ]
        case nil:
            var sections: [[Target]] = []
            if let model = settings.model {
                sections.append(
                    DS.isTouchPlatform ? [.model(model.value)] : modelList?.rows.map { .model($0.id) } ?? [])
            }
            if fastMode != nil, !DS.isTouchPlatform { sections.append([.fastMode]) }
            if settings.effort != nil { sections.append([.effort]) }
            let levels = settings.autonomyLevels.filter { !isForbidden($0.value) }
            if !levels.isEmpty { sections.append(levels.map { .autonomy($0.value) }) }
            let reachable = rows.filter { if case .note = $0.kind { false } else { true } }
            if !reachable.isEmpty { sections.append(reachable.map { .row($0.id) }) }
            if failure?.retry != nil { sections.append([.retry]) }
            return sections.filter { !$0.isEmpty }
        }
    }

    func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // Compose has native controls before the settings. Preserve a native Tab route through
        // those controls and all the settings, including switches and retry actions.
        let isTab = press.key == .tab || press.key == KeyEquivalent("\u{19}")
        if isTab, leadingContent != nil {
            highlighted = nil
            usesNativeTraversal = true
            return .ignored
        }
        // A container's Boolean FocusState stays true for focused descendants. Once Tab hands
        // Compose to native controls, their activation and navigation keys must stay native too.
        if leadingContent != nil, usesNativeTraversal, !isFilterFocused, press.key != .escape {
            return .ignored
        }
        if !isFocused && !isFilterFocused && press.key != .escape { return .ignored }
        // The keyboard takes over from the pointer until it moves again, as in menus.
        hovered = nil
        switch press.key {
        case .downArrow: move(by: 1)
        case .upArrow: move(by: -1)
        case .leftArrow, .rightArrow: return step(press.key == .rightArrow ? 1 : -1)
        case .tab: jumpSection(by: press.modifiers.contains(.shift) ? -1 : 1)
        // ⇧Tab arrives as back-tab.
        case KeyEquivalent("\u{19}"): jumpSection(by: -1)
        case .return: activate(closing: true)
        case .space:
            if isFilterFocused { return .ignored }
            activate(closing: false)
        case .escape: escape()
        case .delete:
            guard !isFilterFocused, !query.isEmpty else { return .ignored }
            query.removeLast()
        default: return type(press)
        }
        return .handled
    }

    private func move(by offset: Int) {
        let targets = sections.flatMap { $0 }
        guard !targets.isEmpty else { return }
        guard let current = highlighted ?? firstMatch, let index = targets.firstIndex(of: current) else {
            highlighted = offset > 0 ? targets.first : targets.last
            return
        }
        highlighted = targets[min(max(index + offset, 0), targets.count - 1)]
    }

    private func jumpSection(by offset: Int) {
        let sections = sections
        guard !sections.isEmpty else { return }
        let index = highlighted.flatMap { target in sections.firstIndex { $0.contains(target) } }
        let next =
            index.map { ($0 + offset + sections.count) % sections.count } ?? (offset > 0 ? 0 : sections.count - 1)
        let section = sections[next]
        // A section lands on its current choice, as a group of radio buttons does.
        highlighted = section.first { isCurrent($0) } ?? section.first
    }

    /// ← and → change Effort's level, open a row's page or menu, and come back from a page.
    private func step(_ direction: Int) -> KeyPress.Result {
        guard !isStopped else { return .ignored }
        if highlighted == .effort, let effort = settings.effort {
            let levels = effort.choices
            if let index = levels.firstIndex(where: { $0.value == effort.value }),
                levels.indices.contains(index + direction)
            {
                onSet(effort, levels[index + direction].value)
            }
            return .handled
        }
        if direction < 0, page != nil {
            leavePage()
            return .handled
        }
        if direction > 0, case .row(let id) = highlighted, let row = rows.first(where: { $0.id == id }) {
            switch row.kind {
            case .menu, .page:
                open(row)
                return .handled
            case .toggle, .note:
                break
            }
        }
        return .ignored
    }

    private func escape() {
        if !query.isEmpty {
            query = ""
        } else if page != nil {
            leavePage()
        } else {
            onClose()
        }
    }

    private func type(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.command) {
            guard press.characters == "z", let onUndo else { return .ignored }
            onUndo()
            return .handled
        }
        guard press.modifiers.isDisjoint(with: [.control, .option]),
            let first = press.characters.unicodeScalars.first, CharacterSet.alphanumerics.contains(first)
        else { return .ignored }
        if isFilterFocused { return .ignored }
        let inModels: Bool =
            switch highlighted {
            case .model, nil: true
            default: false
            }
        // Past eight models, letters typed in the Model section go into its filter.
        if inModels, page == (DS.isTouchPlatform ? .model : nil), modelList?.isFilterable == true {
            query += press.characters
            return .handled
        }
        let prefix = typeAhead.append(press.characters)
        let section = highlighted.flatMap { target in sections.first { $0.contains(target) } } ?? sections.first ?? []
        if let match = section.first(where: { name(of: $0)?.lowercased().hasPrefix(prefix.lowercased()) == true }) {
            highlighted = match
        }
        return .handled
    }

    // MARK: - Choosing

    /// The filter's first match, which Return picks while nothing else is highlighted.
    var firstMatch: Target? {
        guard !query.isEmpty, let id = modelList?.rows.first?.id else { return nil }
        return .model(id)
    }

    private func activate(closing: Bool) {
        guard let target = highlighted ?? firstMatch else {
            if closing { onClose() }
            return
        }
        choose(target, closing: closing)
    }

    /// Chooses what `target` stands for; Return also closes the popover after a choice.
    func choose(_ target: Target, closing: Bool) {
        guard !isStopped || target == .restart else { return }
        switch target {
        case .model(let value):
            if DS.isTouchPlatform, page == nil {
                page = .model
                return
            }
            if let model = settings.model, value != model.value { onSet(model, value) }
        case .autonomy(let value):
            // Picking a level while Plan suspends it leaves Plan, as the agent does.
            if let autonomy = settings.autonomy, value != autonomy.value { onSet(autonomy, value) }
        case .effort:
            break
        case .fastMode:
            if let fastMode { onSet(fastMode, fastMode.isOn ? "off" : "on") }
            return
        case .retry:
            failure?.retry?()
            return
        case .restart:
            onRestart?()
            return
        case .back:
            leavePage()
            return
        case .command(let rowID, let index):
            guard let row = rows.first(where: { $0.id == rowID }),
                case .menu(_, let commands) = row.kind, commands.indices.contains(index)
            else { return }
            commands[index].action()
            return
        case .row(let id):
            let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
            guard let row = rows.first(where: { $0.id == parts.first }) else { return }
            if parts.count == 2 {
                row.perform(parts[1])
                leavePage()
            } else {
                open(row)
            }
            return
        }
        if closing { onClose() }
    }

    private func open(_ row: ComposerSettingsTaskRow) {
        switch row.kind {
        case .menu:
            hovered = nil
            highlighted = nil
            page = .choices(row.id)
            highlighted = pageTargets(row).first { isCurrent($0) } ?? pageTargets(row).first
        case .page:
            row.perform(nil)
        case .toggle(let isOn):
            row.perform(isOn ? "off" : "on")
        case .note:
            break
        }
    }

    private func leavePage() {
        let from = page
        page = nil
        hovered = nil
        if case .choices(let id) = from { highlighted = .row(id) }
    }

    private func isCurrent(_ target: Target) -> Bool {
        switch target {
        case .model(let value): value == settings.model?.value
        case .autonomy(let value): value == shownAutonomy
        case .effort: true
        case .fastMode: fastMode?.isOn == true
        case .retry, .restart, .back, .command: false
        case .row(let id):
            pageChoice(id)?.isCurrent ?? false
        }
    }

    private func name(of target: Target) -> String? {
        switch target {
        case .model(let value): modelList?.rows.first { $0.id == value }?.name
        case .autonomy(let value): settings.autonomyLevels.first { $0.value == value }?.askingTitle
        case .effort: "Effort"
        case .fastMode: fastMode?.option.name
        case .retry: "Try Again"
        case .restart: "Restart"
        case .back: "Task Settings"
        case .command(let rowID, let index):
            if let row = rows.first(where: { $0.id == rowID }), case .menu(_, let commands) = row.kind,
                commands.indices.contains(index)
            {
                commands[index].title
            } else {
                nil
            }
        case .row(let id): pageChoice(id)?.name ?? rows.first { $0.id == id }?.title
        }
    }

    private func pageChoice(_ id: String) -> ComposerSettingsTaskRow.Choice? {
        let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let row = rows.first(where: { $0.id == parts[0] }),
            case .menu(let choices, _) = row.kind
        else { return nil }
        return choices.first { $0.id == parts[1] }
    }
}
