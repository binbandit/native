import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

@testable import Native
@testable import NativeLink

@MainActor
enum DiffCommentsHostChecks {
    static func run() async throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "diff-comment-host-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let host = WorkspaceTestHost()
        let client = NativeHostClient(transport: host, clientInfo: PeerInfo(name: "tests", version: "1", build: "1"))
        await client.start()
        _ = try await client.connected()
        let defaults = PreviewUserDefaults()
        let manifest = PluginManifest(
            id: "diff-comment-fixture", name: "Fixture",
            agents: [AgentManifest(id: "workspace-fake", name: "Fixture", command: "/usr/bin/true")])
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [ManifestPlugin(manifest: manifest)], defaults: defaults),
            defaults: defaults, catalogURL: scratch.appending(path: "catalog.json"),
            hosts: RemoteHosts(store: FilePairedHostStore(directory: scratch.appending(path: "hosts"))))
        app.connectHost(client: client)
        await app.followHost()
        _ = await app.checkForAgents()
        let project = app.projects.add(scratch)
        guard let runtime = await app.ensureRunning(AgentDefinition.ID(rawValue: "workspace-fake")) else {
            throw Failure()
        }
        let session = try await app.launcher.start(on: runtime, cwd: scratch, project: project.id)
        for edited in [false, true] {
            let quotes = DiffCommentsPreviewFixtures.quotes(task: session.clientID)
            session.draft = PromptQuote.draft(quotes: quotes, message: "Please review.\n")
            app.sessions.services.sendGate.setWorkspaceHold("fixture setup", for: scratch)
            await session.submitDiffComments(.queue)
            precondition(session.heldPrompts.count == 1 && !session.draft.isEmpty, "Held packet keeps its draft")
            if edited {
                let id = session.heldPrompts[0].id
                session.editingQueuedPrompt = id
                var changed = quotes
                changed[0].comment?.body = "Edited while waiting."
                session.draft = PromptQuote.draft(quotes: changed, message: "Updated review.\n")
                let saved = await session.saveQueuedDiffComments(id)
                precondition(saved && !session.draft.isEmpty, "Held edit keeps its recovery copy")
                precondition(session.heldPrompts[0].text == PromptQuote.trimmed(session.draft))
            }
            let retained = session.draft
            session.reconcileDiffCommentDelivery()
            precondition(session.unresolvedCommentPacket != nil, "A held list is not durable receipt evidence")
            app.sessions.services.drafts.save()
            let afterQuit = ComposerDrafts(defaults: defaults)
            precondition(afterQuit.draft(for: session.key) == retained, "Held words survive quitting")
            precondition(afterQuit.commentDelivery(for: session.key) != nil, "Held recovery survives quitting")
            await host.configure(failPrompt: true)
            app.sessions.services.sendGate.setWorkspaceHold(nil, for: scratch)
            session.sendHeldPrompts()
            try await wait { session.diffCommentStatus?.hasPrefix("Couldn’t send") == true }
            precondition(
                session.draft == retained && session.unresolvedCommentPacket == nil, "Hold failure keeps words")
            await host.configure()
            await session.submitDiffComments(.queue)
            precondition(session.draft.isEmpty && session.unresolvedCommentPacket == nil, "Host acceptance clears once")
        }
        for hasText in [false, true] {
            let original = try await app.launcher.start(on: runtime, cwd: scratch, project: project.id)
            app.catalog.add(
                SessionInfo(sessionId: original.id, cwd: scratch.folderPath, updatedAt: .now),
                for: original.agent.id, in: project.id)
            app.unsentSessions.started(original.key)
            let editor = DiffCommentsPreviewFixtures.quotes(task: original.clientID)[0]
            original.beginDiffComment(editor)
            original.draft = hasText ? "Keep this note" : ""
            if hasText { original.unresolvedCommentPacket = editor.prompt }
            app.keepDrafts()
            app.sessions.remove(original)
            app.dropUnsentSessions()
            precondition(app.catalog.contains(original.key), "Editor-only tasks survive relaunch cleanup")
            let reopened = await app.reopenUnsent(
                original.key, info: SessionInfo(sessionId: original.id, cwd: scratch.folderPath), on: runtime)
            precondition(reopened, "Persisted comment task reopens")
            guard
                let replacement = app.sessions.open(of: original.agent.id).first(where: {
                    $0.key != original.key && $0.diffCommentEditors == [editor]
                })
            else { throw Failure() }
            precondition(replacement.draft == original.draft, "Text and unfinished comments move to the fresh key")
            precondition(replacement.unresolvedCommentPacket == original.unresolvedCommentPacket, "Delivery lock moves")
            precondition(
                app.sessions.services.drafts.commentEditors(for: original.key).isEmpty,
                "Obsolete persisted editors are cleared only after migration")
            app.sessions.remove(replacement)
        }
        let queued = try await app.launcher.start(on: runtime, cwd: scratch, project: project.id)
        let original = DiffCommentsPreviewFixtures.quotes(task: queued.clientID)
        let item = NativeHostProtocol.QueuedPrompt(text: PromptQuote.draft(quotes: original, message: "Before"))
        queued.hostSummary?.queue = [item]
        queued.editingQueuedPrompt = item.id
        queued.draft = PromptQuote.draft(quotes: original, message: "Edited after the stale queue snapshot")
        let retained = queued.draft
        let acknowledged = await queued.saveQueuedDiffComments(item.id)
        precondition(!acknowledged && queued.draft == retained, "An empty legacy response is not storage evidence")
        precondition(queued.unresolvedCommentPacket != nil, "An unconfirmed queue edit remains recoverable")
    }

    private static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw Failure()
    }

    private struct Failure: Error {}
}
