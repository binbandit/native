import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The "+" chip: picks files and images to send with the draft. On iPad, where pictures live in the
/// photo library, it offers that alongside Files.
struct AttachButton: View {
    @Binding var isPickingFiles: Bool
    let onPick: (IncomingAttachments) -> Void
    var isQuiet = false

    @State private var isPickingPhotos = false
    @State private var photo: PhotosPickerItem?

    var body: some View {
        Group {
            if ComposerPlatform.offersPhotoLibrary {
                Menu {
                    Button("Photo Library", systemImage: "photo.on.rectangle") { isPickingPhotos = true }
                    Button("Files…", systemImage: "folder") { isPickingFiles = true }
                } label: {
                    if isQuiet {
                        Label("Attach", systemImage: "plus")
                            .labelStyle(.iconOnly)
                            .font(.dsBody)
                            .foregroundStyle(.dsTextSecondary)
                            .frame(width: DS.Size.minimumHitTarget, height: DS.Size.minimumHitTarget)
                    } else {
                        Label("Attach", systemImage: "plus")
                            .labelStyle(.iconOnly)
                            .pillChrome(isSquare: true)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            } else if isQuiet {
                Button("Attach Files", systemImage: "plus") { isPickingFiles = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(ComposerFactButtonStyle())
            } else {
                Button("Attach Files", systemImage: "plus") { isPickingFiles = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.pill(isSquare: true))
            }
        }
        .help("Attach files… (⌘U)")
        .fileImporter(isPresented: $isPickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) {
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
            AttachButton(isPickingFiles: .constant(false), onPick: { _ in }, isQuiet: true)
        } trailing: {
            EmptyView()
        }
        .frame(width: 200)
    }
}
#endif
