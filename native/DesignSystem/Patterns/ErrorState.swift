import SwiftUI

/// The one way to show a failure: what happened, what Native already did about it, what the user
/// can do, and one primary action, with the raw error output behind "Show Details".
///
///     ErrorState(
///         "Codex stopped mid-turn",
///         recovery: "Native restarted it and reloaded the session.",
///         suggestion: "Send your last message again to pick up where it left off.",
///         details: stderr,
///         primary: .init("Resend") { resend() }
///     )
///
/// `.inline` sits in a list or above the composer (a `NoticeBanner`); `.pane` fills an empty pane.
public struct ErrorState: View {
    public enum Layout: Sendable {
        case inline, pane, reading
    }

    /// A button the error offers.
    public struct Action {
        let title: String
        let perform: () -> Void
        let shortcut: KeyboardShortcut?

        public init(_ title: String, shortcut: KeyboardShortcut? = nil, perform: @escaping () -> Void) {
            self.title = title
            self.shortcut = shortcut
            self.perform = perform
        }
    }

    let title: String
    let recovery: String?
    let suggestion: String?
    let details: String?
    let primary: Action?
    let secondary: Action?
    let layout: Layout

    @State private var isShowingDetails = false

    /// - Parameters:
    ///   - title: What happened, in plain words.
    ///   - recovery: What Native already did about it.
    ///   - suggestion: What the user can do.
    ///   - details: The raw error output, shown on request in monospace.
    ///   - primary: The one thing to do next (Retry, Sign In, Install).
    ///   - secondary: A quieter alternative (Disable for This Project).
    public init(
        _ title: String,
        recovery: String? = nil,
        suggestion: String? = nil,
        details: String? = nil,
        primary: Action? = nil,
        secondary: Action? = nil,
        layout: Layout = .inline
    ) {
        self.title = title
        self.recovery = recovery
        self.suggestion = suggestion
        self.details = details
        self.primary = primary
        self.secondary = secondary
        self.layout = layout
    }

    private var explanation: String? {
        let text = [recovery, suggestion].compactMap(\.self).joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    public var body: some View {
        switch layout {
        case .inline:
            VStack(alignment: .leading, spacing: 0) {
                NoticeBanner(tone: .danger, title: title, detail: explanation) {
                    buttons
                }
                if isShowingDetails, let details {
                    detailsView(details)
                        .padding(.top, DS.Space.xs)
                }
            }
        case .reading:
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.dsCalloutMedium).foregroundStyle(.dsTextPrimary)
                if let explanation {
                    Text(explanation).font(.dsBody).foregroundStyle(.dsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.xs)
                }
                if let details {
                    detailsView(
                        isShowingDetails
                            ? details : details.components(separatedBy: .newlines).prefix(3).joined(separator: "\n")
                    )
                    .padding(.top, DS.Space.lg)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.Space.md) {
                        Spacer(minLength: 0); buttons
                    }
                    VStack(alignment: .leading, spacing: DS.Space.md) { buttons }
                }
                .padding(.top, DS.Space.lg)
            }
        case .pane:
            VStack(spacing: DS.Space.md) {
                Image(systemName: "exclamationmark.octagon")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.dsDanger)
                    .padding(.bottom, DS.Space.xs)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.dsCalloutMedium)
                    .foregroundStyle(.dsTextPrimary)
                if let explanation {
                    Text(explanation)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                HStack(spacing: DS.Space.md) {
                    buttons
                }
                .padding(.top, DS.Space.xs)
                if isShowingDetails, let details {
                    detailsView(details)
                        .frame(maxWidth: 480)
                }
            }
            .tracking(DS.Tracking.tight)
            .padding(DS.Space.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var buttons: some View {
        if details != nil {
            Button(
                isShowingDetails
                    ? (layout == .reading ? "Hide Output" : "Hide Details")
                    : (layout == .reading ? "Show Output" : "Show Details")
            ) {
                withAnimation(.dsDisclosure) { isShowingDetails.toggle() }
            }
            .buttonStyle(.ds(.ghost))
            .keyboardShortcut(layout == .reading ? KeyboardShortcut("o", modifiers: [.command, .option]) : nil)
        }
        if let secondary {
            Button(secondary.title, action: secondary.perform)
                .buttonStyle(.ds(.secondary))
                .keyboardShortcut(secondary.shortcut)
        }
        if let primary {
            Button(primary.title, action: primary.perform)
                .buttonStyle(.ds(.primary))
                .keyboardShortcut(primary.shortcut)
        }
    }

    private func detailsView(_ details: String) -> some View {
        CappedHeightScrollView(maxHeight: 160) {
            Text(details)
                .font(.dsMonoCaption)
                .foregroundStyle(.dsTextSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.md)
        }
        .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
        .overlay(alignment: .topTrailing) {
            IconButton("Copy Error Output", systemImage: "doc.on.doc") {
                DSPasteboard.copy(self.details ?? details)
            }
            .padding(DS.Space.xs)
        }
    }
}

#Preview("Error state") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            ErrorState(
                "The GitHub MCP server didn't start",
                recovery: "Native kept the task running without it.",
                suggestion: "Check the server's command, then retry.",
                details: "Error: spawn npx ENOENT\n    at ChildProcess._handle.onexit",
                primary: .init("Retry") {},
                secondary: .init("Disable for This Project") {}
            )
            ErrorState(
                "Codex isn't installed",
                suggestion: "Install it with `npm install -g @openai/codex`, then check again.",
                primary: .init("Check Again") {},
                layout: .pane
            )
            .frame(height: 220)
        }
        .frame(width: 560)
    }
}

#if DEBUG
#Preview("Error state - Reading column") {
    DSPreviewPair {
        ErrorState(
            "Codex stopped before finishing", recovery: "Native kept the task's conversation.",
            details: "The build stopped while linking.", primary: .init("Retry") {},
            secondary: .init("Open Task") {}, layout: .reading
        )
        .padding(DS.Space.xl).frame(width: DS.HomeNext.column)
    }
}
#endif
