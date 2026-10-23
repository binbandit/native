#if os(macOS)
import SwiftUI

struct PlatformWindowCloseCommands: Commands {
    @State private var model = PlatformWindowCloseModel()

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Close") { model.close() }
                .keyboardShortcut("w")
                .modifierKeyAlternate(.option) {
                    Button("Close All") { model.closeAll() }
                        .keyboardShortcut("w", modifiers: [.command, .option])
                }
                .disabled(!model.canClose)
        }
    }
}
#endif
