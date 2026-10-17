import SwiftUI

/// Next steps after a turn, offered as pills above the editor until the user starts typing.
struct NextStepsSection: View {
    let steps: [ComposerNextStep]

    var body: some View {
        HStack(spacing: DS.Composer.controlSpacing) {
            Text("Next")
                .font(.dsBody)
                .foregroundStyle(.dsTextTertiary)
            ForEach(steps) { step in
                Button(step.title, systemImage: step.systemImage) {
                    step.action()
                }
                .buttonStyle(.pill)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Composer.controlsInset)
    }
}
