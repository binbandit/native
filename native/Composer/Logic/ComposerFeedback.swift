import Foundation

/// What just happened to the user's last action in the composer, shown for a moment where they
/// took it (docs/product-quality.md: every action says what it did).
struct ComposerFeedback: Equatable, Identifiable {
    enum Tone {
        case notice, problem
    }

    let id = UUID()
    let tone: Tone
    let message: String
    var duration: Duration { .seconds(4) }

    init(tone: Tone, message: String) {
        self.tone = tone
        self.message = message
    }

    static func blocked(_ reason: String) -> ComposerFeedback {
        ComposerFeedback(tone: .problem, message: reason)
    }

    static func failed(_ error: any Error) -> ComposerFeedback {
        ComposerFeedback(tone: .problem, message: "Couldn’t send: \(error.localizedDescription)")
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
