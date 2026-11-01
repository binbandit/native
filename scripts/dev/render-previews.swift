import AppKit
import CoreGraphics
import SwiftUI

// Compiled with the selected view sources. The Python driver inserts their preview builders.
@main
@MainActor
private struct NativePreviewRenderer {
    private static func previewEntries() -> [(String, () -> AnyView)] {
        fatalError("PREVIEW_ENTRIES")
    }

    static func main() throws {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        guard session["CGSSessionScreenIsLocked"] as? Bool != true else {
            throw NSError(
                domain: "NativePreviewRenderer", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "screen locked; UI verification is pending"
                ])
        }
        if FileManager.default.isExecutableFile(atPath: "/tmp/native-tools/screenlocked") {
            let check = Process()
            check.executableURL = URL(fileURLWithPath: "/tmp/native-tools/screenlocked")
            let output = Pipe()
            check.standardOutput = output
            try check.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            check.waitUntilExit()
            if String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "locked" {
                throw NSError(
                    domain: "NativePreviewRenderer", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "screen locked; UI verification is pending"
                    ])
            }
        }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let arguments = CommandLine.arguments
        let output = URL(fileURLWithPath: arguments[1])
        let width = Double(arguments[2]) ?? 800
        let height = Double(arguments[3]) ?? 600
        let previews: [(String, () -> AnyView)] = previewEntries()
        for (index, preview) in previews.enumerated() {
            for scheme in [ColorScheme.light, .dark] {
                let host = NSHostingView(
                    rootView: preview.1()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .environment(\.colorScheme, scheme))
                let window = NSWindow(
                    contentRect: NSRect(x: -20_000, y: -20_000, width: width, height: height),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = host
                defer { window.close() }
                for _ in 0..<5 {
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                    host.layoutSubtreeIfNeeded()
                }
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let appearance = scheme == .dark ? "dark" : "light"
                let path = output.appending(path: "preview-\(index)-\(appearance).png")
                try png.write(to: path)
                print("\(preview.0) [\(appearance)]: \(path.path)")
            }
        }
    }
}
