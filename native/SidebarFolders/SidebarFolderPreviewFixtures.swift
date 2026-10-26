#if DEBUG
import ACP
import Experiments
import NativePolicy
import SwiftUI

/// Inert screenshot states. They use the shipping sidebar controls and model, never an agent or git.
enum SidebarFolderPreviewFixtures {
    static var requested: String? {
        guard Bundle.main.bundleIdentifier?.hasPrefix("dev.binbandit.native.dev.") == true else { return nil }
        return UserDefaults.standard.string(forKey: "sidebarFolderFixture")
    }

    static func model(_ state: String) -> AppModel {
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [BuiltInPlugins.claudeCode]), defaults: PreviewUserDefaults(),
            catalogURL: nil,
            experiments: ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage()))
        _ = app.runtimes.sync()
        app.experiments.set(true, for: .sidebarNext)
        app.sidebarFolders.policyOverride = .default
        if state != "F5" {
            let native = app.projects.add(URL(filePath: "/Development/native"))
            let pier = app.projects.add(URL(filePath: "/Development/pier"))
            for (index, title) in [
                "Keep edited messages in place", "Wrap diff lines at word boundaries", "Show context use in the well",
                "Keep exports in column order",
            ].enumerated() {
                let project = index == 3 ? pier : native
                let id = SessionID("folder-fixture-\(index)")
                app.catalog.add(
                    SessionInfo(sessionId: id, cwd: project.path, title: title, updatedAt: .now),
                    for: AgentDefinition.ID(rawValue: "claude-code"),
                    in: project.id)
            }
            app.selection = SessionKey(
                agent: AgentDefinition.ID(rawValue: "claude-code"), id: SessionID("folder-fixture-0"))
        }
        if state == "F2" {
            for name in ["native", "pier", "atlas"] {
                app.sidebarFolders.remember(URL(filePath: "/Development/\(name)"))
            }
        }
        if state == "F3" {
            app.sidebarFolders.hovered = ["atlas"]
            app.sidebarFolders.acceptsDrop = true
        }
        if state == "F4" {
            let project = app.projects.add(URL(filePath: "/Development/atlas"))
            app.focusProject(project.id)
            app.sidebarFolders.receipt = .init(projects: [project], previousProject: nil, previousSelection: nil)
        }
        if state == "F6" {
            app.sidebarFolders.failures = [.init(name: "Can’t open atlas", reason: "Folder access expired.")]
        }
        if state == "F7" {
            app.sidebarFolders.policyOverride = PolicyLoader.load(
                from: StaticPolicySource(managed: [
                    "policy.folders.allowedRoots": ["/Development"], "policy.organization.name": "Northwind Federal IT",
                    "policy.organization.contact": "Contact your IT service desk to request another approved folder.",
                ]))
        }
        if state == "blocked" {
            app.sidebarFolders.policyOverride = PolicyLoader.load(
                from: StaticPolicySource(managed: [
                    "policy.folders.allowedRoots": [String](), "policy.organization.name": "Northwind Federal IT",
                ]))
        }
        if state == "F10" { app.sidebarFolders.opening = ["atlas"] }
        return app
    }
}
#endif
