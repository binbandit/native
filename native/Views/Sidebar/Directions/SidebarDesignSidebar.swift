#if DEBUG
import SwiftUI

/// The sidebar a `-sidebarDesign` launch asked for, in place of `SidebarView`.
struct SidebarDesignSidebar: View {
    let design: SidebarDesign
    let destinations: SidebarDesignDestinations

    var body: some View {
        switch design {
        case .triage: SidebarTriageDirection(destinations: destinations)
        case .quietProjects: SidebarQuietProjectsDirection(destinations: destinations)
        case .rail: SidebarRailDirection(destinations: destinations)
        case .timeline: SidebarTimelineDirection(destinations: destinations)
        }
    }
}

extension View {
    /// Fills the instance with the `-sidebarDesignFixture` tasks once the sidebar shows.
    func sidebarDesignFixture(_ model: AppModel) -> some View {
        task {
            if let fixture = SidebarDesignFixture.launchChoice {
                await model.applySidebarDesignFixture(fixture)
            }
        }
    }
}
#endif
