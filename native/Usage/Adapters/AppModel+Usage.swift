import ACP
import Foundation

extension AppModel: UsageLimitsHost {
    func resumableSession(_ target: LimitTarget) async -> (any LimitResumable)? {
        let key = SessionKey(agent: target.agent, id: target.session)
        if session(key) == nil {
            await loadSession(key)
        }
        return session(key)
    }

    func show(_ target: LimitTarget) {
        selection = SessionKey(agent: target.agent, id: target.session)
    }
}
