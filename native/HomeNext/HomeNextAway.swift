import Foundation

/// The last time the user stepped away from Native, and what was waiting when they came back.
/// Counted on this device from the tasks Home already shows; it is never sent anywhere.
struct HomeNextAway: Equatable {
    let start: Date
    let end: Date
    var finished = 0
    var asked = 0
    var failed = 0

    /// Shorter absences are ordinary switching between apps, not news.
    static let minimumLength: TimeInterval = 15 * 60

    var isNews: Bool { finished + asked + failed > 0 }

    /// "While you were away, 12:05 to 2:21 PM: 2 finished, 3 asked for you, 1 failed."
    var sentence: String {
        let parts = [
            finished > 0 ? "\(finished) finished" : nil,
            asked > 0 ? "\(asked) asked for you" : nil,
            failed > 0 ? "\(failed) failed" : nil,
        ]
        .compactMap(\.self)
        return "While you were away, \(span): \(parts.joined(separator: ", "))."
    }

    /// "12:05 to 2:21 PM": a shared day period is said once, as people write it.
    var span: String {
        var from = start.formatted(date: .omitted, time: .shortened)
        let to = end.formatted(date: .omitted, time: .shortened)
        let period = String(to.reversed().prefix { !$0.isNumber }.reversed())
        if period.contains(where: \.isLetter), from.hasSuffix(period) {
            from = String(from.dropLast(period.count))
        }
        return "\(from) to \(to)"
    }

    /// Whether `date` happened while the user was away.
    func contains(_ date: Date?) -> Bool {
        guard let date else { return false }
        return date >= start && date <= end
    }
}
