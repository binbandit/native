import AppKit

/// Fixture files travel on private pasteboards. The notification is addressed to the resolved
/// isolated process; the app delivers the drag to its real window's registered destination.
@MainActor
struct AttachmentInput {
    let instance: Instance

    func drop(target: String, paths: [String], phase: String, text: String?) throws(DriveError) {
        guard ["composer", "transcript"].contains(target), ["hover", "drop", "exit"].contains(phase) else {
            throw DriveError("drop: target composer or transcript; phase hover, drop or exit", code: 2)
        }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try write(paths: paths, to: board)
        if let text {
            board.clearContents()
            board.setString(text, forType: .string)
        }
        let token = UUID().uuidString
        let reply = AttachmentInputReply()
        let center = DistributedNotificationCenter.default()
        let observer = center.addObserver(
            forName: Notification.Name("dev.native.debug.dropAttachmentResult"), object: token, queue: .main
        ) { notification in
            let result = notification.userInfo?["result"] as? String
            MainActor.assumeIsolated { reply.value = result }
        }
        defer { center.removeObserver(observer) }
        center.postNotificationName(
            Notification.Name("dev.native.debug.dropAttachment"), object: String(instance.pid),
            userInfo: ["token": token, "target": target, "phase": phase, "pasteboard": board.name.rawValue],
            deliverImmediately: true)
        let deadline = Date(timeIntervalSinceNow: 8)
        while reply.value == nil, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        guard let result = reply.value else {
            throw DriveError("No drop reply. Launch this instance with -debugAttachmentDropChecks YES")
        }
        guard result.hasPrefix("Dropped:") || result.hasPrefix("Hover:") || result == "Exited" else {
            throw DriveError(result)
        }
        print(result)
    }

    func paste(paths: [String]) throws(DriveError) {
        let board = NSPasteboard(name: NSPasteboard.Name("dev.native.debug.attachments.\(instance.name)"))
        try write(paths: paths, to: board)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("dev.native.debug.pasteAttachment"), object: String(instance.pid),
            userInfo: ["pasteboard": board.name.rawValue], deliverImmediately: true)
        print("Posted file paste to \(instance.name)")
    }

    private func write(paths: [String], to board: NSPasteboard) throws(DriveError) {
        let items = try paths.map { path throws(DriveError) -> NSPasteboardItem in
            let url = URL(filePath: path, relativeTo: URL(filePath: FileManager.default.currentDirectoryPath))
                .standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { throw DriveError("No fixture at \(path)") }
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            // Finder-like mixed payload: the string must never become the message's text.
            item.setString(url.path, forType: .string)
            return item
        }
        board.clearContents()
        board.writeObjects(items)
    }
}

@MainActor
private final class AttachmentInputReply {
    var value: String?
}
