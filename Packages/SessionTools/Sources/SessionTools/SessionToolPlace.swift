/// Where a session tool lives on the session screen. A tool that's on shows a fact under the
/// title while it has something to say ("2 files +12 −3"); its place says where its pane opens.
public enum SessionToolPlace: String, CaseIterable, Codable, Sendable {
    /// Only the fact. A pane, if the tool has one, opens over the conversation from it.
    case fact
    /// Beside the conversation, or over it while the window is too narrow to read both.
    case side
    /// A tab in the workbench under the composer.
    case workbench
    /// Not on the session screen.
    case off
}
