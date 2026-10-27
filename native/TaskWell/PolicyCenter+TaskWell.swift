import NativeNetwork
import NativePolicy

/// The policies the well reflects, worded once for the title, the open well and Settings.
extension PolicyCenter {
    /// The policies that fix who runs a task and where: its agent, the agent's environment and
    /// the machines it may run on.
    static let taskWorkerKeys: Set<PolicyKey> = [.agentsAllowed, .agentsEnvironment, .remoteHostsEnabled]

    /// "Managed by Northwind Federal IT · #it-help", with the contact when the organization gave
    /// one, or the generic line when it gave no name. Native never infers a company name.
    var managementLine: String {
        guard let name = policy.organizationName else { return Self.managedExplanation }
        return ["Managed by \(name)", policy.organizationContact].compactMap { $0 }.joined(separator: " · ")
    }

    /// The network policy keeps GitHub out of reach: an air-gapped or internal-only install, or
    /// the GitHub service turned off.
    var isGitHubOutOfReach: Bool {
        (try? NetworkAdmission.checkService(service: .github, policy: policy.network)) == nil
    }

    /// The organization, not the user, set the network policy.
    var isNetworkManaged: Bool { isManaged(.network) || isManaged(.deploymentMode) }
}
