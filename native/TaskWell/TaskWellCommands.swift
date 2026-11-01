import NativeCommands

extension CommandID {
    static let taskWellToggle: Self = "taskWell.toggle"
    static let taskWellExportPatch: Self = "taskWell.exportPatch"
}

extension NativeCommand {
    static let taskWell: [NativeCommand] =
        [
            NativeCommand(.taskWellToggle, title: "Show or Hide Task Tools", category: .view) {
                $0.sessionTools?.toggleWell()
            }
            .available { $0.sessionTools?.hasWell == true },
            // Listed only where the well offers it in place of the pull request.
            NativeCommand(
                .taskWellExportPatch, title: "Export Patch…", category: .tasks, systemImage: "square.and.arrow.up",
                keywords: ["git am", "format-patch", "offline", "air-gapped"]
            ) {
                $0.sessionTools?.wellExportPatch?()
            }
            .available { $0.sessionTools?.wellExportPatch != nil },
        ]
        + TaskWellTool.builtIns.filter { $0 != .changes }.map { taskWellTool($0) }

    /// Shows a tool from the well's list, and does nothing while the tool is off or not there, as
    /// its row isn't. Changes keeps its own show-or-hide command (`sessionTools`).
    static func taskWellTool(_ tool: TaskWellTool) -> NativeCommand {
        NativeCommand(tool.command, title: "Show \(tool.title)", category: .view, systemImage: tool.symbol) {
            $0.sessionTools?.performWellTool(tool)
        }
        .available {
            $0.sessionTools?.wellToolAvailable(tool) == true && $0.sessionTools?.wellToolEnabled(tool) == true
        }
    }
}
