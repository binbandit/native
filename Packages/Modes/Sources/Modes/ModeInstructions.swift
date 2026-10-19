import ACP
import Foundation

/// The instructions a mode sends its agent, once: ahead of the first prompt after the mode is
/// picked or changed (`PromptPreamble`), never repeated while the agent already has them.
public enum ModeInstructions {
    /// What goes ahead of the agent's next prompt for `mode`, given the instructions it had last
    /// (`delivered`, read from the transcript): nil when it has these already, or when it's never
    /// had any and the mode (Build) needs none.
    public static func preamble(
        for mode: Mode, _ resolution: ModeResolution, delivered: PromptPreamble.Marker?
    ) -> PromptPreamble? {
        let instructions = instructions(for: mode, resolution)
        let marker = PromptPreamble.Marker(
            id: markerID(mode, instructions: instructions), label: mode.label, symbol: mode.symbol)
        guard marker.id != delivered?.id, let body = body(for: mode, instructions, previous: delivered) else {
            return nil
        }
        return PromptPreamble(marker: marker, instructions: body)
    }

    /// The mode a delivered marker stands for.
    public static func mode(of marker: PromptPreamble.Marker) -> Mode.ID {
        Mode.ID(rawValue: String(marker.id.prefix { $0 != "#" }))
    }

    /// What the agent is told to do in the mode on this agent.
    private static func instructions(for mode: Mode, _ resolution: ModeResolution) -> String {
        var instructions =
            mode.id == .plan && resolution.usesAgentPlanMode
            ? Mode.agentPlanInstructions : mode.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty, resolution.isReadOnlyUnenforced {
            instructions +=
                "\n\nNative couldn't make your permissions read-only, so this rests on you: don't edit files or run commands that change anything."
        }
        return instructions
    }

    private static func body(for mode: Mode, _ instructions: String, previous: PromptPreamble.Marker?) -> String? {
        guard !instructions.isEmpty else {
            // Back to working normally: only worth saying when other instructions came before.
            guard let previous, Self.mode(of: previous) != mode.id else { return nil }
            return "The user switched this task back to \(mode.label) in Native, so the instructions from "
                + "\(previous.label) no longer apply. Work as you normally would."
        }
        let replacing = previous.map { Self.mode(of: $0) == mode.id ? "" : ", in place of \($0.label)" } ?? ""
        return "The user put this task in \(mode.label) in Native\(replacing). Work this way until a later message "
            + "says the mode changed:\n\n\(instructions)"
    }

    /// The mode's id and a digest of its instructions, so instructions edited since they went out
    /// are sent again.
    private static func markerID(_ mode: Mode, instructions: String) -> String {
        guard !instructions.isEmpty else { return mode.id.rawValue }
        // FNV-1a: stable across launches, unlike `Hasher`.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in instructions.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return "\(mode.id.rawValue)#\(String(hash, radix: 16))"
    }
}
