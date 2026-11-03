import SwiftUI

@MainActor
private enum ComposerLocationSpecPreviews {
    static func rows(width: CGFloat) -> some View {
        let app = AppModel.preview(.empty)
        let project = app.projects.add(URL(filePath: "/fixture", directoryHint: .isDirectory))
        app.quickEntry.project = project.id
        app.composeTask.options = ComposerPreviewFixtures.configOptions
        app.composeTask.configuredAgent = .init(rawValue: "claude-code")
        app.composeTask.editor = SessionModel.preview(
            in: app, cwd: "/fixture", configOptions: ComposerPreviewFixtures.configOptions)
        app.composeTask.workspace = .project
        let existing = [SessionModel.Phase.idle, .prompting, .disconnected].compactMap { phase in
            SessionModel.preview(
                in: app, cwd: "/fixture", phase: phase, configOptions: ComposerPreviewFixtures.configOptions
            ).map { (String(describing: phase), ComposerRowModelAdapter(app: app, session: $0).state) }
        }
        return VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text("New task").font(.dsCallout)
            ComposerRowPreviewFixtures.row(ComposerRowModelAdapter(app: app).state, width: width)
            ForEach(Array(existing.enumerated()), id: \.offset) { _, row in
                Text("Existing task: \(row.0)").font(.dsCallout)
                ComposerRowPreviewFixtures.row(row.1, width: width)
            }
        }
    }
}

#Preview("Where - Actual new and existing task rows") {
    DSPreviewPair { ComposerLocationSpecPreviews.rows(width: DS.ComposerRow.previewWidth) }
}

#Preview("Where - Actual rows at narrow width") {
    DSPreviewPair { ComposerLocationSpecPreviews.rows(width: DS.ComposerRow.narrowPreviewWidth) }
}
