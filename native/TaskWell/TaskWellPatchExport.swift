import Git
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Export Patch, offered where the pull request would be when this install has no route to
/// GitHub: the branch's commits as one file that `git am` applies on a connected machine. The
/// well says what happened, so the step after saving is never a guess.
@Observable
final class TaskWellPatchExport {
    enum Outcome: Equatable {
        case saved(file: String, commits: Int, leftOutChanges: Bool)
        case noCommits
        case noBase
        case failed(String)
    }

    private(set) var isPreparing = false
    private(set) var outcome: Outcome?
    /// Set while the save panel is up.
    var document: TaskWellPatchDocument?
    private(set) var filename = "branch"
    private var hasUncommittedChanges = false
    private var commits = 0

    /// What the well's pull request row says under "Not available here".
    var note: String {
        let offer =
            "This install has no route to GitHub. Export the branch as a patch and open the pull request from a connected machine."
        switch outcome {
        case nil: return offer
        case .saved(let file, let commits, let leftOutChanges):
            let count = commits == 1 ? "1 commit" : "\(commits) commits"
            let left = leftOutChanges ? " Uncommitted changes aren't in it." : ""
            return
                "Saved \(file) with \(count).\(left) On a connected machine, apply it with git am and open the pull request there."
        case .noCommits:
            return "This branch has no commits of its own yet. Commit its changes in Changes, then export them."
        case .noBase:
            return "There's no default branch to compare this branch with, so there's nothing to export."
        case .failed(let message): return "Couldn't export the patch. \(message)"
        }
    }

    /// Reads the branch's commits and, when there are any, puts up the save panel.
    func prepare(from repository: GitRepositoryModel, branch: String) async {
        guard !isPreparing else { return }
        guard let git = repository.repository else {
            outcome = .failed("The repository isn't loaded yet. Try again in a moment.")
            return
        }
        isPreparing = true
        defer { isPreparing = false }
        hasUncommittedChanges = (repository.status?.changedFileCount ?? 0) > 0
        do {
            guard let patch = try await git.branchPatch() else {
                outcome = .noBase
                return
            }
            guard patch.commits > 0 else {
                outcome = .noCommits
                return
            }
            filename = branch.replacing("/", with: "-")
            commits = patch.commits
            outcome = nil
            document = TaskWellPatchDocument(data: patch.data)
        } catch {
            outcome = .failed(error.localizedDescription)
        }
    }

    /// The save panel's answer. Cancelling leaves the offer as it was.
    func finish(_ result: Result<URL, any Error>) {
        document = nil
        switch result {
        case .success(let url):
            outcome = .saved(file: url.lastPathComponent, commits: commits, leftOutChanges: hasUncommittedChanges)
        case .failure(let error as CocoaError) where error.code == .userCancelled:
            break
        case .failure(let error):
            outcome = .failed(error.localizedDescription)
        }
    }
}

extension View {
    /// The save panel for `export`, up while it holds a patch; `finished` runs once it's saved or failed.
    func taskWellPatchExporter(_ export: TaskWellPatchExport, finished: @escaping () -> Void) -> some View {
        fileExporter(
            isPresented: Binding(get: { export.document != nil }, set: { if !$0 { export.document = nil } }),
            document: export.document, contentType: .gitPatch, defaultFilename: export.filename
        ) { result in
            export.finish(result)
            finished()
        }
    }
}

/// The exported mailbox, for `fileExporter`.
struct TaskWellPatchDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.gitPatch]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    nonisolated static let gitPatch = UTType(filenameExtension: "patch", conformingTo: .plainText) ?? .plainText
}
