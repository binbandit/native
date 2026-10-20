import AIInstructions
import GitHub
import SwiftUI

/// Opens a pull request for a pushed branch: title, description, base and draft, with an optional
/// on-device AI draft written from the branch's commits and diff. Nothing is sent to GitHub until
/// the user presses Create.
struct CreatePullRequestSheet: View {
    let request: CreatePullRequestRequest

    @Environment(GitHubModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var base = ""
    @State private var defaultBase: String?
    @State private var isDraft = false
    @State private var existing: PullRequestSummary?
    /// Set when a pull request can't be opened from here at all, which the sheet explains instead.
    @State private var blocker: GitHubSetupView.Problem?
    @State private var isCreating = false
    @State private var created: URL?
    @State private var error: GitHubError?
    @State private var drafting: Task<Void, Never>?
    @State private var draftError: String?
    @FocusState private var focus: Field?

    private enum Field {
        case title, description, base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            SeparatorLine()
            Group {
                if let created {
                    CreatedPullRequestView(
                        url: created, onCopy: { model.copy(created.absoluteString) }, onDone: { dismiss() })
                } else if let blocker {
                    GitHubSetupView(problem: blocker) { await load() }
                        .frame(minHeight: CreatePullRequestLayout.descriptionHeight * 1.5)
                } else {
                    form
                }
            }
            .padding(DS.Space.xl)
            if created == nil, blocker == nil {
                SeparatorLine()
                footer
            }
        }
        .frame(width: CreatePullRequestLayout.width)
        .background(.dsBackground)
        .task { await load() }
        .onDisappear { drafting?.cancel() }
    }

