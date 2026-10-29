import SwiftUI

extension View {
    func diffCommentsTrackingShift(_ isDown: Binding<Bool>) -> some View {
        #if os(macOS)
        onModifierKeysChanged(mask: .shift) { _, keys in isDown.wrappedValue = keys.contains(.shift) }
        #else
        self
        #endif
    }
}
