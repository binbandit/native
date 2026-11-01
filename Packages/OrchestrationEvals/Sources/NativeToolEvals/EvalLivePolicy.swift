import Foundation
import NativeNetwork
import NativePolicy

public enum EvalLivePolicy {
    public static func check(_ policy: NativePolicy) throws {
        // A CLI's remote transport cannot be origin-enforced here. Restricted deployments stay offline.
        guard policy.network.mode == .ordinary, policy.agents.allows("claude-code"),
            policy.mcp.allows(name: "native-eval"), policy.decision(for: .agentExecution).isPermitted
        else { throw PolicyError.denied }
        try NetworkAdmission.checkService(service: .agentProvider, policy: policy.network)
        try NetworkAdmission.checkService(service: .mcpStdio, policy: policy.network)
    }

    public static func checkInstalledPolicy() throws {
        guard let defaults = UserDefaults(suiteName: "dev.binbandit.native") else { throw PolicyError.denied }
        try check(PolicyLoader.load(from: UserDefaultsPolicySource(defaults: defaults)))
    }

    private enum PolicyError: LocalizedError {
        case denied
        var errorDescription: String? { "Live tool eval denied by Native policy. Offline grading remains available." }
    }
}
