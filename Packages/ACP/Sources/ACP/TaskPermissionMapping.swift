import Foundation

/// A plugin declares exact provider equivalents. Missing levels fall back only to a stricter one.
public struct TaskPermissionMapping: Hashable, Sendable {
    public var values: [TaskPermissionMode: [String]]
    public var notes: [String: String]

    public init(values: [TaskPermissionMode: [String]], notes: [String: String] = [:]) {
        self.values = values
        self.notes = notes
    }

    /// ACP vocabulary understood without assuming the meaning of an unfamiliar mode or its order.
    public static let standard = Self(values: [
        .askFirst: ["ask-first", "default", "ask", "manual", "read-only"],
        .acceptEdits: ["accept-edits", "acceptEdits"],
        .auto: ["auto"],
        .fullAccess: ["bypassPermissions", "agent-full-access", "full-access"],
    ])

    public struct Selection: Equatable, Sendable {
        public var value: String
        public var effective: TaskPermissionMode
        public var isExact: Bool
    }

    public func selection(_ mode: TaskPermissionMode, offered: [String], forbidden: Set<String> = []) -> Selection? {
        guard !forbidden.contains(mode.rawValue) else { return nil }
        for candidate in TaskPermissionMode.allCases.reversed() where candidate.rank <= mode.rank {
            guard !forbidden.contains(candidate.rawValue),
                let value = values[candidate]?.first(where: { value in
                    offered.contains(value) && !forbidden.contains(value)
                        && !forbidden.contains { blocked in
                            guard let wireMode = TaskPermissionMode.migrating(value) else { return false }
                            return TaskPermissionMode.migrating(blocked) == wireMode
                        }
                })
            else { continue }
            return Selection(value: value, effective: candidate, isExact: candidate == mode)
        }
        return nil
    }

    public func mode(for value: String) -> TaskPermissionMode? {
        TaskPermissionMode.allCases.first { values[$0]?.contains(value) == true }
    }

    /// The requested mode is retained when two Native modes use the same provider control.
    public func presenting(
        _ option: ConfigOption, remembered: String? = nil, forbidden: Set<String> = []
    ) -> ConfigOption {
        guard option.category == "mode", case .select(let current, let offered) = option.kind else { return option }
        if Set(TaskPermissionMode.allCases.map(\.rawValue)).isSubset(of: Set(offered.map(\.value))) { return option }
        let wire = offered.map(\.value)
        let retained = remembered.flatMap(TaskPermissionMode.init(rawValue:)).flatMap { mode in
            selection(mode, offered: wire, forbidden: forbidden)?.value == current ? mode : nil
        }
        var shown = option
        let mode = retained ?? mode(for: current) ?? TaskPermissionMode.migrating(current) ?? .askFirst
        let choices = TaskPermissionMode.allCases.map { mode in
            let selected = selection(mode, offered: wire, forbidden: forbidden)
            let note =
                selected.map {
                    $0.isExact ? nil : "Uses \($0.effective.title) with this agent."
                } ?? "This agent does not offer a safe equivalent."
            return ConfigOption.SelectOption(
                value: mode.rawValue, name: mode.title,
                description: [mode.summary, note, selected.flatMap { notes[$0.value] }].compactMap { $0 }.joined(
                    separator: " "))
        }
        // Task modes can apply a plan or read-only restriction independently of permissions.
        let restrictions = offered.filter { $0.value == "plan" || $0.value == "read-only" }
        shown.permissionMappings = Dictionary(
            uniqueKeysWithValues: TaskPermissionMode.allCases.compactMap { mode in
                selection(mode, offered: wire, forbidden: forbidden).map { (mode.rawValue, $0.value) }
            })
        shown.name = "Permissions"
        shown.kind = .select(
            currentValue: current == "plan" || (current == "read-only" && retained == nil) ? current : mode.rawValue,
            options: choices + restrictions)
        return shown
    }
}
