import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// The folder of audio files the user chose in Settings › Sounds. Native lists the files in it that
/// it can play and plays them where they are, never copying them. Kept as a bookmark so the choice
/// survives the folder being moved or renamed, with the path as a fallback.
nonisolated struct SoundsFolder: Codable, Hashable, Sendable {
    var bookmark: Data?
    var path: String

    init(url: URL) {
        bookmark = try? url.bookmarkData()
        path = url.path(percentEncoded: false)
    }

    /// What the folder holds right now. Only its top level is read, so pointing it at a big tree
    /// stays cheap.
    func listing() -> SoundsFolderListing {
        guard let url else {
            return SoundsFolderListing(name: URL(filePath: path).lastPathComponent, url: nil, sounds: [])
        }
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.contentTypeKey, .isRegularFileKey], options: .skipsHiddenFiles))
            ?? []
        let sounds = files.filter(Self.isPlayable)
            .map { SoundOption(id: .folder($0.lastPathComponent), title: Self.title(for: $0), source: .file($0)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return SoundsFolderListing(name: url.lastPathComponent, url: url, sounds: sounds)
    }

    /// Where the folder is now, if it still exists. Resolving never mounts a volume or asks the user
    /// anything, since it runs whenever the sounds are listed.
    private var url: URL? {
        var isStale = false
        if let bookmark,
            let url = try? URL(
                resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &isStale)
        {
            return url
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    /// The audio types AVFoundation can open, so the list never offers a file that won't play.
    private static let playableTypes = AVURLAsset.audiovisualContentTypes.filter { $0.conforms(to: .audio) }

    private static func isPlayable(_ file: URL) -> Bool {
        guard let values = try? file.resourceValues(forKeys: [.contentTypeKey, .isRegularFileKey]),
            values.isRegularFile == true, let type = values.contentType
        else { return false }
        return playableTypes.contains { type.conforms(to: $0) }
    }

    /// A file's title from its name: "door-chime_2.mp3" is "Door Chime 2". Names the user already
    /// capitalized keep their capitals.
    static func title(for file: URL) -> String {
        let words = file.deletingPathExtension().lastPathComponent
            .split { $0 == "-" || $0 == "_" || $0.isWhitespace }
            .joined(separator: " ")
        guard !words.isEmpty else { return file.lastPathComponent }
        return words.contains(where: \.isUppercase) ? words : words.localizedCapitalized
    }
}

/// The sounds folder as Native last found it.
nonisolated struct SoundsFolderListing: Sendable {
    /// The folder's name, which titles its submenu in the sound picker.
    let name: String
    /// Where the folder is; nil when Native can't find it.
    let url: URL?
    /// The files Native can play, by title.
    let sounds: [SoundOption]
}
