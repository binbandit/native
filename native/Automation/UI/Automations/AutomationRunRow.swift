import NativeAutomation
import SwiftUI

/// One run in an automation's history: why it started, when, how it went, and what to do about it.
struct AutomationRunRow: View {
    let run: AutomationRun
    let onOpen: (() -> Void)?
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            AutomationStatusGlyph(glyph: AutomationGlyph(run: run.status))
                .padding(.top, DS.Space.xxs)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.md) {
                    Text(run.reason.label)
                        .font(.dsBodyMedium)
                        .foregroundStyle(.dsTextPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.md)
                    Text(run.status.label)
                        .font(.dsCaptionMedium)
                        .foregroundStyle(AutomationGlyph(run: run.status).tint)
                    Text(timing)
                        .font(.dsMonoCaption)
                        .monospacedDigit()
                        .foregroundStyle(.dsTextTertiary)
                }
                if let detail {
                    Text(detail)
                        .font(.dsCaption)
                        .foregroundStyle(run.status.isFailure ? .dsDanger : .dsTextSecondary)
                        .lineLimit(2)
                }
                if onOpen != nil || run.status.isOpen {
                    HStack(spacing: DS.Space.sm) {
                        if let onOpen {
                            Button("Open Run", systemImage: "arrow.right.circle", action: onOpen)
                                .buttonStyle(.ds(.ghost))
                        }
                        if run.status.isOpen {
                            Button("Stop", systemImage: "stop.fill", action: onStop)
                                .buttonStyle(.ds(.ghost))
                        }
                    }
                }
            }
        }
        .padding(DS.Space.md)
    }

    private var timing: String {
        let started = DSFormat.compactAge(run.startedAt, now: .now)
        let age = started == "now" ? "just now" : "\(started) ago"
        guard let end = run.endedAt, end > run.startedAt else { return age }
        return "\(age) · \(DSFormat.duration(end.timeIntervalSince(run.startedAt)))"
    }

    private var detail: String? {
        switch run.status {
        case .failed(let reason), .skipped(let reason): reason
        case .needsYou: "A step is waiting for you. Open the run to answer it."
        default: run.summary
        }
    }
}

private extension AutomationRunStatus {
    var isFailure: Bool {
        if case .failed = self { true } else { false }
    }
}
