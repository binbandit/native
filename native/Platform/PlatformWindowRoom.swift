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

    /// The narrowest the window's content lets it be now.
    var minWidth: CGFloat {
        #if canImport(AppKit)
        window?.minSize.width ?? 0
        #else
        0
        #endif
    }

    /// Whether content `width` wider than the window's minimum would make the window grow.
    func wouldGrow(adding width: CGFloat) -> Bool {
        #if canImport(AppKit)
        window != nil && minWidth + width > self.width
        #else
        false
        #endif
    }
}

extension PlatformWindowRoom {
    /// Waits, a frame at a time and at most a second, for the window's layout to settle into
    /// `condition` (a column it just showed or hid counts toward its minimum until it has).
    func waitUntil(_ condition: () -> Bool) async {
        var frames = 0
        while !condition(), frames < 60 {
            try? await Task.sleep(for: .milliseconds(16))
            frames += 1
        }
    }

    /// Waits, likewise, until the window's minimum width has held still for a few frames: a column
    /// that just went keeps counting toward it for a frame or two.
    func waitUntilSettled() async {
        var last = minWidth
        var still = 0
        var frames = 0
        while still < 3, frames < 60 {
            try? await Task.sleep(for: .milliseconds(16))
            still = minWidth == last ? still + 1 : 0
            last = minWidth
            frames += 1
        }
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
