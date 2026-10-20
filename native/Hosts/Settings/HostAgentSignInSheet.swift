#if NATIVE_HOSTSUI_WIP
import ACP
import NativeHostProtocol
import SwiftUI

/// Signs an agent in on a paired host. The agent runs there, so its sign-in happens there, and a
/// method that opens a browser opens it on the host's screen, where nobody may be looking. So the
/// sheet leads with what works from this Mac (a key, or a page and code to open anywhere), then
/// gives the exact steps to sign in over SSH, and offers the browser method last, for a host whose
/// screen the user can see. It closes by itself once the agent is signed in; its row says so.
struct HostAgentSignInSheet: View {
    let directory: any HostsDirectory
    let device: SessionDevice
    let agentID: AgentDefinition.ID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// Keys being typed, by method. Cleared the moment one is sent; never logged or kept.
    @State private var keys: [String: String] = [:]
    /// The method being tried, so its button shows progress and the others wait.
    @State private var running: String?
    @State private var failure: Failure?
    @State private var isChecking = false
    /// Set while the user stops a link sign-in, so its ending isn't shown as a failure.
    @State private var isCancelling = false

    /// What went wrong, and what trying again does.
    private struct Failure {
        let message: String
        let retry: (() -> Void)?
    }

    private var host: HostDisplay? {
        directory.hosts.first { $0.device == device }
    }

    private var agent: HostAgentDisplay? {
        host?.agents.first { $0.id == agentID }
    }

    var body: some View {
        Group {
            if let host, let agent {
                content(host, agent)
            } else {
                EmptyStateView(
                    "This agent isn't on that host anymore", systemImage: "questionmark.circle",
                    message: "The host was removed, or it no longer runs the agent.", actionTitle: "Close"
                ) { dismiss() }
                .frame(height: HostsMetrics.signInSheetMaxHeight / 2)
            }
        }
        .frame(width: HostsMetrics.signInSheetWidth)
        .background(.dsBackground)
        .onChange(of: agent?.wantsSignIn) { _, wantsSignIn in
            if wantsSignIn == false { dismiss() }
        }
    }

