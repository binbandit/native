import SwiftUI

/// One screen, no account and no carousel: what the app is, and the one thing to do.
struct WelcomeView: View {
    let pair: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.xxl) {
            Spacer()
            NativeMark()
                .frame(width: CompanionMetrics.welcomeMark, height: CompanionMetrics.welcomeMark)
                .foregroundStyle(.dsTextPrimary)
            VStack(spacing: DS.Space.md) {
                Text("Native")
                    .font(CompanionType.largeTitle)
                    .foregroundStyle(.dsTextPrimary)
                Text("Check on your agents and answer them from anywhere. Your Mac does the work.")
                    .font(CompanionType.body)
                    .foregroundStyle(.dsTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DS.Space.xxl)
            Spacer()
            Button(action: pair) {
                Text("Pair with Your Mac")
                    .font(CompanionType.bodyMedium)
                    .frame(maxWidth: .infinity, minHeight: CompanionMetrics.pill)
            }
            .buttonStyle(.ds(.primary, size: .large))
            .accessibilityIdentifier("pairWithMac")
            Text("On your Mac: Native ▸ Settings ▸ Paired Devices ▸ Pair iPhone.")
                .font(CompanionType.caption)
                .foregroundStyle(.dsTextTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(DS.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.dsBackground)
    }
}
