import Experiments
import SwiftUI

/// Two experiments that change the same thing: says what happened, what Native did about it (it
/// uses the standard version) and offers to turn either one off.
struct LabsConflictBanner: View {
    let conflict: ExtensionConflict
    let catalog: ExperimentCatalog
    let turnOff: (ExperimentID) -> Void

    private var experiments: [ExperimentDescriptor] {
        conflict.sources.compactMap { source in
            switch source {
            case .experiment(let id): catalog.descriptor(for: id)
            }
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        HStack(alignment: .top, spacing: DS.Space.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.dsDanger)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text("\(experiments.map(\.title).formatted(.list(type: .and))) both change \(conflict.pointTitle)")
                    .settingsText(.bodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                Text("Native is using the standard \(conflict.pointTitle.lowercased()) until you turn one off.")
                    .settingsText(.body)
                    .foregroundStyle(.dsTextSecondary)
            }
            Spacer(minLength: DS.Space.lg)
            ForEach(experiments) { experiment in
                Button("Turn Off \(experiment.title)") { turnOff(experiment.id) }
                    .buttonStyle(.ds(.secondary, size: .medium))
            }
        }
        .padding(DS.Space.lg)
        .background(Color.dsDanger.opacity(0.06), in: shape)
        .overlay { shape.strokeBorder(Color.dsDanger.opacity(0.3), lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Labs conflict") {
    DSPreviewPair {
        if let conflict = LabsPreviewFixtures.conflict {
            LabsConflictBanner(conflict: conflict, catalog: .native, turnOff: { _ in })
                .settingsPreviewPage()
        }
    }
}
#endif
