/// A tool's verb in each tense a row needs: "Edit notes.txt" while it waits for approval or when it
/// didn't happen, "Editing notes.txt" while it runs, "Edited notes.txt" once it's done.
public struct ToolVerb: Hashable, Sendable {
    public var base: String
    public var progressive: String
    public var past: String

    public init(base: String, progressive: String, past: String) {
        self.base = base
        self.progressive = progressive
        self.past = past
    }

    public func form(for phase: ToolPhase) -> String {
        switch phase {
        case .running: progressive
        case .completed: past
        // Not done: the sentence names what was asked, and the outcome word says what happened.
        case .awaitingApproval, .failed, .cancelled, .rejected, .interrupted, .unreported: base
        }
    }

    /// The same verb with words after it in every tense: "Search" + "the web for".
    public func appending(_ words: String) -> ToolVerb {
        ToolVerb(base: "\(base) \(words)", progressive: "\(progressive) \(words)", past: "\(past) \(words)")
    }

    public static let read = ToolVerb(base: "Read", progressive: "Reading", past: "Read")
    public static let list = ToolVerb(base: "List", progressive: "Listing", past: "Listed")
    public static let edit = ToolVerb(base: "Edit", progressive: "Editing", past: "Edited")
    public static let create = ToolVerb(base: "Create", progressive: "Creating", past: "Created")
    public static let write = ToolVerb(base: "Write", progressive: "Writing", past: "Wrote")
    public static let delete = ToolVerb(base: "Delete", progressive: "Deleting", past: "Deleted")
    public static let move = ToolVerb(base: "Move", progressive: "Moving", past: "Moved")
    public static let search = ToolVerb(base: "Search", progressive: "Searching", past: "Searched")
    public static let run = ToolVerb(base: "Run", progressive: "Running", past: "Ran")
    public static let fetch = ToolVerb(base: "Fetch", progressive: "Fetching", past: "Fetched")
    public static let use = ToolVerb(base: "Use", progressive: "Using", past: "Used")
    public static let update = ToolVerb(base: "Update", progressive: "Updating", past: "Updated")
    public static let check = ToolVerb(base: "Check", progressive: "Checking", past: "Checked")
    public static let stop = ToolVerb(base: "Stop", progressive: "Stopping", past: "Stopped")
    public static let lookUp = ToolVerb(base: "Look up", progressive: "Looking up", past: "Looked up")
    public static let present = ToolVerb(base: "Present", progressive: "Presenting", past: "Presented")
    public static let start = ToolVerb(base: "Start", progressive: "Starting", past: "Started")
    public static let delegate = ToolVerb(base: "Delegate", progressive: "Delegating", past: "Delegated")
    public static let wait = ToolVerb(base: "Wait", progressive: "Waiting", past: "Waited")
    public static let send = ToolVerb(base: "Send", progressive: "Sending", past: "Sent")
}
