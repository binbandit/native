#if !canImport(os)
import Foundation

/// The `os.Logger` calls ACP makes, where there's no unified log (Linux), so the call sites read the
/// same everywhere. Errors go to stderr, which a host's supervisor keeps (journald, a log file).
/// Debug messages are dropped, as the unified log only shows them to someone streaming it. Privacy
/// marks are accepted and ignored: stderr only reaches the machine's own user.
struct Logger: Sendable {
    private let label: String

    init(subsystem: String, category: String) {
        label = "\(subsystem).\(category)"
    }

    func debug(_ message: LogMessage) {}

    func error(_ message: LogMessage) {
        FileHandle.standardError.write(Data("[\(label)] error: \(message.text)\n".utf8))
    }
}

/// What `OSLogMessage` takes: string interpolation, with an optional `privacy:` on each value.
struct LogMessage: ExpressibleByStringInterpolation {
    let text: String

    init(stringLiteral value: String) {
        text = value
    }

    init(stringInterpolation: Interpolation) {
        text = stringInterpolation.text
    }

    struct Interpolation: StringInterpolationProtocol {
        fileprivate var text = ""

        init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity)
        }

        mutating func appendLiteral(_ literal: String) {
            text += literal
        }

        mutating func appendInterpolation(_ value: Any, privacy: LogPrivacy = .private) {
            text += String(describing: value)
        }
    }
}

enum LogPrivacy {
    case `public`
    case `private`
}
#endif
