import Foundation

extension KeepAwakeStatus {
    /// One plain sentence saying what keeping awake is doing right now, for every place that shows
    /// it: the status bar's tooltip and menu, the View menu and Settings.
    func description(keepsDisplayOn: Bool) -> String {
        let sentence = switch reason {
        case .off:
            "Your Mac sleeps as usual."
        case .waitingForAgents:
            "Your Mac sleeps as usual until an agent starts working."
        case .agentsWorking(let count):
            count == 1 ? "Keeping your Mac awake while an agent works." : "Keeping your Mac awake while \(count) agents work."
        case .alwaysOn:
            "Keeping your Mac awake until you turn this off."
        case .timer(let until):
            "Keeping your Mac awake until \(Self.time(until))."
        case .pausedOnBattery:
            "Paused on battery. Your Mac stays awake again once it's plugged in."
        case .pausedLowBattery:
            "Paused below 10% battery so your Mac can sleep."
        }
        return isActive && keepsDisplayOn ? sentence + " The display stays on too." : sentence
    }

    /// "Active" or "Inactive", beside the mode in Orca's menu header.
    var stateTitle: String {
        isActive ? "Active" : "Inactive"
    }

    /// "5:40 PM", or "tomorrow at 1:10 AM" past midnight.
    private static func time(_ date: Date) -> String {
        let clock = date.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDateInToday(date) ? clock : "tomorrow at \(clock)"
    }
}

extension Duration {
    /// "30 Minutes", "2 Hours", for the timer choices.
    var keepAwakeTitle: String {
        formatted(.units(allowed: [.hours, .minutes], width: .wide)).capitalized
    }
}
