#if canImport(GhosttyKit) && TERMINAL_ENGINE_WIP
import AppKit
import GhosttyKit
import UniformTypeIdentifiers

/// libghostty's clipboard callbacks: pasting (⌘V), copying (⌘C, programs' OSC 52) and the
/// confirmation before pasting text that would run commands. Native's config denies programs
/// reading the clipboard, so every read here is a paste the user asked for.
enum GhosttyClipboard {
    /// A paste: hands libghostty the requested representations of the general pasteboard.
    nonisolated static func read(
        surface userdata: UnsafeMutableRawPointer?, location: ghostty_clipboard_e, state: UnsafeMutableRawPointer?,
        mimes: UnsafePointer<UnsafePointer<CChar>?>?, count: Int
    ) -> ghostty_clipboard_read_result_e {
        guard Thread.isMainThread else { return GHOSTTY_CLIPBOARD_READ_UNSUPPORTED }
        // libghostty calls on the main thread and the pointers live for the call.
        nonisolated(unsafe) let (userdata, state, mimes) = (userdata, state, mimes)
        return MainActor.assumeIsolated {
            guard location == GHOSTTY_CLIPBOARD_STANDARD,
                let surface = GhosttySurfaceView.from(userdata: userdata)?.surface
            else { return GHOSTTY_CLIPBOARD_READ_UNSUPPORTED }
            let requested = (0..<count).compactMap { index in mimes?[index].map { String(cString: $0) } }
            let contents = requested.compactMap { mime in
                pasteboardData(forMime: mime).map { (mime: mime, data: $0) }
            }
            guard !contents.isEmpty else { return GHOSTTY_CLIPBOARD_READ_UNAVAILABLE }
            complete(surface, contents: contents, state: state, confirmed: false)
            return GHOSTTY_CLIPBOARD_READ_STARTED
        }
    }

    /// Asks before pasting text that libghostty considers unsafe (it would run commands at a
    /// prompt without bracketed paste).
    nonisolated static func confirmRead(
        surface userdata: UnsafeMutableRawPointer?, confirm: UnsafePointer<ghostty_clipboard_confirm_s>?,
        state: UnsafeMutableRawPointer?, request: ghostty_clipboard_request_e
    ) {
        guard Thread.isMainThread else { return }
        nonisolated(unsafe) let (userdata, confirm, state) = (userdata, confirm, state)
        MainActor.assumeIsolated {
            guard let view = GhosttySurfaceView.from(userdata: userdata), let surface = view.surface else { return }
            guard request == GHOSTTY_CLIPBOARD_REQUEST_PASTE, let confirm else {
                ghostty_surface_deny_clipboard_request(surface, state)
                return
            }
            // The confirmation borrows its contents only for this call; copy them for the alert.
            let request = confirm.pointee
            let contents: [(mime: String, data: Data)] = (0..<request.contents_len).compactMap { index in
                guard let content = request.contents?[index], let mime = content.mime else { return nil }
                let data = content.data.map { Data(bytes: $0, count: content.len) } ?? Data()
                return (String(cString: mime), data)
            }
            let text = contents.first { $0.mime == "text/plain" }.flatMap { String(data: $0.data, encoding: .utf8) }
            askToPaste(text ?? "", in: view) { approved in
                guard let surface = view.surface else { return }
                if approved {
                    complete(surface, contents: contents, state: state, confirmed: true)
                } else {
                    ghostty_surface_deny_clipboard_request(surface, state)
                }
            }
        }
    }

    /// A copy: ⌘C on a selection, or a program writing the clipboard (OSC 52).
    nonisolated static func write(
        location: ghostty_clipboard_e, contents: UnsafePointer<ghostty_clipboard_content_s>?, count: Int
    ) {
        guard Thread.isMainThread, location == GHOSTTY_CLIPBOARD_STANDARD, let contents else { return }
        let text = (0..<count).lazy.compactMap { index -> String? in
            let content = contents[index]
            guard let mime = content.mime, String(cString: mime) == "text/plain", let data = content.data else {
                return nil
            }
            return String(data: Data(bytes: data, count: content.len), encoding: .utf8)
        }.first
        guard let text else { return }
        MainActor.assumeIsolated {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private static func pasteboardData(forMime mime: String) -> Data? {
        let pasteboard = NSPasteboard.general
        switch mime {
        case "text/plain":
            // Files copied in Finder paste as their paths, the way Terminal does.
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
                as? [URL], !urls.isEmpty
            {
                return Data(urls.map { $0.path(percentEncoded: false) }.joined(separator: " ").utf8)
            }
            return pasteboard.string(forType: .string).map { Data($0.utf8) }
        default:
            guard let type = UTType(mimeType: mime) else { return nil }
            return pasteboard.data(forType: NSPasteboard.PasteboardType(type.identifier))
        }
    }

    private static func complete(
        _ surface: ghostty_surface_t, contents: [(mime: String, data: Data)], state: UnsafeMutableRawPointer?,
        confirmed: Bool
    ) {
        // libghostty copies what it needs before returning, so these buffers only live for the call.
        let mimes = contents.map { strdup($0.mime) }
        let buffers = contents.map { entry in
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: max(entry.data.count, 1), alignment: 1)
            entry.data.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: entry.data.count)
            return buffer
        }
        defer {
            mimes.forEach { free($0) }
            buffers.forEach { $0.deallocate() }
        }
        let cContents = zip(contents, zip(mimes, buffers)).map { entry, pointers in
            ghostty_clipboard_content_s(
                mime: pointers.0, data: pointers.1.assumingMemoryBound(to: CChar.self), len: entry.data.count)
        }
        cContents.withUnsafeBufferPointer { contentsBuffer in
            var complete = ghostty_clipboard_complete_s(
                contents: contentsBuffer.baseAddress, contents_len: contentsBuffer.count, available: nil,
                available_len: 0, confirmed: confirmed, remember: false)
            ghostty_surface_complete_clipboard_request(surface, &complete, state)
        }
    }

    private static func askToPaste(_ text: String, in view: NSView, completion: @escaping (Bool) -> Void) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        let alert = NSAlert()
        alert.messageText = lines > 1 ? "Paste \(lines) lines into the terminal?" : "Paste into the terminal?"
        alert.informativeText =
            "This text could run commands as soon as it's pasted. Paste only text you trust."
        alert.addButton(withTitle: "Paste")
        alert.addButton(withTitle: "Cancel")
        guard let window = view.window else {
            completion(alert.runModal() == .alertFirstButtonReturn)
            return
        }
        alert.beginSheetModal(for: window) { response in
            completion(response == .alertFirstButtonReturn)
        }
    }
}
#endif
