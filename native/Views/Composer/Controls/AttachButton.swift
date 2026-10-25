import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The "+" chip: picks files and images to send with the draft. On iPad, where pictures live in the
/// photo library, it offers that alongside Files. In Fine print's field it's a quiet paperclip.
struct AttachButton: View {
    @Binding var isPickingFiles: Bool
    let onPick: (IncomingAttachments) -> Void
    var presentsFilePicker = true
    var isPage = false
    /// Fine print's paperclip among the field's trailing controls.
    var isField = false

    @State private var isPickingPhotos = false
    @State private var photo: PhotosPickerItem?
    @State private var isHovered = false

    var body: some View {
        Group {
            if ComposerPlatform.offersPhotoLibrary {
                Menu {
                    Button("Photo Library", systemImage: "photo.on.rectangle") { isPickingPhotos = true }
                    Button("Files…", systemImage: "folder") { isPickingFiles = true }
                } label: {
                    if isField {
                        paperclip
                    } else {
                        Label("Attach", systemImage: "plus")
                            .labelStyle(.iconOnly)
                            .pillChrome(isSquare: true)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            } else if isField {
                Button {
                    isPickingFiles = true
                } label: {
                    paperclip
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attach Files")
            } else {
                Button("Attach Files", systemImage: isPage ? "paperclip" : "plus") { isPickingFiles = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.pill(isSquare: true))
            }
        }
        .help("Attach files… (⌘U)")
        .fileImporter(
            isPresented: presentsFilePicker ? $isPickingFiles : .constant(false), allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) {
            result in
            if case .success(let urls) = result, !urls.isEmpty {
                onPick(.files(urls))
            }
        }
        .photosPicker(isPresented: $isPickingPhotos, selection: $photo, matching: .images)
        .trackHover($isHovered)
        .task(id: photo) {
            guard let photo, let data = try? await photo.loadTransferable(type: Data.self) else { return }
            onPick(.image(data, photo.supportedContentTypes.first ?? .image))
            self.photo = nil
        }
    }
}

extension AttachButton {
    private var paperclip: some View {
        Image(systemName: "paperclip")
            .font(.system(size: AttachButtonMetrics.paperclip))
            .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextTertiary)
            .frame(width: DS.ComposerSettings.controlHeight, height: DS.ComposerSettings.controlHeight)
            .background(isHovered ? Color.dsHover : .clear, in: .rect(cornerRadius: DS.Radius.control))
            .contentShape(.rect)
            .dsHitTarget(DS.ComposerSettings.controlHeight)
    }
}

private enum AttachButtonMetrics {
    /// The field's paperclip, a touch larger than its 12pt neighbors so its thin strokes read.
    static let paperclip: CGFloat = 15
}

#if DEBUG
#Preview("Attach button") {
    DSPreviewPair {
        ComposerControlsBar {
            AttachButton(isPickingFiles: .constant(false), onPick: { _ in })
            AttachButton(isPickingFiles: .constant(false), onPick: { _ in }, isField: true)
        } trailing: {
            EmptyView()
        }
        .frame(width: 200)
    }
}
#endif
