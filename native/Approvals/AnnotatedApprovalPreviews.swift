import SwiftUI

#if DEBUG
#Preview("Approval - force, cache, unknown, narrow, failed, reconnecting") {
    DSPreviewPair {
        ScrollView {
            VStack(spacing: DS.Space.xl) {
                ForEach(ApprovalPreviewFixtures.commands, id: \.self) { command in
                    ApprovalPreviewFixtures.card(command: command).frame(width: 760)
                }
                ApprovalPreviewFixtures.card(command: ApprovalPreviewFixtures.commands[0]).frame(width: 360)
                ApprovalPreviewFixtures.card(
                    command: ApprovalPreviewFixtures.commands[0], options: ApprovalPreviewFixtures.distinctOptions
                ).frame(width: 760)
                ApprovalPreviewFixtures.card(
                    command: ApprovalPreviewFixtures.commands[2], options: ApprovalPreviewFixtures.distinctOptions
                ).frame(width: 760)
                ApprovalPreviewFixtures.card(
                    command: ApprovalPreviewFixtures.commands[0],
                    failure: "Couldn't send your instruction. Your words are kept. Try again."
                ).frame(width: 760)
                ApprovalPreviewFixtures.card(command: ApprovalPreviewFixtures.commands[0], sending: true)
                    .frame(width: 760)
                ApprovalPreviewFixtures.card(command: ApprovalPreviewFixtures.commands[0], isAvailable: false)
                    .frame(width: 760)
            }.padding(DS.Space.xl)
        }.frame(height: 900)
    }
}
#Preview("Approval - global ask owns the shortcut") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ApprovalPreviewFixtures.card(command: ApprovalPreviewFixtures.commands[0])
            ApprovalPreviewFixtures.card(command: ApprovalPreviewFixtures.commands[2])
        }
        .environment(\.legacyAskShortcutEnabled, false)
        .frame(width: 760)
        .padding(DS.Space.xl)
    }
}
#endif
