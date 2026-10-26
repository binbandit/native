import Foundation
import NativePolicy

/// Files access stays local and never searches or mounts a stale bookmark's location.
nonisolated enum PlatformFolderAccess {
    enum Failure: Equatable, Sendable {
        case notFolder, unreadable, missing, notAllowed

        func message(for name: String) -> String {
            switch self {
            case .notFolder: "Choose a folder to add a project."
            case .unreadable: "Native can’t read \(name). Choose Folder…"
            case .missing: "Can’t find \(name). Locate Folder…"
            case .notAllowed: "Only approved folders can be added."
            }
        }
    }

    struct Resolved: Sendable {
        let original: URL
        let url: URL
        let hasSecurityScope: Bool
        let failure: Failure?
    }

    static func bookmark(_ url: URL) -> Data? {
        #if os(macOS)
        try? url.bookmarkData(options: [.withSecurityScope])
        #else
        try? url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    static func resolve(_ data: Data) throws -> URL {
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI, .withoutMounting]
        #else
        let options: URL.BookmarkResolutionOptions = [.withoutUI, .withoutMounting]
        #endif
        let url = try URL(resolvingBookmarkData: data, options: options, bookmarkDataIsStale: &stale)
        if stale { throw CocoaError(.fileReadNoPermission) }
        return url
    }

    static func inspect(_ urls: [URL], policy: NativePolicy) async -> [Resolved] {
        await Task.detached(priority: .userInitiated) {
            let roots = policy.foldersAllowedRoots?.map {
                URL(filePath: $0).resolvingSymlinksInPath().standardizedFileURL.path
            }
            return urls.map { url in
                guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else {
                    return Resolved(
                        original: url, url: url, hasSecurityScope: false, failure: .notFolder)
                }
                let scoped = url.startAccessingSecurityScopedResource()
                let canonical = url.resolvingSymlinksInPath().standardizedFileURL
                var failure: Failure?
                do {
                    let values = try canonical.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isReadableKey])
                    if values.isDirectory != true || values.isPackage == true {
                        failure = .notFolder
                    } else if values.isReadable == false {
                        failure = .unreadable
                    } else if !policy.allowsFolder(canonical.path, canonicalRoots: roots) {
                        failure = .notAllowed
                    }
                } catch {
                    let error = error as NSError
                    failure =
                        error.code == NSFileReadNoPermissionError
                        ? .unreadable : .missing
                }
                if failure != nil, scoped { url.stopAccessingSecurityScopedResource() }
                return Resolved(
                    original: url, url: canonical, hasSecurityScope: scoped && failure == nil, failure: failure)
            }
        }.value
    }
}
