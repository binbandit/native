#if DEBUG
import AppAppearance
import SwiftUI

/// The same inert states used by Xcode previews can be driven in an isolated Debug instance.
struct CelebrationPreviewGallery: View {
    let state: CelebrationPreviewFixtures.State
    @State private var center: CelebrationCenter?
    @State private var registry: PluginRegistry?

    init(_ state: CelebrationPreviewFixtures.State) {
        self.state = state
    }

    var body: some View {
        Group {
            if let center, let registry {
                content(center: center)
                    .environment(center)
                    .environment(registry)
                    .environment(\.locale, Locale(identifier: "en_AU"))
            } else {
                ProgressView()
            }
        }
        .task {
            // Fixtures mutate observable models while seeding them. Creating those models in a
            // view initializer makes the parent observe the seed writes and repeat its layout.
            guard center == nil else { return }
            registry = CelebrationPreviewFixtures.registry(state)
            center = CelebrationPreviewFixtures.center(state)
        }
    }

    @ViewBuilder private func content(center: CelebrationCenter) -> some View {
        switch state {
        case .off, .menu, .page, .pending, .offline, .empty:
            CelebrationsSettingsPage(organizationName: state == .offline ? "Northwind Federal IT" : nil)
        case .search, .noMatches:
            CelebrationsSettingsPage(initialQuery: state == .search ? "Deepavali" : "nonesuch")
        case .showing, .homeOnly, .skipped, .waiting, .failed:
            CelebrationStatusCard()
        case .yearHover:
            CelebrationYearStrip(previewHover: CelebrationID("native.christmas"))
        case .rows:
            VStack(spacing: DS.Space.lg) {
                row("halloween", center: center)
                row("diwali", center: center)
                row("bandi-chhor-divas", center: center)
                row("australia-day", center: center, flash: true)
                row("diwali", center: center, query: "Deepavali")
                ForEach(center.celebrations.filter { !$0.canBeChosen(on: center.today) }) { event in
                    CelebrationRow(event: event)
                }
            }
        case .overlaps:
            CelebrationOverlaps(overlaps: center.overlaps(within: 365))
        case .unavailableSelections:
            VStack(spacing: DS.Space.lg) {
                row("songkran", center: center)
                row("eid-al-fitr", center: center)
                row("vesak", center: center)
                row("eid-al-adha", center: center)
            }
        case .detail, .style, .unavailableDetail:
            let id: CelebrationID =
                switch state {
                case .style: CelebrationID("native.australia-day")
                case .unavailableDetail: CelebrationID("native.songkran")
                default: FirstPartyCelebrations.halloweenID
                }
            if let event = center.celebrations.first(where: { $0.id == id }) {
                CelebrationDetailPage(event: event)
            }
        case .confirmation:
            CelebrationBulkConfirmation(
                summary: "Turned on Australia Day and Easter. Christmas and New Year were already on."
            ) {}
        }
    }

    @ViewBuilder private func row(
        _ id: String, center: CelebrationCenter, query: String = "", flash: Bool = false
    ) -> some View {
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
#Preview("Celebrations - Feature off") {
    DSPreviewPair { CelebrationPreviewGallery(.off).settingsPreviewPage() }.environment(SettingsPresentation())
}
#Preview("Celebrations - Artwork and dates pending") {
    DSPreviewPair { CelebrationPreviewGallery(.pending).settingsPreviewPage() }.environment(SettingsPresentation())
}
#Preview("Celebrations - Bulk menu trigger") {
    DSPreviewPair { CelebrationPreviewGallery(.menu).settingsPreviewPage() }.environment(SettingsPresentation())
}
#Preview("Celebrations - Alias search") {
    DSPreviewPair { CelebrationPreviewGallery(.search).settingsPreviewPage() }.environment(SettingsPresentation())
}
#Preview("Celebrations - No matches") {
    DSPreviewPair { CelebrationPreviewGallery(.noMatches).settingsPreviewPage() }.environment(SettingsPresentation())
}
#Preview("Celebrations - Unavailable selections on and off") {
    DSPreviewPair { CelebrationPreviewGallery(.unavailableSelections).settingsPreviewPage() }
        .environment(SettingsPresentation())
}
#Preview("Celebrations - Unavailable selection details") {
    DSPreviewPair { CelebrationPreviewGallery(.unavailableDetail).settingsPreviewPage() }
        .environment(SettingsPresentation())
}
#endif
