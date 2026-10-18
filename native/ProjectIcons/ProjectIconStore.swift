import CoreGraphics
import Foundation
import ImageIO
import Observation
import SwiftUI

/// Each project's icon for the sidebar: the user's choice, else the icon found in the project,
/// else its initial. Detected icons are cached on disk so they show at once on the next launch,
/// and looked for again once per run in case the project's changed.
@Observable
final class ProjectIconStore {
    static let shared = ProjectIconStore()

    private var choices: [Project.ID: ProjectIconChoice]
    private var detected: [Project.ID: Image] = [:]
    private var custom: [Project.ID: Image] = [:]
    @ObservationIgnored private var resolved: Set<Project.ID> = []
    @ObservationIgnored private let resolver: ProjectIconResolver
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let directory: URL

    private static let choicesKey = "projectIcons.choices"

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
            custom[project] = Self.image(fromPNGAt: customURL(for: project))
        }
    }

    /// What leads the project's row.
    func icon(for project: Project) -> ProjectIcon {
        switch choice(for: project.id) {
        case .automatic: detectedImage(for: project.id).map(ProjectIcon.image) ?? .initial
        case .initial: .initial
        case .emoji(let emoji): .emoji(emoji)
        case .symbol(let name): .symbol(name)
        case .image: customImage(for: project.id).map(ProjectIcon.image) ?? .initial
        }
    }

    func choice(for project: Project.ID) -> ProjectIconChoice {
        choices[project] ?? .automatic
    }

    /// The icon found in the project, if any, for the picker to offer.
    func detectedImage(for project: Project.ID) -> Image? {
        detected[project]
    }

    /// Looks for the project's own icon, once per run, showing last run's in the meantime.
    func resolve(_ project: Project) async {
        guard resolved.insert(project.id).inserted else { return }
        let url = cacheURL(for: project.id)
        if detected[project.id] == nil {
            detected[project.id] = Self.image(fromPNGAt: url)
        }
        let png = await resolver.detectIcon(in: project.url)
        if let png {
            write(png, to: url)
            detected[project.id] = Self.image(fromPNG: png)
        } else {
            try? FileManager.default.removeItem(at: url)
            detected[project.id] = nil
        }
    }

    func setChoice(_ choice: ProjectIconChoice, for project: Project.ID) {
        choices[project] = choice == .automatic ? nil : choice
        save()
    }

    /// Uses an image file the user picked: kept as a small PNG, so the original can move or go.
    /// Returns false when the file isn't an image Native can read.
    @discardableResult
    func setCustomImage(_ data: Data, for project: Project.ID) -> Bool {
        guard let png = ProjectIconResolver.thumbnail(of: data, maxPixelSize: ProjectIconResolver.pixelSize) else {
            return false
        }
        write(png, to: customURL(for: project))
        custom[project] = Self.image(fromPNG: png)
        setChoice(.image, for: project)
        return true
    }

    private func customImage(for project: Project.ID) -> Image? {
        custom[project]
    }

    private func save() {
        let saved = Dictionary(uniqueKeysWithValues: choices.map { ($0.key.uuidString, $0.value) })
        defaults.set(try? JSONEncoder().encode(saved), forKey: Self.choicesKey)
    }

    private func cacheURL(for project: Project.ID) -> URL {
        directory.appending(path: "detected-\(project.uuidString).png")
    }

    private func customURL(for project: Project.ID) -> URL {
        directory.appending(path: "custom-\(project.uuidString).png")
    }

    private func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static func image(fromPNGAt url: URL) -> Image? {
        (try? Data(contentsOf: url)).flatMap(image(fromPNG:))
    }

    private static func image(fromPNG data: Data) -> Image? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        // Pixels at 4x the 16pt avatar, so it's sharp on every display.
        return Image(decorative: image, scale: CGFloat(ProjectIconResolver.pixelSize) / DS.Size.rowLeading)
    }
}

extension EnvironmentValues {
    /// The project icons to draw from; `ProjectIconStore.shared` when nothing is injected.
    @Entry var projectIconStore: ProjectIconStore?
}