    private func content(_ host: HostDisplay, _ agent: HostAgentDisplay) -> some View {
        // A link first: it needs nothing but a browser anywhere. Then keys.
        let fromHere =
            agent.methods.filter { $0.kind == .link }
            + agent.methods.filter(\.worksFromHere).filter {
                $0.kind != .link
            }
        let browser = agent.methods.filter { $0.kind == .browser }
        return VStack(alignment: .leading, spacing: 0) {
            header(host, agent, hasMethodsFromHere: !fromHere.isEmpty)
            SeparatorLine()
            CappedHeightScrollView(maxHeight: HostsMetrics.signInSheetMaxHeight) {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    if let failure {
                        ErrorState(
                            "Couldn't sign in to \(agent.agent.displayName)", suggestion: failure.message,
                            primary: failure.retry.map { ErrorState.Action("Try Again", perform: $0) })
                    }
                    if let link = agent.signInLink {
                        linkWaiting(link, agent: agent)
                        SeparatorLine()
                    }
                    ForEach(fromHere) { method in
                        option(method, agent: agent, host: host)
                        SeparatorLine()
                    }
                    sshSteps(host, agent)
                    ForEach(browser) { method in
                        SeparatorLine()
                        browserOption(method, host: host)
                    }
                }
                .padding(DS.Space.xl)
            }
            SeparatorLine()
            footer(agent)
        }
    }

    private func header(_ host: HostDisplay, _ agent: HostAgentDisplay, hasMethodsFromHere: Bool) -> some View {
        let name = agent.agent.displayName
        let why =
            if hasMethodsFromHere {
                "\(name) runs on \(host.name), so it signs in there. Use a key or a link from this Mac, or sign in over SSH."
            } else if agent.methods.contains(where: { $0.kind == .browser }) {
                "\(name) signs in by opening a browser on the machine it runs on, and that's \(host.name), where nobody may be looking. Sign in over SSH from this Mac instead."
            } else {
                "\(name) signs in from a terminal on the machine it runs on. Open one on \(host.name) over SSH from this Mac."
            }
        return HStack(alignment: .top, spacing: DS.Space.lg) {
            AgentIcon(agent: agent.agent, size: DS.Size.controlXS)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Sign In to \(name) on \(host.name)")
                    .font(.dsTitle3)
                    .foregroundStyle(.dsTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(why)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Space.xl)
    }

    // MARK: - From this Mac

    @ViewBuilder
    private func option(_ method: HostSignInMethod, agent: HostAgentDisplay, host: HostDisplay) -> some View {
        switch method.kind {
        case .apiKey(let label):
            keyOption(method, label: label ?? "key", agent: agent, host: host)
        case .link:
            optionText(
                title: method.method.name,
                detail: [
                    "\(agent.agent.displayName) shows a page and a code. Open the page in any browser, on this Mac or your phone.",
                    agent.usesAPIKey ? "This replaces the API key \(agent.agent.displayName) uses now." : nil,
                ].compactMap(\.self).joined(separator: " ")
            ) {
                Button(running == method.id ? "Waiting for the Page…" : "Get a Link") { run(method, key: nil) }
                    .buttonStyle(.ds(.primary, size: .medium))
                    .disabled(running != nil || agent.signInLink != nil)
            }
        case .browser, .terminal:
            EmptyView()
        }
    }

    private func keyOption(
        _ method: HostSignInMethod, label: String, agent: HostAgentDisplay, host: HostDisplay
    )
        -> some View
    {
        let isSaved = agent.savedKeys.contains(method.id)
        return optionText(
            title: method.method.name,
            detail: isSaved
                ? "\(host.name) keeps your \(label) in its keychain for \(agent.agent.displayName) alone."
                : "Native sends it to \(host.name) over the encrypted link. \(host.name) keeps it in its keychain for \(agent.agent.displayName) alone and never sends it back."
        ) {
            if isSaved {
                HStack(spacing: DS.Space.md) {
                    Label(
                        "\(label.prefix(1).uppercased() + label.dropFirst()) saved on \(host.name)", systemImage: "key"
                    )
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    Spacer(minLength: DS.Space.md)
                    Button(running == method.id ? "Removing…" : "Remove") { removeKey(method) }
                        .buttonStyle(.ds(.secondary, size: .medium))
                        .disabled(running != nil)
                }
            } else {
                HStack(spacing: DS.Space.md) {
                    SecureField("Paste your \(label)", text: key(for: method))
                        .textFieldStyle(.plain)
                        .font(.dsMono)
                        .settingsField()
                        .onSubmit { run(method, key: keys[method.id]) }
                    Button(running == method.id ? "Signing In…" : "Sign In") { run(method, key: keys[method.id]) }
                        .buttonStyle(.ds(.primary, size: .medium))
                        .disabled(keys[method.id, default: ""].isEmpty || running != nil)
                }
                if let page = method.method.credentialsPage {
                    Button("Get a Key") { openURL(page) }
                        .buttonStyle(.ds(.ghost))
                        .help(page.absoluteString)
                }
            }
        }
    }

    /// A link sign-in waiting on the user: the agent's own words, the code to copy, the page to open.
    private func linkWaiting(_ link: HostSignInLink, agent: HostAgentDisplay) -> some View {
        optionText(title: "Finish signing in", detail: link.message) {
            HostSignInLinkView(link: link) {
                openURL(link.url)
            } cancel: {
                isCancelling = true
                Task { await directory.cancelSignIn(agentID, on: device) }
            }
        }
    }

    // MARK: - Over SSH

    private func sshSteps(_ host: HostDisplay, _ agent: HostAgentDisplay) -> some View {
        let name = agent.agent.displayName
        return optionText(
            title: "Sign in over SSH",
            detail: "Open Terminal on this Mac and run these. Links \(name) prints open fine here."
        ) {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                step(1, "Connect to \(host.name):") {
                    if let destination = host.sshDestination {
                        AgentSetupCommand(command: "ssh \(destination)")
                    } else {
                        Text("ssh with your user name and \(host.name)'s address, as you'd reach it from here.")
                            .font(.dsBody)
                            .foregroundStyle(.dsTextSecondary)
                    }
                }
                step(2, "Sign in to \(name) there:") {
                    if let command = agent.terminalSignIn {
                        AgentSetupCommand(command: command)
                    } else {
                        HStack(spacing: DS.Space.md) {
                            Text("Use \(name)'s own terminal sign-in.")
                                .font(.dsBody)
                                .foregroundStyle(.dsTextSecondary)
                            if let docs = agent.docs {
                                Button("Open \(name)'s Docs") { openURL(docs) }
                                    .buttonStyle(.ds(.secondary))
                            }
                        }
                    }
                }
                step(3, "Come back and choose Check Again.") { EmptyView() }
            }
        }
    }

    private func step<Content: View>(_ number: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            Text("\(number)")
                .font(.dsMonoCaption)
                .foregroundStyle(.dsTextTertiary)
                .frame(width: DS.Size.rowLeading, alignment: .leading)
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text(title)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextPrimary)
                content()
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - On the host's screen

    private func browserOption(_ method: HostSignInMethod, host: HostDisplay) -> some View {
        optionText(
            title: "On \(host.name)'s screen",
            detail:
                "“\(method.method.name)” opens a browser on \(host.name). Use it if you can see that screen, with Screen Sharing for example."
        ) {
            Button(running == method.id ? "Waiting for \(host.name)…" : "Sign In on \(host.name)") {
                run(method, key: nil)
            }
            .buttonStyle(.ds(.secondary, size: .medium))
            .disabled(running != nil)
        }
    }

    // MARK: - Parts

    private func optionText<Controls: View>(
        title: String, detail: String, @ViewBuilder controls: () -> Controls
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .font(.dsCalloutMedium)
                    .foregroundStyle(.dsTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            controls()
        }
    }

    private func footer(_ agent: HostAgentDisplay) -> some View {
        HStack(spacing: DS.Space.md) {
            if isChecking {
                DotGridLoader(pattern: .waiting)
                    .frame(width: HostsMetrics.loader, height: HostsMetrics.loader)
                Text("Checking…")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextTertiary)
            }
            Spacer(minLength: DS.Space.lg)
            Button("Cancel") { cancel() }
                .buttonStyle(.ds(.secondary))
                .keyboardShortcut(.cancelAction)
            Button("Check Again") { checkAgain() }
                .buttonStyle(.ds(.primary))
                .disabled(isChecking)
                .help("Signed in over SSH? Native restarts \(agent.agent.displayName) there and asks again.")
        }
        .padding(DS.Space.lg)
    }

    // MARK: - Actions

    private func key(for method: HostSignInMethod) -> Binding<String> {
        Binding(get: { keys[method.id, default: ""] }, set: { keys[method.id] = $0 })
    }

    private func run(_ method: HostSignInMethod, key: String?) {
        guard running == nil else { return }
        if let key, key.isEmpty { return }
        // The key leaves the field as it's sent; a refused one is typed again, never kept here.
        keys[method.id] = nil
        running = method.id
        failure = nil
        Task {
            defer { running = nil }
            do {
                try await directory.signIn(agentID, on: device, with: method.method, apiKey: key)
            } catch {
                guard !isCancelling else {
                    isCancelling = false
                    return
                }
                // A key isn't kept for a retry, so a refused one is pasted again.
                failure = Failure(
                    message: error.localizedDescription, retry: key == nil ? { run(method, key: nil) } : nil)
            }
        }
    }

    private func removeKey(_ method: HostSignInMethod) {
        running = method.id
        failure = nil
        Task {
            defer { running = nil }
            do {
                try await directory.removeAPIKey(agentID, on: device, for: method.method)
            } catch {
                failure = Failure(message: error.localizedDescription) { removeKey(method) }
            }
        }
    }

    private func checkAgain() {
        isChecking = true
        failure = nil
        Task {
            defer { isChecking = false }
            do {
                try await directory.checkAgain(agentID, on: device)
                if agent?.wantsSignIn == true {
                    failure = Failure(
                        message:
                            "\(agent?.agent.displayName ?? "The agent") still asks to sign in. Finish its steps, then check again.",
                        retry: nil)
                }
            } catch {
                // "Busy" says what's working and what to do; Try Again asks once more.
                failure = Failure(message: error.localizedDescription) { checkAgain() }
            }
        }
    }

    /// Closing ends a link sign-in still waiting, so the host doesn't wait on a page nobody opens.
    private func cancel() {
        if agent?.signInLink != nil {
            Task { await directory.cancelSignIn(agentID, on: device) }
        }
        dismiss()
    }
}

