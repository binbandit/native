import AppAppearance
import SwiftUI

/// The switch changes the choice; the rest of the line opens its page.
struct CelebrationRow: View {
    let event: CelebrationEvent
    var query = ""
    var flash = false
    var open: () -> Void = {}

    @Environment(CelebrationCenter.self) private var center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var flashOpacity = 0.0

    private var selection: CelebrationPreferences.Selection { center.preferences.selection(for: event.id) }
    private var occurrence: CelebrationOccurrence? { center.nextOccurrence(of: event) }
    private var ready: Bool { event.canBeChosen(on: center.today) }
    private var showing: Bool { center.resolution.active?.eventID == event.id }
    private var title: String { event.contribution.title.resolved() }
    private var alias: String? {
        guard !query.isEmpty, !title.localizedStandardContains(query) else { return nil }
        return event.contribution.aliases.first { $0.localizedStandardContains(query) }
    }

    var body: some View {
        HStack(spacing: DS.Space.lg) {
            CelebrationPreview(event: event)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .settingsText(.body)
                    .foregroundStyle(ready ? Color.dsTextPrimary : .dsTextTertiary)
                    .lineLimit(1)
                if let alias {
                    Text("Also \(alias)").settingsText(.caption).foregroundStyle(.dsTextTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.sm)
            dates.settingsText(.body).foregroundStyle(ready ? Color.dsTextSecondary : .dsTextTertiary)
                .lineLimit(1).fixedSize()
            SettingsSwitch(
                "Celebrate \(title) automatically",
                isOn: Binding(
                    get: { selection.isEnabled }, set: { center.setAutomatic($0, for: event.id) })
            )
            .disabled(!ready)
            Image(systemName: "chevron.right")
                .font(.system(size: CelebrationMetrics.chevron, weight: .medium))
                .foregroundStyle(.dsTextTertiary)
        }
        .frame(minHeight: CelebrationMetrics.rowHeight)
        .padding(.horizontal, DS.Space.xl)
        .background(.dsFill.opacity(flashOpacity))
        .background(isHovered ? Color.dsHover : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { isHovered = $0 }
        .focusable()
        .settingsFocusShape(.rect(cornerRadius: DS.Radius.row))
        .onKeyPress(.space) {
            toggle(); return .handled
        }
        .onKeyPress(.return) {
            open(); return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(accessibleDates)")
        .accessibilityValue(selection.isEnabled ? "on" : "off")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .accessibilityAction(named: "Toggle celebration", toggle)
        .accessibilityAction(named: "Open celebration", open)
        .settingsRevealTarget(CelebrationsSettingsPage.rowID(event.id))
        .task(id: flash) {
            guard flash else { return }
            flashOpacity = 1
            withAnimation(reduceMotion ? nil : CelebrationMetrics.bulkFade) { flashOpacity = 0 }
        }
    }

    private func toggle() {
        guard ready else { return }
        center.setAutomatic(!selection.isEnabled, for: event.id)
    }

    private var dates: Text {
        guard ready else {
            return Text(event.dateStatus(on: center.today) == .resolvable ? "Artwork coming" : "Dates coming")
        }
        guard let occurrence else { return Text("Dates coming") }
        if showing {
            return Text(
                "\(Text("Now").font(SettingsTextStyle.bodyMedium.font).foregroundStyle(.dsTextPrimary)) – \(CelebrationDates.shortText(CivilDayRange(day: occurrence.display.last)))"
            )
        }
        return Text(CelebrationDates.shortText(occurrence.display))
    }

    private var accessibleDates: String {
        guard let occurrence else { return "dates coming" }
        if showing {
            return "showing now until \(CelebrationDates.accessible(CivilDayRange(day: occurrence.display.last)))"
        }
        return CelebrationDates.accessible(occurrence.display)
    }
}

#if DEBUG
#Preview("Celebrations - On, off, showing, flash, alias and not ready") {
    DSPreviewPair { CelebrationPreviewGallery(.rows).settingsPreviewPage() }.environment(SettingsPresentation())
}
#endif
