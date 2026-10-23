#if DEBUG
import AppAppearance
import SwiftUI

/// The same inert states used by Xcode previews can be driven in an isolated Debug instance.
struct CelebrationPreviewGallery: View {
    let state: CelebrationPreviewFixtures.State
    @State private var center: CelebrationCenter
    @State private var registry = CelebrationPreviewFixtures.registry()

    init(_ state: CelebrationPreviewFixtures.State) {
        self.state = state
        _center = State(initialValue: CelebrationPreviewFixtures.center(state))
    }

    var body: some View {
        Group {
            switch state {
            case .page, .offline, .empty:
                CelebrationsSettingsPage(organizationName: state == .offline ? "Northwind Federal IT" : nil)
            case .showing, .homeOnly, .skipped, .waiting, .failed:
                CelebrationStatusCard()
            case .yearHover:
                CelebrationYearStrip(previewHover: CelebrationID("native.christmas"))
            case .rows:
                VStack(spacing: DS.Space.lg) {
                    row("halloween")
                    row("diwali")
                    row("bandi-chhor-divas")
                    row("australia-day", flash: true)
                    row("diwali", query: "Deepavali")
                    ForEach(center.celebrations.filter { !$0.canBeChosen(on: center.today) }.prefix(2)) { event in
                        CelebrationRow(event: event)
                    }
                }
            case .overlaps:
                CelebrationOverlaps(overlaps: center.overlaps(within: 365))
            case .detail:
                if let event = center.celebrations.first(where: { $0.id == FirstPartyCelebrations.halloweenID }) {
                    CelebrationDetailPage(event: event)
                }
            case .confirmation:
                CelebrationBulkConfirmation(
                    summary: "Turned on Australia Day and Easter. Christmas and New Year were already on."
                ) {}
            }
        }
        .environment(center)
        .environment(registry)
    }

    @ViewBuilder private func row(_ id: String, query: String = "", flash: Bool = false) -> some View {
        if let event = center.celebrations.first(where: { $0.id.rawValue == "native.\(id)" }) {
            CelebrationRow(event: event, query: query)
                .background(flash ? Color.dsFill : .clear)
        }
    }
}

#Preview("Celebrations - Page") {
    DSPreviewPair { CelebrationPreviewGallery(.page).settingsPreviewPage() }.environment(SettingsPresentation())
}
#Preview("Celebrations - Offline install") {
    DSPreviewPair { CelebrationPreviewGallery(.offline).settingsPreviewPage() }.environment(SettingsPresentation())
}
#endif
