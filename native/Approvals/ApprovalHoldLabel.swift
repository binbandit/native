import SwiftUI

struct ApprovalHoldLabel: View {
    let progress: Double
    var allowed = false
    var confirming = false
    var shortcutsEnabled = true
    var reduceMotion = false

    var body: some View {
        HStack(spacing: DS.Space.md) {
            if allowed {
                Image(systemName: "checkmark")
            } else {
                ZStack {
                    Circle().stroke(
                        .dsTextOnAccent.opacity(DS.Approval.ringTrackOpacity), lineWidth: DS.Approval.ringStroke)
                    Circle().trim(from: 0, to: progress)
                        .stroke(.dsTextOnAccent, lineWidth: DS.Approval.ringStroke)
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: DS.Approval.ringSize, height: DS.Approval.ringSize)
            }
            Text(allowed ? "Allowed" : confirming ? "Confirm Allow" : "Hold to Allow")
            if shortcutsEnabled, !allowed {
                Text("⌘Y").font(.dsMonoMicro).opacity(DS.Approval.hintOpacity)
            }
        }
        .overlay(alignment: .leading) {
            if !reduceMotion {
                GeometryReader { geometry in
                    Rectangle().fill(.dsTextOnAccent.opacity(DS.Approval.sweepOpacity))
                        .frame(width: geometry.size.width * progress)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

#if DEBUG
#Preview("Hold - rest, halfway, early release, allowed, accessible, reduced motion") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            Button {
            } label: {
                ApprovalHoldLabel(progress: 0)
            }
            Button {
            } label: {
                ApprovalHoldLabel(progress: 0.5)
            }
            Button {
            } label: {
                ApprovalHoldLabel(progress: 0.15)
            }
            Button {
            } label: {
                ApprovalHoldLabel(progress: 1, allowed: true)
            }
            Button {
            } label: {
                ApprovalHoldLabel(progress: 0, confirming: true)
            }
            Button {
            } label: {
                ApprovalHoldLabel(progress: 0.5, reduceMotion: true)
            }
        }
        .buttonStyle(ApprovalActionStyle(primary: true))
        .padding(DS.Space.xl)
    }
}
#endif
