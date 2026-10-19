import Foundation
import Observation
import SwiftUI

/// Each project's icon: the user's choice, else the icon found in the project, else its initial.
/// Found icons are cached on disk so they show at once on the next launch, and looked for again
/// once per run in case the project's changed. Pictures are drawn for the size they're shown at,
/// so an SVG is as sharp in Settings as in the sidebar.
@Observable
final class ProjectIconStore {
    static let shared = ProjectIconStore()

    private var choices: [Project.ID: ProjectIconChoice]
    private var detected: [Project.ID: ProjectIconArtwork] = [:]
    /// Which file each found icon came from this run, relative to the project's folder.
    private var detectedPaths: [Project.ID: String] = [:]
    private var custom: [Project.ID: ProjectIconArtwork] = [:]
    @ObservationIgnored private var images: [ImageKey: Image] = [:]
    @ObservationIgnored private var resolved: Set<Project.ID> = []
    @ObservationIgnored private let resolver: ProjectIconResolver
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let directory: URL

    private static let choicesKey = "projectIcons.choices"

    /// Which of a project's pictures a file or cached image is.
    private enum Slot: String {
        case detected, custom
    }

    private struct ImageKey: Hashable {
        let project: Project.ID
        let slot: Slot
        let side: CGFloat
    }

    init(
        files: any ProjectFileReading = LocalProjectFiles(),
        defaults: UserDefaults = .standard,
        // Per bundle id, like the app's other stores, so isolated test builds don't share icons.
        directory: URL = URL.applicationSupportDirectory.appending(
            path: "\(Bundle.main.bundleIdentifier ?? "Native")/ProjectIcons", directoryHint: .isDirectory)
    ) {
        resolver = ProjectIconResolver(files: files)
        self.defaults = defaults
        self.directory = directory
        let saved = defaults.data(forKey: Self.choicesKey).flatMap {
            try? JSONDecoder().decode([String: ProjectIconChoice].self, from: $0)
        }
        choices = Dictionary(
            uniqueKeysWithValues: (saved ?? [:]).compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
        for (project, choice) in choices where choice == .image {
            custom[project] = load(.custom, for: project)
        }
    }

    /// What leads the project's row, drawn for a `size`-point square.
    func icon(for project: Project, size: CGFloat = DS.Size.rowLeading) -> ProjectIcon {
        switch choice(for: project.id) {
        case .automatic, .file: image(.detected, for: project.id, side: size).map(ProjectIcon.image) ?? .initial
        case .initial: .initial
        case .emoji(let emoji): .emoji(emoji)
        case .symbol(let name): .symbol(name)
        case .image: image(.custom, for: project.id, side: size).map(ProjectIcon.image) ?? .initial
        }
    }

    func choice(for project: Project.ID) -> ProjectIconChoice {
        choices[project] ?? .automatic
    }

    /// The icon found in the project, if any, for the picker to offer.
    func detectedImage(for project: Project.ID, size: CGFloat = DS.Size.rowLeading) -> Image? {
        image(.detected, for: project, side: size)
    }

    /// The file the project's found icon came from, once it's been looked for this run.
    func detectedPath(for project: Project.ID) -> String? {
        detectedPaths[project]
    }

    /// Whether `icon` is the picture automatic found for the project.
    func isDetected(_ icon: ProjectIconResolver.FoundIcon, in project: Project) -> Bool {
        detected[project.id] == icon.artwork
    }

    /// Every icon file in the project, for the picker to list.
    func foundIcons(in project: Project) async -> [ProjectIconResolver.FoundIcon] {
        await resolver.foundIcons(in: project.url)
    }

    /// Looks for the project's own icon, once per run, showing last run's in the meantime.
    func resolve(_ project: Project) async {
        guard resolved.insert(project.id).inserted else { return }
        if detected[project.id] == nil {
            setDetected(load(.detected, for: project.id), for: project.id, saving: false)
        }
        await detect(project)
    }

    func setChoice(_ choice: ProjectIconChoice, for project: Project, undoManager: UndoManager? = nil) {
        let previous = self.choice(for: project.id)
        guard choice != previous else { return }
        choices[project.id] = choice == .automatic ? nil : choice
        save()
        // The found icon follows the choice: the chosen file, or the candidates' order again.
        if choice.readsProjectFile || previous.readsProjectFile {
            Task { await detect(project) }
        }
        undoManager?.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.setChoice(previous, for: project, undoManager: undoManager) }
        }
        undoManager?.setActionName("Change Icon")
    }

    /// Uses one of the icon files found in the project.
    func choose(_ icon: ProjectIconResolver.FoundIcon, for project: Project, undoManager: UndoManager? = nil) {
        setDetected(icon.artwork, for: project.id)
        detectedPaths[project.id] = icon.path
        setChoice(.file(icon.path), for: project, undoManager: undoManager)
    }

    /// Uses a file the user picked, kept as a copy so the original can move or go: an SVG as it is,
    /// a bitmap as a small PNG. `isSVG` comes from the file's type, when it's known. Throws why the
    /// file can't be an icon.
    func setCustomImage(
        _ data: Data, isSVG: Bool? = nil, for project: Project, undoManager: UndoManager? = nil
    ) throws(ProjectIconRejection) {
        let artwork = try ProjectIconArtwork.decode(data, isSVG: isSVG)
        let previous = (artwork: custom[project.id], choice: choice(for: project.id))
        setCustom(artwork, for: project.id)
        setChoice(.image, for: project)
        undoManager?.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                store.setCustom(previous.artwork, for: project.id)
                store.setChoice(previous.choice, for: project)
            }
        }
        undoManager?.setActionName("Change Icon")
    }

    private func detect(_ project: Project) async {
        let preferred: String? = if case .file(let path) = choice(for: project.id) { path } else { nil }
        let found = await resolver.detectIcon(in: project.url, preferring: preferred)
        setDetected(found?.artwork, for: project.id)
        detectedPaths[project.id] = found?.path
    }

    private func setDetected(_ artwork: ProjectIconArtwork?, for project: Project.ID, saving: Bool = true) {
        guard detected[project] != artwork else { return }
        detected[project] = artwork
        forgetImages(.detected, of: project)
        if saving { store(artwork, as: .detected, for: project) }
    }

    private func setCustom(_ artwork: ProjectIconArtwork?, for project: Project.ID) {
        custom[project] = artwork
        forgetImages(.custom, of: project)
        store(artwork, as: .custom, for: project)
    }

    /// The picture in `slot`, drawn once per size it's shown at.
    private func image(_ slot: Slot, for project: Project.ID, side: CGFloat) -> Image? {
        let key = ImageKey(project: project, slot: slot, side: side)
        if let image = images[key] { return image }
        let artwork = slot == .detected ? detected[project] : custom[project]
        guard let image = artwork?.image(side: side) else { return nil }
        images[key] = image
        return image
    }

    private func forgetImages(_ slot: Slot, of project: Project.ID) {
        images = images.filter { $0.key.project != project || $0.key.slot != slot }
    }

    private func save() {
        let saved = Dictionary(uniqueKeysWithValues: choices.map { ($0.key.uuidString, $0.value) })
        defaults.set(try? JSONEncoder().encode(saved), forKey: Self.choicesKey)
    }

    // MARK: - Files

    private func url(_ slot: Slot, for project: Project.ID, extension fileExtension: String) -> URL {
        directory.appending(path: "\(slot.rawValue)-\(project.uuidString).\(fileExtension)")
    }

    private func load(_ slot: Slot, for project: Project.ID) -> ProjectIconArtwork? {
        ["svg", "png"].lazy.compactMap { ProjectIconArtwork.load(from: self.url(slot, for: project, extension: $0)) }
            .first
    }

    /// Writes the picture, replacing whatever was saved in its slot; nil removes it.
    private func store(_ artwork: ProjectIconArtwork?, as slot: Slot, for project: Project.ID) {
        for fileExtension in ["svg", "png"] where fileExtension != artwork?.fileExtension {
            try? FileManager.default.removeItem(at: url(slot, for: project, extension: fileExtension))
        }
        guard let artwork else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? artwork.data.write(to: url(slot, for: project, extension: artwork.fileExtension), options: .atomic)
    }
}

extension EnvironmentValues {
    /// The project icons to draw from; `ProjectIconStore.shared` when nothing is injected.
    @Entry var projectIconStore: ProjectIconStore?
}
