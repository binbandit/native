import SwiftUI

extension FocusedValues {
    /// Draft commands must not enable actions on a task that does not exist yet.
    @Entry var composeDraft: SessionModel?
}
