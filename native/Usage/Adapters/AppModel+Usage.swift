import ACP
import Foundation

extension AppModel: UsageLimitsHost {
    func resumableSession(_ target: UsageSessionRef) async -> (any LimitResumable)? {
        let key = SessionKey(agent: target.agent, id: target.session)
        if session(key) == nil {
            await loadSession(key)
        }
        return session(key)
    }

    func show(_ target: UsageSessionRef) {
        selection = SessionKey(agent: target.agent, id: target.session)
    }
}
