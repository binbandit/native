import SwiftUI

// The usage views for a `SessionModel`, reading limits and breakdowns from the Usage plugin. These
// are what the composer, the session view and the sidebar place.

extension ContextIndicator where Source == SessionContextSource {
    /// The indicator for a session, reading its breakdown from the Usage plugin.
    init(session: SessionModel, style: Style = .ring, arrowEdge: Edge = .top) {
        self.init(source: SessionContextSource(session: session), style: style, arrowEdge: arrowEdge)
    }
}

extension UsageLimitBanner {
    init(session: SessionModel) {
        self.init(agent: session.agent.id, session: session.id, limits: BuiltInPlugins.usage.limits)
    }
}

extension ContextPressureBanner where Source == SessionContextSource {
    init(session: SessionModel, chrome: UsageBannerChrome = .card) {
        self.init(source: SessionContextSource(session: session), chrome: chrome)
    }
}

extension UsageLimitTranscriptCard {
    init(session: SessionModel, stop: UsageLimitStop, isLatestTurn: Bool) {
        self.init(
            stop: stop, agent: session.agent.id, agentName: session.agentName, session: session.id,
            isLatestTurn: isLatestTurn, limits: BuiltInPlugins.usage.limits)
    }
}
