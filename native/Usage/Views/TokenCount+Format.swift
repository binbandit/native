import ACP

extension ContextReport.TokenCount {
    /// Keeps the agent's own hedging for estimates: "~300", "< 20".
    var formatted: String {
        switch bound {
        case .exact: DSFormat.tokens(value)
        case .approximate: "~" + DSFormat.tokens(value)
        case .below: "< " + DSFormat.tokens(value)
        }
    }
}
