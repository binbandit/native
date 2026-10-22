import Foundation

extension LinkGrants {
    /// What both allow: a link's preapproved grants and what its device asked for. Built up from
    /// nothing, so a grant added later stays off here until it's listed.
    public func intersection(_ other: LinkGrants) -> LinkGrants {
        var both = LinkGrants()
        both.managePlugins = managePlugins && other.managePlugins
        both.manageHost = manageHost && other.manageHost
        both.runCommands = runCommands && other.runCommands
        return both
    }

    /// What a device with these grants may do, as a sentence's list: "follow and drive tasks, run
    /// commands and edit files in its projects, and install updates". The items have "and"s of their
    /// own, so the last always gets a comma. The pair command, the host's journal and Add Host all
    /// say it this way.
    public var abilities: String {
        var abilities = ["follow and drive tasks"]
        if runCommands { abilities.append("run commands and edit files in its projects") }
        if manageHost { abilities.append("install updates") }
        if managePlugins { abilities.append("turn plugins on and off") }
        guard let last = abilities.popLast() else { return "" }
        guard !abilities.isEmpty else { return last }
        return "\(abilities.joined(separator: ", ")), and \(last)"
    }
}
