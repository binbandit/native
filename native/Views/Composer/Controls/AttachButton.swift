import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The "+" chip: picks files and images to send with the draft. On iPad, where pictures live in the
/// photo library, it offers that alongside Files.
struct AttachButton: View {
    @Binding var isPickingFiles: Bool
    let onPick: (IncomingAttachments) -> Void
    /// Fine print owns the file importer outside its popover so the keyboard command also works closed.
    var presentsFilePicker = true
    var isPage = false

    @State private var isPickingPhotos = false
    @State private var photo: PhotosPickerItem?

    var body: some View {
        Group {
            if ComposerPlatform.offersPhotoLibrary {
                Menu {
                    Button("Photo Library", systemImage: "photo.on.rectangle") { isPickingPhotos = true }
                    Button("Files…", systemImage: "folder") { isPickingFiles = true }
                } label: {
                    Label("Attach", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .pillChrome(isSquare: true)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
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
        .task(id: photo) {
            guard let photo, let data = try? await photo.loadTransferable(type: Data.self) else { return }
            onPick(.image(data, photo.supportedContentTypes.first ?? .image))
            self.photo = nil
        }
    }
}

#if DEBUG
#Preview("Attach button") {
    DSPreviewPair {
        ComposerControlsBar {
            AttachButton(isPickingFiles: .constant(false), onPick: { _ in })
        } trailing: {
            EmptyView()
        }
        .frame(width: 200)
    }
}
#endif
