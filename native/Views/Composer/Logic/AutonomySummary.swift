import ACP

/// Canonical mode descriptions include any provider fallback in the same quiet line.
enum AutonomySummary {
    static func summary(of choice: SelectSetting.Choice) -> String? {
        choice.description ?? TaskPermissionMode.migrating(choice.value)?.summary
    }
}
