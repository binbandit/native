import CoreGraphics
import Foundation

/// Whether the Mac's screen is locked. While it is, windows aren't laid out or drawn: screenshots
/// fail, and the accessibility tree of an undrawn window can be incomplete, so nothing seen then is a
/// finding. Never try to unlock or wake it.
enum Screen {
    static var isLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    static let lockedWarning =
        "the screen is locked: windows aren't laid out, so what this reads may be incomplete; report nothing seen now"
}
