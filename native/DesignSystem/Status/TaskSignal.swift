import AppAppearance
import SwiftUI

extension EnvironmentValues {
    /// A surface may opt into still signals; it can never override the system's Reduce Motion.
    @Entry var taskSignalReducedMotion = false
}

/// Native's status vocabulary on the loader's 240-unit grid. A caller may supply its own working
/// animation; every other state, its accessibility words and Reduce Motion remain shared.
public struct TaskSignal<Working: View>: View {
    public enum Placement: Sendable {
        case toolbarCount, well, sidebar, peek

        var size: CGFloat {
            switch self {
            case .toolbarCount: 12
            case .well: 13
            case .sidebar: 14
            case .peek: 15
            }
        }
    }

    let status: TaskStatus
    let isUnread: Bool
    let placement: Placement
    let attentionSince: Date?
    let unavailable: String?
    let limitReset: Date?
    let working: Working?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.taskSignalReducedMotion) private var stillSignals
    @Environment(\.dsWorkingAnimation) private var workingAnimation
    @Environment(\.scenePhase) private var scenePhase
    @State private var activatedAt: Date?
    @State private var expiredDeadline: Date?

    public init(
        status: TaskStatus, isUnread: Bool = false, placement: Placement = .sidebar,
        attentionSince: Date? = nil, unavailable: String? = nil, limitReset: Date? = nil,
        @ViewBuilder working: () -> Working
    ) {
        self.status = status
        self.isUnread = isUnread
        self.placement = placement
        self.attentionSince = attentionSince
        self.unavailable = unavailable
        self.limitReset = limitReset
        self.working = working()
    }

    private var reduceMotion: Bool { systemReduceMotion || stillSignals }

    public var body: some View {
        Group {
            if status == .working, unavailable == nil, !reduceMotion, let working {
                working
            } else {
                LayerMaskedView(content: Rectangle().fill(.foreground)) {
                    TaskSignalLayer()
                } update: { layer in
                    layer.update(
                        status: status, unread: isUnread, showsRest: placement == .well,
                        offline: unavailable != nil, reduceMotion: reduceMotion,
                        workingAnimation: workingAnimation,
                        breathUntil: expiredDeadline == breathDeadline ? nil : breathDeadline)
                }
            }
        }
        .foregroundStyle(tint)
        .frame(width: placement.size, height: placement.size)
        .opacity(unavailable == nil ? 1 : DS.Signal.offlineOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .help(label)
        .task(id: breathDeadline) {
            guard let deadline = breathDeadline else { return }
            let remaining = deadline.timeIntervalSinceNow
            if remaining > 0 {
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            }
            // CA pauses under an occluded window. The wall-clock deadline still ends the breath.
            expiredDeadline = deadline
        }
        .onChange(of: scenePhase, initial: true) { _, new in
            if new == .active { activatedAt = .now }
        }
    }

    private var breathDeadline: Date? {
        guard status.needsAttention, unavailable == nil, !reduceMotion else { return nil }
        let fresh = attentionSince?.addingTimeInterval(DS.Signal.freshDuration) ?? .distantPast
        let active = activatedAt?.addingTimeInterval(DS.Signal.activationDuration) ?? .distantPast
        return max(fresh, active)
    }

    private var tint: Color {
        if unavailable != nil { return .dsTextTertiary }
        switch status {
        case .starting, .working, .waiting: return .dsTextSecondary
        case .needsInput, .needsPermission, .needsPlanReview: return .dsAttention
        case .failed: return .dsDanger
        case .done where isUnread: return .dsAccent
        default: return .dsTextTertiary
        }
    }

    private var label: String {
        if let unavailable { return unavailable }
        if status == .limited, let limitReset {
            return "\(status.label), resets \(limitReset.formatted(date: .omitted, time: .shortened))"
        }
        return status.label
    }
}

extension TaskSignal where Working == EmptyView {
    public init(
        status: TaskStatus, isUnread: Bool = false, placement: Placement = .sidebar,
        attentionSince: Date? = nil, unavailable: String? = nil, limitReset: Date? = nil
    ) {
        self.status = status
        self.isUnread = isUnread
        self.placement = placement
        self.attentionSince = attentionSince
        self.unavailable = unavailable
        self.limitReset = limitReset
        working = nil
    }
}

#if DEBUG
#Preview("Signals - Every status, sizes, offline and Reduce Motion") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ForEach(TaskStatus.allCases, id: \.self) { status in
                HStack {
                    ForEach([12, 13, 14, 15], id: \.self) { size in
                        TaskSignal(
                            status: status, isUnread: true,
                            placement: size == 12 ? .toolbarCount : size == 13 ? .well : size == 14 ? .sidebar : .peek,
                            attentionSince: .now)
                    }
                    TaskSignal(status: status, isUnread: true).environment(\.taskSignalReducedMotion, true)
                    Text(status.label).font(.dsBody)
                }
            }
            TaskSignal(status: .working, unavailable: "On build-mac, offline since 2:14 PM")
            TaskSignal(status: .needsInput, attentionSince: .now.addingTimeInterval(-120))
        }
    }
}
#endif
