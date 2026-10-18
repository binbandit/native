import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// The room in the window a view is in: whether more content would make it grow. A Mac window
/// grows to fit its content's minimum width; an iPad window never does.
@MainActor
final class PlatformWindowRoom {
    #if canImport(AppKit)
    fileprivate weak var window: NSWindow?
    #endif

    /// The window's width now.
    var width: CGFloat {
        #if canImport(AppKit)
        window?.frame.width ?? 0
        #else
        0
        #endif
    }

    /// Whether content `width` wider than the window's minimum would make the window grow.
    func wouldGrow(adding width: CGFloat) -> Bool {
        #if canImport(AppKit)
        guard let window else { return false }
        return window.minSize.width + width > window.frame.width
        #else
        false
        #endif
    }
}

extension View {
    /// Keeps `room` pointed at the window this view is in.
    func tracksWindowRoom(_ room: PlatformWindowRoom) -> some View {
        #if canImport(AppKit)
        background(WindowRoomReader(room: room))
        #else
        self
        #endif
    }
}

#if canImport(AppKit)
private struct WindowRoomReader: NSViewRepresentable {
    let room: PlatformWindowRoom

    func makeNSView(context: Context) -> ReaderView {
        ReaderView(room: room)
    }

    func updateNSView(_ view: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        let room: PlatformWindowRoom

        init(room: PlatformWindowRoom) {
            self.room = room
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            room.window = window
        }
    }
}
#endif
