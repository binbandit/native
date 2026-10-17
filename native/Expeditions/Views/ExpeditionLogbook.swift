#if EXPEDITIONS_WIP
import NativeAutomation
import NativeExpeditions
import SwiftUI

/// The expedition's latest logbook entries, newest first; the whole log opens with Show All.
struct ExpeditionLogbook: View {
    let expedition: Expedition
    @Binding var selected: CrewSlot?

    @Environment(ExpeditionCenter.self) private var center
    @State private var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            SectionHeader("Logbook") {
                HStack(spacing: DS.Space.sm) {
                    if expedition.log.count > Self.recent {
                        Button(showsAll ? "Show Less" : "Show All") { showsAll.toggle() }
                            .buttonStyle(.ds(.ghost))
                    }
                    #if os(macOS)
                        if let folder = center.runner.documents?.folder(for: expedition.id) {
                            Button("Show Files", systemImage: "folder") { PlatformFileBrowser.reveal(folder) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.ds(.ghost))
                                .help("Show the route, reports and logbook as files")
                        }
                    #endif
                }
            }
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(entries) { entry in
                        Button { entry.slot.map { selected = $0 } } label: {
                            HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                                Text(DSFormat.time(entry.at, now: timeline.date))
                                    .font(.dsMonoCaption)
                                    .foregroundStyle(.dsTextTertiary)
                                    .frame(width: 58, alignment: .leading)
                                Text(entry.text)
                                    .font(.dsCaption)
                                    .foregroundStyle(color(entry.kind))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(entry.slot == nil)
                    }
                }
            }
        }
    }

    private static let recent = 8

    private var entries: [LogbookEntry] {
        let newest = Array(expedition.log.reversed())
        return showsAll ? newest : Array(newest.prefix(Self.recent))
    }

    private func color(_ kind: LogbookEntry.Kind) -> Color {
        switch kind {
        case .progress, .user: .dsTextSecondary
        case .success: .dsTextPrimary
        case .attention: .dsAttention
        }
    }
}
#endif
