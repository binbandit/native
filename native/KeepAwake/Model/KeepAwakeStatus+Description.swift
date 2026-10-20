import Foundation
import NativeHostProtocol

extension KeepAwakeStatus {
    /// One plain sentence saying what keeping awake is doing right now, for every place that shows
    /// it: the status bar's tooltip and menu, the View menu and Settings.
    func description(keepsDisplayOn: Bool) -> String {
        let sentence =
            switch reason {
            case .off, .unknown:
                "Your Mac sleeps as usual."
            case .waitingForAgents:
                "Your Mac sleeps as usual until an agent starts working."
            case .agentsWorking:
                workingAgents == 1
                    ? "Keeping your Mac awake while an agent works."
                    : "Keeping your Mac awake while \(workingAgents) agents work."
            case .alwaysOn:
                "Keeping your Mac awake until you turn this off."
            case .timer:
                until.map { "Keeping your Mac awake until \(DSFormat.time($0, now: .now))." }
                    ?? "Keeping your Mac awake for a while."
            case .pausedOnBattery:
                "Paused on battery. Your Mac stays awake again once it's plugged in."
            case .pausedLowBattery:
                "Paused below 10% battery so your Mac can sleep."
            }
        return isActive && keepsDisplayOn ? sentence + " The display stays on too." : sentence
    }
}

extension Duration {
    /// "30 Minutes", "2 Hours", for the timer choices.
    var keepAwakeTitle: String {
        formatted(.units(allowed: [.hours, .minutes], width: .wide)).capitalized
    }
}
