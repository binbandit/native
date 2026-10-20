import SessionTools
import SwiftUI

/// A place's tabs: a tab per tool, or each of its own tabs for a tool that has several (every
/// shell and every run is a tab), with + after a tool's tabs where it can add one.
struct SessionToolsStrip: View {
    let tools: [SessionToolContribution]
    /// The tool the place shows, if it's open.
    let open: SessionToolID?
    let context: (SessionToolContribution) -> SessionToolContext
    let select: (SessionToolID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: DS.Space.xxs) {
                ForEach(tools) { tool in
                    if let items = tool.tabs?(context(tool)) {
                        ForEach(items) { item in
                            SessionToolTab(
                                title: item.title, systemImage: item.systemImage, accessory: item.accessory,
                                isSelected: open == tool.id && item.isSelected, close: item.close, action: item.select)
                        }
                        if let newTab = tool.newTab {
                            IconButton("New \(tool.title) Tab", systemImage: "plus") { newTab(context(tool)) }
                        }
                    } else {
                        SessionToolTab(
                            title: tool.title, systemImage: tool.systemImage,
                            accessory: tool.fact(context(tool))?.accessory, isSelected: open == tool.id
                        ) {
                            select(tool.id)
                        }
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }
}
