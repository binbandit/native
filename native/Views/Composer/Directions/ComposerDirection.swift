#if DEBUG
import Foundation

/// How the composer could look: a DEBUG-only prototype for choosing a direction, picked with
/// `-composerDesign a|b|c|d`. Without the argument the composer is today's. Every direction drives the
/// same session through `ComposerView`'s actions; only the arrangement differs.
enum ComposerDirection: String, CaseIterable {
    /// Just the text, with the settings as one line of plain facts that open in place.
    case quiet = "a"
    /// A command line: `/` and `@` first, settings set by typing, approvals answered by keys.
    case command = "b"
    /// The draft is the next message: a bubble carrying its settings as chips, kept once sent.
    case message = "c"
    /// One surface that changes with the moment: drafting, a running turn, an approval.
    case moment = "d"

    /// The direction this launch asked for, if any.
    static let launchChoice: Self? = UserDefaults.standard.string(forKey: "composerDesign").flatMap(
        Self.init(rawValue:))

    /// A file to attach once at launch, so the attachment state can be shown without a file picker:
    /// `-composerDesignAttach /path/to/file`.
    static let launchAttachment: URL? = UserDefaults.standard.string(forKey: "composerDesignAttach").map {
        URL(fileURLWithPath: $0)
    }

    /// Whether the composer answers approvals itself, so the transcript's card keeps only the details.
    static var answersApprovals: Bool {
        launchChoice == .moment
    }

    /// Whether sent messages show the settings they went out with.
    static var showsMessageSettings: Bool {
        launchChoice == .message
    }
}
#endif
