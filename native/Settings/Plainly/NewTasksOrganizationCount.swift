import SwiftUI

/// How many of the values on New Tasks the organization sets, gathered from the rows that show
/// them, for the page's header and scope row.
struct NewTasksOrganizationCount: PreferenceKey {
    static let defaultValue = 0

    static func reduce(value: inout Int, nextValue: () -> Int) {
        value += nextValue()
    }
}
