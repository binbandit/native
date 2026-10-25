import Foundation

/// Reported worker details, kept separate from the activity headline and the checkout footer.
struct TaskWellIdentity {
    var model: String?
    var machine: String
    var timing: String?
    var contextFraction: Double?
    var isManaged = false
    var management: String?
}
