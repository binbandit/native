import ACP
import SwiftUI

struct ArtifactViewer: View {
    @Bindable var model: ArtifactViewerModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if model.isLoading {
                    LoadingStateView("Opening artifact…")
                } else if let error = model.error {
                    EmptyStateView("Couldn't preview this artifact", systemImage: "doc", message: error) {
                        if model.canRetry { Button("Try Again", action: model.retry) }
                    }
                } else if let image = model.image {
                    ArtifactImageCanvas(image: image, model: model)
                } else if let file = model.previewFile {
                    PlatformArtifactPreview(url: file.url)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.dsSurfaceSunken)
            Divider()
            footer
        }
        .background(.dsSurface)
        .frame(
            minWidth: DS.Artifact.minimumWidth, idealWidth: DS.Artifact.viewerWidth,
            minHeight: DS.Artifact.minimumHeight, idealHeight: DS.Artifact.viewerHeight
        )
        .fileExporter(
            isPresented: $model.isExporting,
            document: model.data.map { ArtifactDocument(data: $0) },
            contentType: model.contentType, defaultFilename: model.artifact?.filename
        ) { model.exported($0) }
    }

    private var header: some View {
        HStack(spacing: DS.Space.md) {
            Text(model.artifact?.name ?? "Artifact")
                .font(.dsHeadline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: DS.Space.sm)
            if model.image != nil {
                IconButton("Zoom Out", systemImage: "minus.magnifyingglass", size: .large) { model.zoom(by: 0.8) }
                    .keyboardShortcut("-", modifiers: .command)
                Text((model.viewport.fitScale * model.viewport.zoom).formatted(.percent.precision(.fractionLength(0))))
                    .font(.dsCaption)
                    .monospacedDigit()
                    .foregroundStyle(.dsTextSecondary)
                    .accessibilityLabel("Zoom")
                    .accessibilityValue((model.viewport.fitScale * model.viewport.zoom).formatted(.percent))
                IconButton("Zoom In", systemImage: "plus.magnifyingglass", size: .large) { model.zoom(by: 1.25) }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Fit", action: model.fit)
                    .buttonStyle(.ds(.secondary))
                    .keyboardShortcut("0", modifiers: .command)
            }
            IconButton("Close Viewer", systemImage: "xmark", size: .large, action: model.close)
                .keyboardShortcut(.cancelAction)
        }
        .padding(DS.Space.lg)
    }

    private var footer: some View {
        HStack(spacing: DS.Space.md) {
            if let feedback = model.feedback {
                Text(feedback).font(.dsCaption).foregroundStyle(.dsTextSecondary)
            }
            Spacer(minLength: 0)
            IconButton("Copy Artifact", systemImage: "doc.on.doc", size: .large, action: model.copy)
                .keyboardShortcut("c", modifiers: .command)
                .disabled(model.data == nil)
            Button("Save As…", action: model.saveAs)
                .buttonStyle(.ds(.secondary))
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.data == nil)
            if model.revealURL != nil {
                IconButton("Show in Finder", systemImage: "folder", size: .large, action: model.reveal)
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        .padding(DS.Space.lg)
    }
}

#if DEBUG
#Preview("Artifact viewer - Loading") {
    DSPreviewPair {
        ArtifactViewer(model: ArtifactPreviewFixtures.loading())
            .frame(width: 640, height: 480)
    }
}

#Preview("Artifact viewer - Unavailable") {
    DSPreviewPair {
        ArtifactViewer(model: ArtifactPreviewFixtures.unavailable())
            .frame(width: 400, height: 480)
    }
}
#endif