    private var header: some View {
        HStack(spacing: DS.Space.md) {
            Text("Create Pull Request")
                .font(.dsHeadline)
                .foregroundStyle(.dsTextPrimary)
            Spacer(minLength: DS.Space.md)
            IconButton("Close", systemImage: "xmark") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.leading, DS.Space.xl)
        .padding(.trailing, DS.Space.md)
        .frame(height: DS.Window.headerHeight + DS.Space.md)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            BranchFlowRow(
                head: request.head, base: $base, placeholder: defaultBase ?? "default branch", focus: $focus,
                field: .base)
            if let existing {
                ExistingPullRequestNotice(pullRequest: existing)
            }
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack {
                    FieldLabel("Title")
                    Spacer()
                    DraftWithAIButton(isDrafting: drafting != nil, action: draft)
                }
                TextField("Title", text: $title, prompt: Text("Summarize the change").foregroundStyle(.dsTextTertiary))
                    .textFieldStyle(.plain)
                    .font(.dsCallout)
                    .focused($focus, equals: .title)
                    .formFieldChrome(isFocused: focus == .title)
            }
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                FieldLabel("Description")
                TextEditor(text: $description)
                    .font(.dsBody)
                    .scrollContentBackground(.hidden)
                    .focused($focus, equals: .description)
                    .overlay(alignment: .topLeading) {
                        if description.isEmpty {
                            Text("What was wrong or missing, and how this addresses it. Markdown works.")
                                .font(.dsBody)
                                .foregroundStyle(.dsTextTertiary)
                                .padding(.leading, CreatePullRequestLayout.editorTextInset)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(height: CreatePullRequestLayout.descriptionHeight)
                    .formFieldChrome(isFocused: focus == .description, isMultiline: true)
            }
            if let draftError {
                Text(draftError)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            }
            if let error {
                Text(error.stderr.flatMap { $0.isEmpty ? nil : $0 } ?? error.localizedDescription)
                    .font(.dsBody)
                    .foregroundStyle(.dsDanger)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(isCreating || existing != nil)
    }

    private var footer: some View {
        HStack(spacing: DS.Space.md) {
            if existing == nil {
                GitHubCheckbox(title: "Create as draft", isOn: $isDraft)
            }
            Spacer(minLength: DS.Space.md)
            Button("Cancel") { dismiss() }
                .buttonStyle(.ds(.ghost, size: .medium))
            if let existing {
                // GitHub allows one open pull request per branch, so the way forward is that one.
                Button("Open \(existing.reference)") {
                    model.openInBrowser(existing)
                    dismiss()
                }
                .buttonStyle(.ds(.primary, size: .medium))
                .keyboardShortcut(.defaultAction)
            } else {
                Button(isCreating ? "Creating…" : isDraft ? "Create Draft" : "Create Pull Request") {
                    Task { await create() }
                }
                .buttonStyle(.ds(.primary, size: .medium))
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.lg)
    }

    // MARK: - Actions

    private func load() async {
        if base.isEmpty { base = request.base ?? "" }
        if title.isEmpty, let subject = Self.firstSubject(of: request.commits) {
            title = subject
        }
        focus = .title
        do {
            defaultBase = try await model.repository(of: request.directory).defaultBranch
            blocker = nil
        } catch .notInstalled {
            blocker = .notInstalled
        } catch .notAuthenticated {
            blocker = .notAuthenticated
        } catch .notARepository(let message) {
            blocker = .failed(.notARepository(message))
        } catch {
            // Offline and the like: let the user write, and say why when they press Create.
            blocker = nil
        }
        if blocker == nil {
            existing = await model.openPullRequest(for: request.branch)
        }
    }

    private func create() async {
        error = nil
        isCreating = true
        defer { isCreating = false }
        let trimmedBase = base.trimmingCharacters(in: .whitespaces)
        let pullRequest = NewPullRequest(
            title: title.trimmingCharacters(in: .whitespaces),
            body: description,
            head: request.head,
            base: trimmedBase.isEmpty ? nil : trimmedBase,
            isDraft: isDraft
        )
        do {
            created = try await model.createPullRequest(pullRequest, in: request.directory)
        } catch {
            self.error = error
        }
    }

    private func draft() {
        if let drafting {
            drafting.cancel()
            self.drafting = nil
            return
        }
        if let reason = PullRequestDrafter.unavailableReason {
            draftError = reason
            return
        }
        draftError = nil
        let prompt = PullRequestDraftPrompt(
            head: request.head,
            base: base.isEmpty ? defaultBase : base,
            commits: request.commits,
            diff: request.diff,
            template: request.template
        )
        drafting = Task {
            defer { drafting = nil }
            do {
                let instructions = AIInstructionsStore.shared.addition(for: .pullRequest, in: request.directory)
                try await PullRequestDrafter.draft(prompt, instructions: instructions) { title, body in
                    if let title { self.title = title }
                    if let body { self.description = body }
                }
            } catch is CancellationError {
            } catch {
                draftError = "Couldn't draft: \(error.localizedDescription)"
            }
        }
    }

    /// The newest commit's subject, a better starting title than nothing. `git log --oneline`
    /// lines start with the abbreviated hash.
    static func firstSubject(of commits: String) -> String? {
        guard let line = commits.split(whereSeparator: \.isNewline).first else { return nil }
        let words = line.split(separator: " ", maxSplits: 1)
        let isHash = words.count == 2 && words[0].count >= 7 && words[0].allSatisfy(\.isHexDigit)
        return String(isHash ? words[1] : line).trimmingCharacters(in: .whitespaces)
    }
}

enum CreatePullRequestLayout {
    static let width: CGFloat = 560
    static let descriptionHeight: CGFloat = 200
    /// `NSTextView`'s line fragment padding, where the description's placeholder has to start.
    static let editorTextInset: CGFloat = 5
}

#if NATIVE_PREVIEWS_WIP
#Preview("Create pull request") {
    DSPreviewPair {
        CreatePullRequestSheet(request: PullRequestPreviewFixtures.createRequest)
    }
    .environment(GitHubModel.preview())
}
#endif
