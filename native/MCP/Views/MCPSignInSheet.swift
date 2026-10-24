import MCPClient
import SwiftUI

struct MCPSignInSheet: View {
    let library: MCPLibrary
    let command: AgentCLICommand
    var task: SessionModel?

    @Environment(\.dismiss) private var dismiss
    @State private var flow = MCPLoginFlow()
    @State private var redirect = ""
    @State private var problem: String?
    @State private var starting: Task<Void, Never>?
    @State private var isPreparing = false

    var body: some View {
        MCPSignInContent(
            serverName: command.serverName, phase: isPreparing ? .starting : flow.phase,
            hasLink: flow.authorization != nil,
            problem: problem ?? flow.inputProblem, redirect: $redirect,
            start: start, openBrowser: openBrowser,
            submit: { if flow.submitCallback(redirect) { redirect = "" } },
            close: {
                flow.cancel(); dismiss()
            }
        )
        .onChange(of: flow.authorization) { _, link in
            if link != nil { openBrowser() }
        }
        .onDisappear {
            starting?.cancel()
            flow.cancel()
            redirect = ""
        }
    }

    private func start() {
        guard !isPreparing else { return }
        isPreparing = true
        problem = nil
        starting = Task {
            defer { isPreparing = false }
            problem = await library.startSignIn(command, flow: flow, task: task)
        }
    }

    private func openBrowser() {
        guard let link = flow.authorization else { return }
        PlatformURLOpener.open(link.url)
    }
}

private struct MCPSignInContent: View {
    let serverName: String
    let phase: MCPLoginFlow.Phase
    let hasLink: Bool
    let problem: String?
    @Binding var redirect: String
    let start: () -> Void
    let openBrowser: () -> Void
    let submit: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            Text("Sign in to \(serverName)")
                .settingsText(.title)
                .foregroundStyle(.dsTextPrimary)
            Text(guidance)
                .settingsText(.body)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if phase == .starting {
                HStack(spacing: DS.Space.md) {
                    DotGridLoader(pattern: .settingUp)
                    Text("Getting the sign-in link…").settingsText(.body)
                }
            }
            if phase == .waiting {
                Button("Open Browser", action: openBrowser)
                    .buttonStyle(.ds(.secondary, size: .medium))
                    .disabled(!hasLink)
                Text(
                    "If the browser can't connect to the redirect page, copy its full address and paste it here. This also finishes sign-in on a paired host."
                )
                .settingsText(.body)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                TextField("Redirect URL", text: $redirect)
                    .settingsField()
                    .autocorrectionDisabled()
                    .onSubmit(submit)
            }
            if let problem {
                Text(problem).settingsText(.body).foregroundStyle(.dsDanger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: DS.Space.md) {
                Spacer()
                if phase == .succeeded {
                    Button("Done", action: close)
                        .buttonStyle(.ds(.primary, size: .large))
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel", action: close)
                        .buttonStyle(.ds(.secondary, size: .large))
                        .keyboardShortcut(.cancelAction)
                    Button(phase == .waiting ? "Continue" : "Sign In", action: phase == .waiting ? submit : start)
                        .buttonStyle(.ds(.primary, size: .large))
                        .keyboardShortcut(.defaultAction)
                        .disabled(phase == .starting || (phase == .waiting && redirect.isEmpty))
                }
            }
        }
        .padding(DS.Space.xxl)
        .frame(idealWidth: DS.MCP.signInWidth, maxWidth: DS.MCP.signInWidth)
        .background(.dsBackground)
    }

    private var guidance: String {
        switch phase {
        case .succeeded: "Signed in. New tasks on this host can use this server."
        case .waiting:
            "Finish signing in in your browser. The agent keeps your credentials on the host running the task."
        case .failed(let message): message
        case .cancelled: "Sign-in was cancelled. You can try again."
        default:
            "Native opens the sign-in page on this device. Your agent completes sign-in and keeps the credentials on its host."
        }
    }
}

#if DEBUG
#Preview("MCP sign-in - All states") {
    DSPreviewPair {
        VStack {
            ForEach(
                Array(
                    [
                        MCPLoginFlow.Phase.ready, .starting, .waiting,
                        .failed("The host disconnected. Try again when it's back."), .cancelled, .succeeded,
                    ].enumerated()), id: \.offset
            ) { _, phase in
                MCPSignInContent(
                    serverName: "Team documentation and engineering handbooks", phase: phase,
                    hasLink: phase == .waiting,
                    problem: phase == .waiting ? "Paste the full redirect address for this sign-in." : nil,
                    redirect: .constant(""), start: {}, openBrowser: {}, submit: {}, close: {})
            }
        }
    }
}
#endif
