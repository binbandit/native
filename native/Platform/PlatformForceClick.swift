import SwiftUI

extension View {
    /// Pressure is optional hardware. The row's signal and context menu provide pointer and touch access.
    @ViewBuilder func onTaskForceClick(enabled: Bool, perform: @escaping () -> Void) -> some View {
        #if os(macOS)
        background { if enabled { TaskPressureReader(perform: perform) } }
        #else
        self
        #endif
    }
}

#if os(macOS)
import AppKit

private struct TaskPressureReader: NSViewRepresentable {
    let perform: () -> Void
    func makeNSView(context: Context) -> TaskPressureView { TaskPressureView() }
    func updateNSView(_ view: TaskPressureView, context: Context) { view.perform = perform }
    static func dismantleNSView(_ view: TaskPressureView, coordinator: ()) { view.stop() }
}

private final class TaskPressureView: NSView {
    var perform: () -> Void = {}
    private var monitor: Any?
    private var didFire = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.pressure, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.window else { return }
                if event.type == .leftMouseUp {
                    self.didFire = false
                } else if event.stage == 2, !self.didFire,
                    self.visibleRect.contains(self.convert(event.locationInWindow, from: nil))
                {
                    self.didFire = true
                    self.perform()
                }
            }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
#endif
