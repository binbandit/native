import Exec
import Experiments
import Foundation
import Git

extension GitStore {
    /// Kept behind Labs until the project controls and timings have passed design review.
    func warmTaskWorktree(_ folder: URL, from project: URL) async throws -> String? {
        guard ExperimentStore.shared.value(of: .warmWorktrees) else { return nil }
        let configuration = settings.warmWorktree(forProjectAt: project)
        guard configuration.enabled, !configuration.folders.isEmpty else { return nil }
        let report = try await requireRepository(at: project).warmWorktree(at: folder, settings: configuration)
        if report.unsupported {
            return
                "Caches weren't copied. Warm worktrees need both folders on the same APFS volume. Setup commands still run."
        }
        var parts: [String] = []
        if !report.cloned.isEmpty {
            parts.append(
                "Copied \(report.cloned.joined(separator: ", "))."
            )
        } else {
            parts.append("No matching folders to copy.")
        }
        if !report.skipped.isEmpty {
            parts.append(
                "Left unchanged or skipped unsafe paths: \(report.skipped.joined(separator: ", ")). Run the setup command to rebuild them."
            )
        }
        return parts.joined(separator: " ")
    }
}
