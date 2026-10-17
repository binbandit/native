import Foundation

/// Whether this build of Native can show a terminal.
enum TerminalAvailability: Equatable {
    case available
    /// Built without libghostty: `scripts/build-libghostty.sh` hasn't run on this machine, or the
    /// platform has no local terminal engine yet (iPad).
    case notBuilt
    /// libghostty is in the build but didn't start.
    case failed(String)

    /// The command that builds libghostty, for the unavailable state to offer.
    static let buildCommand = "scripts/build-libghostty.sh"
}