/// A sign-in waiting at a web page: the code large enough to read while typing it, with Copy, and
/// the page with Open and Copy Link.
struct HostSignInLinkView: View {
    let link: HostSignInLink
    let open: () -> Void
    let cancel: () -> Void

    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if let code = link.code {
                HStack(spacing: DS.Space.md) {
                    Text(code)
                        .font(.ds(HostsMetrics.deviceCodeSize, weight: .medium, design: .mono))
                        .foregroundStyle(.dsTextPrimary)
                        .textSelection(.enabled)
                    copyButton("Copy Code", text: code)
                }
            }
            HStack(spacing: DS.Space.md) {
                Text(link.url.host() ?? link.url.absoluteString)
                    .font(.dsMono)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(link.url.absoluteString)
                copyButton("Copy Link", text: link.url.absoluteString)
                Spacer(minLength: DS.Space.md)
                Button("Open Page", action: open)
                    .buttonStyle(.ds(.primary, size: .medium))
            }
            HStack(spacing: DS.Space.sm) {
                DotGridLoader(pattern: .waiting)
                    .frame(width: HostsMetrics.loader, height: HostsMetrics.loader)
                Text("Waiting for you to finish there…")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextTertiary)
                Spacer(minLength: DS.Space.md)
                Button("Stop Waiting", action: cancel)
                    .buttonStyle(.ds(.ghost))
            }
        }
        .task(id: copied) {
            guard copied != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = nil
        }
    }

    private func copyButton(_ title: String, text: String) -> some View {
        IconButton(copied == title ? "Copied" : title, systemImage: copied == title ? "checkmark" : "doc.on.doc") {
            DSPasteboard.copy(text)
            copied = title
        }
    }
}
#endif
