import SwiftUI

struct GitChangesDismissal {
    let close: @MainActor () -> Void
}

extension EnvironmentValues {
    @Entry var gitChangesCompact = false
    @Entry var gitChangesNeutralMarkers = false
    @Entry var gitChangesClose: GitChangesDismissal? = nil
}
