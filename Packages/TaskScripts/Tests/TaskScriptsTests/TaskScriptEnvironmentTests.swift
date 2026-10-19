import Foundation
import Testing

@testable import TaskScripts

struct TaskScriptEnvironmentTests {
    @Test func tellsTheScriptAboutItsTask() {
        let context = TaskScriptContext(
            event: .turnFinished, projectPath: "/work/app", worktreePath: "/Users/me/.native/worktrees/app/fix-login",
            branch: "me/fix-login", baseBranch: "main", taskID: "sess_123", taskTitle: "Fix login", agent: "codex")
        #expect(
            context.environment == [
                "NATIVE_EVENT": "turn-finished",
                "NATIVE_PROJECT_PATH": "/work/app",
                "NATIVE_WORKTREE_PATH": "/Users/me/.native/worktrees/app/fix-login",
                "NATIVE_BRANCH": "me/fix-login",
                "NATIVE_BASE_BRANCH": "main",
                "NATIVE_TASK_ID": "sess_123",
                "NATIVE_TASK_TITLE": "Fix login",
                "NATIVE_AGENT": "codex",
            ])
    }

    /// Every variable is set, so `set -u` scripts don't fail on the ones Native doesn't know yet.
    @Test func setsUnknownValuesEmpty() {
        let context = TaskScriptContext(event: .taskDeleted, projectPath: "/work/app", worktreePath: "/work/app")
        let environment = context.environment
        #expect(environment["NATIVE_TASK_ID"] == "")
        #expect(environment["NATIVE_BRANCH"] == "")
        #expect(environment["NATIVE_BASE_BRANCH"] == "")
        #expect(environment["NATIVE_EVENT"] == "task-deleted")
        #expect(environment["NATIVE_WORKSPACE_PATH"] == nil)
    }

    @Test func setupKeepsTheNamesSetupScriptsHadBefore() {
        let context = TaskScriptContext(event: .setup, projectPath: "/work/app", worktreePath: "/wt/app/a1b2")
        #expect(context.environment["NATIVE_WORKSPACE_PATH"] == "/wt/app/a1b2")
        #expect(context.environment["NATIVE_ROOT_PATH"] == "/work/app")
    }

    @Test func runsWithTheUsersShellUnlessTheScriptNamesItsInterpreter() {
        let plain = TaskScript(event: .setup, source: .global, text: "bun install")
        let invocation = plain.invocation(shell: "/opt/homebrew/bin/fish")
        #expect(invocation.executable == "/opt/homebrew/bin/fish")
        #expect(invocation.arguments == ["-c", "bun install"])
        #expect(invocation.input == nil)
        #expect(plain.invocation(shell: nil).executable == "/bin/sh")
        #expect(plain.invocation(shell: "").executable == "/bin/sh")

        let committed = TaskScript(event: .setup, source: .repository, text: "#!/usr/bin/env bash -e\nset -u\n")
        let shebang = committed.invocation(shell: "/opt/homebrew/bin/fish")
        #expect(shebang.executable == "/bin/sh")
        #expect(Array(shebang.arguments.suffix(5)) == ["sh", "setup.sh", "/usr/bin/env", "bash", "-e"])
        #expect(shebang.input == Data(committed.text.utf8))
    }

    @Test func readsTheInterpreterLine() {
        #expect(TaskScript.interpreter(of: "#!/bin/zsh\necho") == ["/bin/zsh"])
        #expect(TaskScript.interpreter(of: "#! /usr/bin/env  python3 \r\nprint()") == ["/usr/bin/env", "python3"])
        #expect(TaskScript.interpreter(of: "#!\necho") == nil)
        #expect(TaskScript.interpreter(of: "echo #!/bin/sh") == nil)
    }

    @Test func commandsEndWhenTheScriptExits() {
        let command = TaskScript(event: .teardown, source: .project, text: "make stop")
            .command(in: "/wt", environment: ["SHELL": "/bin/zsh"], timeout: .seconds(60))
        #expect(command.directory == "/wt")
        #expect(command.timeout == .seconds(60))
        #expect(command.outputEndsAtExit)
    }
}
