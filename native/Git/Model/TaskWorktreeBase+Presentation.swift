import Git

extension TaskWorktreeBase {
    var localNotice: String? {
        switch source {
        case .remote: nil
        case .local(.fetchFailed): "Couldn't fetch the latest remote changes. This task starts from the local branch."
        case .local(.disabled): "Remote fetching is turned off. This task starts from the local branch."
        case .local(.noRemote): "This branch has no remote to fetch. This task starts from the local branch."
        case .local(.detached): "This checkout has no base branch. This task starts from the local commit."
        }
    }
}
