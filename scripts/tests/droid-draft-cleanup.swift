import Foundation

@testable import Native

@MainActor
enum DraftCleanupRegression {
    static func discardDuringPreparation(
        app: AppModel, project: Project, folder: String, host: RemoteHost,
        provider: RecordingWorkspaces, others: [RecordingWorkspaces]
    ) async throws {
        guard let agent = host.runtimes.first?.agent else { throw RoutingFailure("Missing remote draft agent") }
        let task = StartingTask(project: project.id, agent: agent, isAgentPicked: false, workspaceLabel: "Fixture")
        task.device = .remote(host.id)
        app.startingTasks.append(task)
        provider.holdPreparation = true
        defer { provider.holdPreparation = false }
        let starting = Task { await app.start(task) }
        let deadline = ContinuousClock.now + .seconds(15)
        while provider.pendingPreparation == nil {
            guard ContinuousClock.now < deadline else { throw RoutingFailure("Draft did not prepare its workspace") }
            try await Task.sleep(for: .milliseconds(10))
        }
        app.discard(task)
        provider.pendingPreparation?.resume(returning: URL(filePath: folder))
        provider.pendingPreparation = nil
        await starting.value
        while provider.calls.isEmpty {
            guard ContinuousClock.now < deadline else { throw RoutingFailure("Discard leaked the pending workspace") }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard provider.calls == [.init(operation: "delete", folder: folder, project: project.path)],
            others.allSatisfy({ $0.calls.isEmpty }), task.folder == nil
        else { throw RoutingFailure("Pending draft cleanup lost its owner") }
        provider.calls = []
        print("PASS: discarding during remote workspace preparation cleans up on its owner")
    }

    static func retryDiscard(
        app: AppModel, project: Project, folder: String, provider: RecordingWorkspaces,
        others: [RecordingWorkspaces], device: SessionDevice = .thisMac
    ) async throws {
        guard let agent = app.plugins.agents.first else { throw RoutingFailure("Missing draft agent") }
        let task = StartingTask(project: project.id, agent: agent, isAgentPicked: false, workspaceLabel: "Fixture")
        task.device = device
        task.folder = URL(filePath: folder)
        task.ownsWorkspace = true
        task.failure = StartingTask.Failure(title: "Fixture", message: "Agent failed to start")
        app.startingTasks.append(task)
        let checkout = app.projects.project(project.id)?.checkoutPath(on: device)
        let work = ProjectProblem.Work.workspaceDeletion(task.id, folder: URL(filePath: folder))
        provider.failsDeletion = true
        defer { provider.failsDeletion = false }
        app.discard(task)
        let deadline = ContinuousClock.now + .seconds(15)
        while !app.problems.all.contains(where: { $0.work == work }) {
            guard ContinuousClock.now < deadline else { throw RoutingFailure("Discard failed to report cleanup") }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let problem = app.problems.all.first(where: { $0.work == work }) else {
            throw RoutingFailure("Missing discarded draft problem")
        }
        guard task.folder == nil, app.startingTask(task.id) == nil, app.catalog.lookup(task.id) == nil else {
            throw RoutingFailure("Discard retained the starting task")
        }
        if case .remote(let id) = device, let host = app.hosts.host(id) {
            host.taskWorkspaces = nil
            await app.retry(problem)
            host.taskWorkspaces = provider
            guard app.problems.all.contains(where: { $0.id == problem.id }), provider.calls.count == 1,
                others.allSatisfy({ $0.calls.isEmpty })
            else { throw RoutingFailure("Unavailable draft provider fell through or lost recovery") }
        }
        provider.failsDeletion = false
        await app.retry(problem)
        guard !app.problems.all.contains(where: { $0.id == problem.id }) else {
            throw RoutingFailure(
                "Discarded draft cleanup retry failed: \(app.problems.all.first?.details ?? "unknown")")
        }
        guard provider.calls.map(\.operation) == ["delete", "delete"],
            provider.calls.allSatisfy({ $0.folder == folder && $0.project == checkout }),
            others.allSatisfy({ $0.calls.isEmpty })
        else { throw RoutingFailure("Draft cleanup or retry reached the wrong provider or deletion hook") }
        provider.calls = []
        print("PASS: discarded draft retries on its explicit device with remote hosts \(app.offersRemoteHosts)")
    }
}
