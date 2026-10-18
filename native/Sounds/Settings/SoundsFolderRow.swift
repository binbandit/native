import SwiftUI
import UniformTypeIdentifiers

/// Settings › Sounds › Sounds folder: a folder of the user's own audio files, whose sounds every
/// trigger's picker then offers. A select like the terminal's shell: none, the current folder, or
/// "Choose Folder…" to pick one.
struct SoundsFolderRow: View {
    let sounds: NotificationSounds

    @State private var isChoosing = false

    private enum Choice: Hashable {
        case noFolder
        case current
        case choose
    }

    var body: some View {
        SettingsRow(
            id: SoundsSettingsPage.folderRow,
            "Sounds folder",
            description: Text("Pick from your own audio files for each sound. Native plays them where they are."),
            detail: detail
        ) {
            SettingsSelect(
                label: "Sounds folder", selection: selection, options: options, width: SoundsSettingsPage.selectWidth)
        }
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                sounds.setSoundsFolder(url)
            }
        }
    }

    private var options: [SettingsSelect<Choice>.Option] {
        var options: [SettingsSelect<Choice>.Option] = [.init(value: .noFolder, title: "None")]
        if let folder = sounds.catalog.folder {
            options.append(.init(value: .current, title: folder.name))
        }
        return options + [.init(value: .choose, title: "Choose Folder…")]
    }

    private var selection: Binding<Choice> {
        Binding {
            sounds.catalog.folder == nil ? .noFolder : .current
        } set: { choice in
            switch choice {
            case .noFolder: sounds.setSoundsFolder(nil)
            case .current: break
            case .choose: isChoosing = true
            }
        }
    }

    /// Where the folder is and what Native found there, or why it found nothing.
    private var detail: Text? {
        guard let folder = sounds.preferences.soundsFolder, let listing = sounds.catalog.folder else { return nil }
        guard let url = listing.url else {
            let path = URL(filePath: folder.path).abbreviatedPath
            return Text(
                "Native can't find \(path). Choose it again or pick another; until then, Native's own sounds play instead."
            )
        }
        let count = listing.sounds.count
        guard count > 0 else {
            return Text("\(url.abbreviatedPath) has no audio files Native can play, such as WAV, AIFF, MP3 or M4A.")
        }
        let found = count == 1 ? "1 sound" : "\(count) sounds"
        return Text("\(found) from \(url.abbreviatedPath), under “\(listing.name)” in each sound's menu.")
    }
}
