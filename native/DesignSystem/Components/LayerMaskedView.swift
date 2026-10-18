import QuartzCore
import SwiftUI

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// A view SwiftUI draws once, shown through a Core Animation mask that animates on its own in the
/// render server: for animations that run for as long as something works or shows (the dot-grid
/// loaders, the shimmer on running work, the night sky). A SwiftUI animation that never stops
/// re-renders the whole window every frame; one loader cost half a CPU core and 225 MB of graphics
/// memory for as long as an agent worked.
///
/// The content keeps its environment, so it draws in the foreground style and fonts it's given.
/// The view is as flexible as the space it's offered and never takes clicks. The mask counts y down,
/// as SwiftUI does, and on the Mac its animations pause while the window is hidden, minimized or
/// covered.
struct LayerMaskedView<Content: View, Mask: CALayer>: View {
    let content: Content
    let makeMask: () -> Mask
    /// Brings the mask up to date with the view, on every update.
    var update: (Mask) -> Void = { _ in }

    var body: some View {
        LayerMaskedRepresentable(content: content, makeMask: makeMask, update: update)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#if canImport(AppKit)
private struct LayerMaskedRepresentable<Content: View, Mask: CALayer>: NSViewRepresentable {
    let content: Content
    let makeMask: () -> Mask
    let update: (Mask) -> Void

    func makeNSView(context: Context) -> LayerMaskedHost<Mask> {
        let host = LayerMaskedHost(content: root(in: context.environment), mask: makeMask())
        update(host.maskLayer)
        return host
    }

    func updateNSView(_ host: LayerMaskedHost<Mask>, context: Context) {
        host.content = root(in: context.environment)
        update(host.maskLayer)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LayerMaskedHost<Mask>, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    private func root(in environment: EnvironmentValues) -> AnyView {
        AnyView(content.environment(\.self, environment))
    }
}

final class LayerMaskedHost<Mask: CALayer>: NSView {
    let maskLayer: Mask
    private let hosting: NSHostingView<AnyView>
    private var occlusionObserver: (any NSObjectProtocol)?

    var content: AnyView {
        get { hosting.rootView }
        set { hosting.rootView = newValue }
    }

    init(content: AnyView, mask: Mask) {
        maskLayer = mask
        hosting = NSHostingView(rootView: content)
        super.init(frame: .zero)
        // Sized by this view's frame, never by what it hosts.
        hosting.sizingOptions = []
        wantsLayer = true
        addSubview(hosting)
        // AppKit's layers count y up; the masks are laid out as SwiftUI lays out, y down.
        mask.isGeometryFlipped = true
        layer?.mask = mask
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        hosting.frame = bounds
        maskLayer.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
        occlusionObserver = window.map { window in
            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.followVisibility() }
            }
        }
        followVisibility()
    }

    private func followVisibility() {
        maskLayer.setAnimationsPaused(window?.occlusionState.contains(.visible) != true)
    }
}
#else
private struct LayerMaskedRepresentable<Content: View, Mask: CALayer>: UIViewRepresentable {
    let content: Content
    let makeMask: () -> Mask
    let update: (Mask) -> Void

    func makeUIView(context: Context) -> LayerMaskedHost<Mask> {
        let host = LayerMaskedHost(content: root(in: context.environment), mask: makeMask())
        update(host.maskLayer)
        return host
    }

    func updateUIView(_ host: LayerMaskedHost<Mask>, context: Context) {
        host.content = root(in: context.environment)
        update(host.maskLayer)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: LayerMaskedHost<Mask>, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    private func root(in environment: EnvironmentValues) -> AnyView {
        AnyView(content.environment(\.self, environment))
    }
}

/// The system stops rendering, and these animations with it, while the app is in the background.
final class LayerMaskedHost<Mask: CALayer>: UIView {
    let maskLayer: Mask
    private let hosting: UIHostingController<AnyView>

    var content: AnyView {
        get { hosting.rootView }
        set { hosting.rootView = newValue }
    }

    init(content: AnyView, mask: Mask) {
        maskLayer = mask
        hosting = UIHostingController(rootView: content)
        super.init(frame: .zero)
        hosting.sizingOptions = []
        hosting.view.backgroundColor = .clear
        addSubview(hosting.view)
        layer.mask = mask
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hosting.view.frame = bounds
        maskLayer.frame = bounds
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        false
    }
}
#endif

extension CALayer {
    /// Stops the layer's animations where they are, or lets them run on from there.
    nonisolated func setAnimationsPaused(_ isPaused: Bool) {
        if isPaused, speed != 0 {
            let now = convertTime(CACurrentMediaTime(), from: nil)
            speed = 0
            timeOffset = now
        } else if !isPaused, speed == 0 {
            let pausedAt = timeOffset
            speed = 1
            timeOffset = 0
            beginTime = 0
            beginTime = convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        }
    }
}
