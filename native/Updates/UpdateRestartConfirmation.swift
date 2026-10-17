import SwiftUI

extension View {
    /// Asks before a restart that would stop working tasks (when the durable host isn't running
    /// them), offering to restart once they finish instead.
    func updateRestartConfirmation(_ controller: UpdateController, isPresented: Binding<Bool>) -> some View {
        let context = controller.restartContext()
        let tasks = context.workingTasks == 1 ? "A task is" : "\(context.workingTasks) tasks are"
        return confirmationDialog("Restart Native to update?", isPresented: isPresented, titleVisibility: .visible) {
            Button("Restart When Tasks Finish") { controller.installUpdate(.whenTasksFinish) }
                .keyboardShortcut(.defaultAction)
            Button("Restart Now", role: .destructive) { controller.installUpdate(.now) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(tasks) still working. Restarting now stops them; you can pick them up again afterwards.")
        }
    }
}
