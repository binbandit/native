import ACP
import NativeOrchestration

extension SessionModel {
    /// Uses the model's ordinary settings API so app-owned sessions obey the same admission rules.
    func prepareDelegation(_ options: TaskLaunchOptions, parent: SessionModel) async throws {
        for (category, value) in [("model", options.model), ("thought_level", options.effort)] {
            if let value {
                let option = try TaskLaunchValidation.exact(value, category: category, in: state.configOptions)
                await setConfigOption(option, to: value)
                try TaskLaunchValidation.verify(option.id, value: value, in: state.configOptions)
            }
        }
        let (mode, value) = try TaskLaunchValidation.permission(
            parent: parent.state.configOptions, child: state.configOptions, requested: options.permissions)
        await setConfigOption(mode, to: value)
        let (actualMode, boundedValue) = try TaskLaunchValidation.permission(
            parent: parent.state.configOptions, child: state.configOptions, requested: options.permissions)
        try TaskLaunchValidation.verify(actualMode.id, value: boundedValue, in: state.configOptions)
        for (category, value) in [("model", options.model), ("thought_level", options.effort)] {
            if let value {
                let option = try TaskLaunchValidation.exact(value, category: category, in: state.configOptions)
                try TaskLaunchValidation.verify(option.id, value: value, in: state.configOptions)
            }
        }
    }
}
