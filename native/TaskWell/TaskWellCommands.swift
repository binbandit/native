import NativeCommands

extension CommandID {
    static let taskWellToggle: Self = "taskWell.toggle"
}

extension NativeCommand {
    static let taskWell: [NativeCommand] =
        [
            NativeCommand(.taskWellToggle, title: "Show or Hide Task Tools", category: .view) {
                $0.sessionTools?.toggleWell()
            }
            .available { $0.sessionTools?.hasWell == true }
        ]
        + TaskWellTool.allCases.filter { $0 != .changes }.map { tool in
            NativeCommand(tool.command, title: "Show \(tool.title)", category: .view, systemImage: tool.symbol) {
                $0.sessionTools?.performWellTool(tool)
            }
            .available { $0.sessionTools?.wellToolAvailable(tool) == true }
        }
}
