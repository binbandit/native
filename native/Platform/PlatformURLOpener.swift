import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Opens web links in the user's browser: NSWorkspace on the Mac, UIApplication on iPad.
///
/// Launched with `-nativeURLOpenerLog <path>`, it appends each URL to that file instead, so an
/// automated check can follow "Open on GitHub" without opening a browser on the machine.
@MainActor
enum PlatformURLOpener {
    static let logDefaultsKey = "nativeURLOpenerLog"

    static func open(_ url: URL) {
        if let log = UserDefaults.standard.string(forKey: logDefaultsKey), !log.isEmpty {
            record(url, in: URL(filePath: log))
            return
        }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }

    private static func record(_ url: URL, in file: URL) {
        let line = Data((url.absoluteString + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
            try? handle.close()
        } else {
            try? line.write(to: file)
        }
    }
}
