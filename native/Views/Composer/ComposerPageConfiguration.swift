/// Page layout changes the presentation and submit destination, keeping the editor's behavior.
struct ComposerPageConfiguration {
    var allowsFileMentions = true
    var needsFolder = false
    let start: () -> Void
    let attachmentsPending: (Bool) -> Void
}
