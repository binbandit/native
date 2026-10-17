import SwiftUI
import UniformTypeIdentifiers

/// The "+" chip: picks files to mention in the draft.
///
/// On iPad the files live on the iPad, not the host, so they need to travel with the prompt as
/// content; that waits on `SessionModel` taking attachments, and then this becomes a Photos and
/// Files menu there.
struct AttachButton: View {
    let onPick: ([URL]) -> Void

    @State private var isPicking = false

    var body: some View {
        Button("Attach Files", systemImage: "plus") {
            isPicking = true
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.pill(isSquare: true))
        .help("Attach files…")
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                onPick(urls)
            }
        }
    }
}
