import GitHub

/// A line comment the user is writing, before it goes into the pending review or out on its own.
struct ReviewCommentDraft: Hashable {
    var anchor: ReviewAnchor
    var body: String = ""
    /// The commented lines as they read now, for "Suggest a Change".
    var lines: String
}
