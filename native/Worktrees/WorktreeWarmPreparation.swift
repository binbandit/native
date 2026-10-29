import Experiments
import Foundation
import Git

extension GitStore {
    /// Kept behind Labs until the project controls and timings have passed design review.
    func warmTaskWorktree(_ folder: URL, from project: URL) async throws -> String? {
        guard ExperimentStore.shared.value(of: .warmWorktrees) else { return nil }
        let configuration = settings.warmWorktree(forProjectAt: project)
        guard configuration.enabled else {
            return "Warm setup is off for this project. No caches or env files were copied."
        }
        let report = try await requireRepository(at: project).warmWorktree(at: folder, settings: configuration)
        if report.unsupported {
            return
                "Caches weren't copied. Warm worktrees need both folders on the same APFS volume. Setup commands still run."
        }
        var parts: [String] = []
        if !report.cloned.isEmpty {
            parts.append(
                "Cloned from the project: \(report.cloned.joined(separator: ", ")). Storage is shared until files change."
            )
        } else {
            parts.append("No matching caches were found to bring along.")
        }
        if !report.skipped.isEmpty {
            parts.append(
                "Left unchanged or skipped unsafe paths: \(report.skipped.joined(separator: ", ")). Run the setup command to rebuild them."
            )
        }
        return parts.joined(separator: " ")
    }
}
