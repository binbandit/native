import ACP
import Foundation
import Testing

@testable import NativeOrchestration

@Suite struct TaskLaunchValidationTests {
    private func options(_ current: String, _ values: [String], category: String = "mode") throws -> [ConfigOption] {
        let wire: [String: Any] = [
            "id": category, "name": category, "category": category, "type": "select",
            "currentValue": current, "options": values.map { ["value": $0, "name": $0] },
        ]
        return [try JSONDecoder().decode(ConfigOption.self, from: JSONSerialization.data(withJSONObject: wire))]
    }

    @Test func inheritanceUsesKnownSemantics() throws {
        let parent = try options("acceptEdits", ["default", "acceptEdits"])
        let child = try options("bypassPermissions", ["default", "bypassPermissions"])
        #expect(try TaskLaunchValidation.permission(parent: parent, child: child, requested: nil).1 == "default")
        #expect(throws: TaskLaunchValidation.Refusal.self) {
            try TaskLaunchValidation.permission(parent: parent, child: child, requested: "full-access")
        }
    }

    @Test func explicitModesAreNeverSilentlyNarrowed() throws {
        let parent = try options("bypassPermissions", ["default", "bypassPermissions"])
        #expect(throws: TaskLaunchValidation.Refusal.self) {
            try TaskLaunchValidation.permission(
                parent: parent, child: options("default", ["default"]), requested: "auto")
        }
    }

    @Test func unknownAndIncomparableModesRefuse() throws {
        for source in ["unknown", "acceptEdits", "plan", "read-only"] {
            #expect(throws: TaskLaunchValidation.Refusal.self) {
                try TaskLaunchValidation.permission(
                    parent: options(source, [source]), child: options("workspace-write", ["workspace-write"]),
                    requested: nil)
            }
        }
    }

    @Test func exactModelAndAcknowledgmentAreRequired() throws {
        let offered = try options("alpha", ["alpha", "beta"], category: "model")
        #expect(try TaskLaunchValidation.exact("beta", category: "model", in: offered).id == "model")
        #expect(throws: TaskLaunchValidation.Refusal.self) {
            try TaskLaunchValidation.exact("invented", category: "model", in: offered)
        }
        #expect(throws: TaskLaunchValidation.Refusal.self) {
            try TaskLaunchValidation.verify("model", value: "beta", in: offered)
        }
    }
}
