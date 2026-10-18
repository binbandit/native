import SwiftUI

/// The emblem in one edition, without the wordmark: what `NativeLockup` draws above "Native", and
/// what previews of an edition show. Lays out exactly like `NativeMark`; decorated editions reach
/// outside that frame without affecting layout.
public struct NativeEditionMark: View {
    let style: NativeMarkStyle

    public init(style: NativeMarkStyle) {
        self.style = style
    }

    public var body: some View {
        switch style {
        case .standard: NativeMark().fill()
        case .beta: NativeBetaMark()
        case .halloween(let edition): NativeHalloweenMark(edition: edition)
        case .diaDeMuertos(let edition): NativeMuertosMark(edition: edition)
        case .twoTone(let palette): NativeTwoToneMark(palette: palette)
        }
    }
}
