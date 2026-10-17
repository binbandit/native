import Foundation

/// Something about a provider's limit worth telling the user outside the app.
enum LimitAlert: Hashable {
    /// `sessions` are the ones the limit stopped, which "Resume at Reset" would pick back up.
    case reached(ProviderLimit, sessions: [LimitTarget])
    case warning(ProviderLimit)
    /// The limit of a snoozed provider reset; nothing was sent.
    case availableAgain(ProviderLimit)
    /// A scheduled resume couldn't find its session.
    case resumeFailed(LimitTarget)
}

/// What the user chose on an alert.
enum LimitAlertAction: Hashable {
    case resumeAtReset(AgentDefinition.ID)
    case snoozeUntilReset(AgentDefinition.ID)
    case show(LimitTarget)
}

/// Delivers alerts, and reports what the user picked on them.
protocol LimitAlerting: AnyObject {
    var onAction: ((LimitAlertAction) -> Void)? { get set }
    func post(_ alert: LimitAlert) async
}
