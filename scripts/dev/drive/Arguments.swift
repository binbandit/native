import Foundation

/// A command's arguments: positionals in order, `--option value` pairs and bare `--flags`. `--`
/// ends the options, for a value that starts with dashes.
struct Arguments {
    private(set) var positional: [String] = []
    private var options: [String: String] = [:]
    private var flags: Set<String> = []

    init(_ raw: [String], options known: Set<String> = [], flags allowed: Set<String> = []) throws(DriveError) {
        var index = 0
        while index < raw.count {
            let argument = raw[index]
            index += 1
            if argument == "--" {
                positional += raw[index...]
                break
            }
            guard argument.hasPrefix("--") else {
                positional.append(argument)
                continue
            }
            let name = String(argument.dropFirst(2))
            if allowed.contains(name) {
                flags.insert(name)
            } else if known.contains(name) {
                guard index < raw.count else { throw DriveError("--\(name) needs a value", code: 2) }
                options[name] = raw[index]
                index += 1
            } else {
                throw DriveError("unknown option \(argument)", code: 2)
            }
        }
    }

    func has(_ flag: String) -> Bool {
        flags.contains(flag)
    }

    func string(_ name: String) -> String? {
        options[name]
    }

    func number(_ name: String) throws(DriveError) -> Double? {
        guard let text = options[name] else { return nil }
        guard let value = Double(text) else { throw DriveError("--\(name) takes a number, not \(text)", code: 2) }
        return value
    }

    /// Exactly `count` positionals, or a usage error naming what's expected.
    func expect(_ count: ClosedRange<Int>, _ usage: String) throws(DriveError) {
        guard count.contains(positional.count) else { throw DriveError("usage: drive.sh <name> \(usage)", code: 2) }
    }
}
