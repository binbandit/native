import Foundation

/// Calls back when the user's Ghostty config changes on disk: a file edited in place, saved by
/// an editor that replaces it, created, or removed. It watches the files and the folders they're
/// in, and waits for writes to settle so one save is one reload.
final class TerminalConfigWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    private let onChange: () -> Void

    /// How long to wait after the last change; editors write a file in several steps.
    private static let settle: DispatchTimeInterval = .milliseconds(250)

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    isolated deinit {
        stop()
    }

    /// Watches `files` (existing or not) and their folders, replacing what was watched before.
    func watch(_ files: [URL]) {
        stop()
        let folders = Set(files.map { $0.deletingLastPathComponent() })
        for url in Set(files).union(folders) {
            let descriptor = open(url.path(percentEncoded: false), O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename, .attrib], queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.changed() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        pending?.cancel()
        pending = nil
        sources.forEach { $0.cancel() }
        sources = []
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle, execute: work)
    }
}
