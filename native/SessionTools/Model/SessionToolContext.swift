import SessionTools

/// What a tool's fact and pane are built from: the task, and its screen, which opens tools and
/// keeps each tool's own state for as long as the screen shows the task.
struct SessionToolContext {
    let session: SessionModel
    let screen: SessionToolsScreenModel
    let tool: SessionToolID

    /// The tool's state on this screen, made the first time it's asked for.
    func state<State: AnyObject>(_ make: () -> State) -> State {
        screen.state(for: tool, make)
    }

    /// Opens a tool in its place: the turn card's Review opens Changes, a run's fact the terminal.
    func open(_ id: SessionToolID) {
        screen.open(id)
    }
}
