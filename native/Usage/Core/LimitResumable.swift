import Foundation

/// A session `UsageLimits` can pick back up once a limit resets. `SessionModel` conforms.
protocol LimitResumable: AnyObject {
    var resumeReadiness: ResumeReadiness { get }
    /// Sends `prompt` as a new turn, the way the user sending it would.
    func resume(with prompt: String) async
}

enum ResumeReadiness {
    case ready
    /// Working on a turn. The user carried on by hand, so a scheduled resume would only get in the way.
    case busy
    /// Loading or disconnected: worth another try in a moment.
    case unavailable
}
