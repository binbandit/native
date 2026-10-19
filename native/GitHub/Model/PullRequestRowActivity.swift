/// What the list is doing to a pull request, shown on its row: so an action started from the list
/// says it's under way, that it worked, or why it didn't.
enum PullRequestRowActivity: Equatable {
    case working(String)
    case done(String)
    case failed(String)
}
