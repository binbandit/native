import ACP
import SwiftUI

struct HomeNextReceiptView: View {
    let receipt: HomeNextReceipt
    let openTask: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: "checkmark").foregroundStyle(.dsTextTertiary)
            Text("\(receipt.rejected ? "Rejected" : "Allowed") \(receipt.command) in \(receipt.title).")
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open Task", action: openTask).buttonStyle(.plain).foregroundStyle(.dsTextPrimary)
                .dsHitTarget(DS.Size.controlXS)
        }
        .font(.dsBody).foregroundStyle(.dsTextSecondary)
        .padding(.horizontal, DS.Space.lg)
        .frame(minHeight: DS.HomeNext.finishedHeight)
        .background(.dsHover, in: RoundedRectangle(cornerRadius: DS.Radius.card))
        .padding(.horizontal, -DS.Space.lg)
        .help("\(receipt.rejected ? "Rejected" : "Allowed") \(receipt.command) in \(receipt.title).")
        .accessibilityIdentifier("home-next-receipt")
    }
}

#if DEBUG
#Preview("Next receipt - Allowed and rejected") {
    DSPreviewPair {
        VStack {
            ForEach([false, true], id: \.self) { rejected in
                HomeNextReceiptView(
                    receipt: HomeNextReceipt(
                        task: SessionKey(agent: .init(rawValue: "codex"), id: .init("fixture")),
                        title: "Fix flaky PermissionRequestTests", command: "swift test",
                        rejected: rejected, date: .now), openTask: {})
            }
        }.padding(DS.Space.xxl).frame(width: DS.HomeNext.column)
    }
}
#endif
