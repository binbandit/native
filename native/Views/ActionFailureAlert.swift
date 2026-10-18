import SwiftUI

extension View {
    /// Says why an action the user just took failed (`AppModel.actionFailure`). Background failures
    /// never come here; they stay with their project (`ProjectProblem`).
    func actionFailureAlert() -> some View {
        modifier(ActionFailureAlert())
    }
}

private struct ActionFailureAlert: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.alert(
            model.actionFailure?.title ?? "",
            isPresented: Binding(get: { model.actionFailure != nil }, set: { if !$0 { model.actionFailure = nil } }),
            presenting: model.actionFailure
        ) { _ in
            Button("OK") {}
        } message: { failure in
            Text(failure.message)
        }
    }
}
