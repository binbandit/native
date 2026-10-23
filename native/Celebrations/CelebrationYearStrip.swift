import AppAppearance
import SwiftUI

/// One year of chosen dates, with decorative seasons quieter than observance days.
struct CelebrationYearStrip: View {
    var reveal: (CelebrationID) -> Void = { _ in }
    var revealMonth: (CivilDate) -> Void = { _ in }
    var chooseCountry: (String) -> Void = { _ in }
    var previewHover: CelebrationID?

    @Environment(CelebrationCenter.self) private var center
    @Environment(\.locale) private var locale
    @State private var hovered: CelebrationID?

    private var chosen: [CelebrationEvent] { center.priority }
    private var occurrences: [(event: CelebrationEvent, occurrence: CelebrationOccurrence)] {
        chosen.compactMap { event in
            center.nextOccurrence(of: event).map { (event, $0) }
        }.filter { $0.occurrence.display.first < center.today.adding(days: 365) }
            .sorted { $0.occurrence.display.first < $1.occurrence.display.first }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.md) {
                Text("Your year").foregroundStyle(.dsTextTertiary)
                Spacer(minLength: 0)
                if !chosen.isEmpty {
                    Text(
                        "\(Text("\(chosen.count) chosen").font(SettingsTextStyle.caption.font.weight(.medium)).foregroundStyle(.dsTextSecondary))\(nextText)"
                    )
                    .foregroundStyle(.dsTextTertiary).lineLimit(1)
                }
            }
            .settingsText(.caption)
            .padding(.horizontal, DS.Space.xl)
            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)
                let placements = placements(width: width)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(.dsSeparator).frame(height: CelebrationMetrics.hairline)
                        .offset(y: CelebrationMetrics.yearBaseline)
                    ForEach(placements) { item in
                        span(item.occurrence.display, width: width, core: false)
                        span(item.occurrence.core, width: width, core: true)
                    }
                    ForEach(months, id: \.self) { month in
                        let x = position(month, width: width)
                        Rectangle().fill(.dsTextQuaternary)
                            .frame(width: CelebrationMetrics.hairline, height: CelebrationMetrics.yearTick)
                            .offset(x: x, y: CelebrationMetrics.yearBaseline + CelebrationMetrics.hairline)
                        if x >= CelebrationMetrics.yearTodayClearance {
                            Button {
                                revealMonth(month)
                            } label: {
                                HStack(spacing: CelebrationMetrics.yearNumberGap) {
                                    Text(month.start(in: .current), format: .dateTime.month(.abbreviated))
                                        .font(CelebrationMetrics.yearLabelFont).foregroundStyle(.dsTextTertiary)
                                    if month.month == 1 {
                                        Text(String(month.year % 100))
                                            .font(CelebrationMetrics.yearNumberFont).foregroundStyle(.dsTextQuaternary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(CelebrationDates.month(month, includeYear: true))
                            .offset(x: x, y: CelebrationMetrics.yearBaseline + CelebrationMetrics.yearLabelOffset)
                        }
                    }
                    Text("Today").font(CelebrationMetrics.yearLabelFont.weight(.medium))
                        .foregroundStyle(.dsTextPrimary)
                        .offset(y: CelebrationMetrics.yearBaseline + CelebrationMetrics.yearLabelOffset)
                    // All stems are behind all icons, including icons in the lower lanes.
                    ForEach(placements) { item in
                        Rectangle().fill(.dsTextQuaternary)
                            .frame(
                                width: CelebrationMetrics.hairline,
                                height: CelebrationMetrics.yearBaseline - item.y - CelebrationMetrics.yearIcon
                            )
                            .offset(x: item.x, y: item.y + CelebrationMetrics.yearIcon)
                    }
                    ForEach(placements) { item in
                        icon(item)
                    }
                    if chosen.isEmpty {
                        emptyYear.frame(maxWidth: .infinity)
                            .padding(.top, DS.Space.lg)
                    }
                }
            }
            .frame(height: CelebrationMetrics.yearHeight)
            .padding(.horizontal, DS.Space.xl)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your year, \(chosen.count) celebrations")
    }

    private var nextText: String {
        guard let next = occurrences.first(where: { $0.occurrence.display.first > center.today }) else { return "" }
        return
            " · next, \(next.event.contribution.title.resolved()) on \(CelebrationDates.shortText(CivilDayRange(day: next.occurrence.display.first)))"
    }

    private var emptyYear: some View {
        VStack(spacing: DS.Space.md) {
            Text("Start with your region's public holidays. Nothing turns on until you click.")
                .settingsText(.caption).foregroundStyle(.dsTextTertiary)
            if let region = locale.region?.identifier,
                let count = CelebrationPreferences.publicHolidayCountries(in: center.celebrations)[region]
            {
                Button("Turn On \(CelebrationCountryMenu.name(region))'s \(count) Holidays") { chooseCountry(region) }
                    .buttonStyle(.settings)
            } else {
                CelebrationCountryMenu(
                    counts: CelebrationPreferences.publicHolidayCountries(in: center.celebrations),
                    onPick: chooseCountry)
            }
        }
    }

    private var months: [CivilDate] {
        (1..<365).compactMap { offset in
            let date = center.today.adding(days: offset)
            return date.day == 1 ? date : nil
        }
    }

    private func position(_ day: CivilDate, width: CGFloat) -> CGFloat {
        CGFloat(day.dayNumber - center.today.dayNumber) / 365 * width
    }

    @ViewBuilder private func span(_ days: CivilDayRange, width: CGFloat, core: Bool) -> some View {
        let start = max(0, position(days.first, width: width))
        let end = min(width, position(days.last.adding(days: 1), width: width))
        if end > start {
            Capsule().fill(core ? Color.dsTextPrimary : .dsTextTertiary)
                .frame(width: max(CelebrationMetrics.yearSpan, end - start), height: CelebrationMetrics.yearSpan)
                .offset(x: start, y: CelebrationMetrics.yearBaseline - CelebrationMetrics.hairline)
                .accessibilityHidden(true)
        }
    }

    private func icon(_ item: Placement) -> some View {
        let skipped = center.preferences.skipped.contains(item.occurrence.id)
        let current = center.resolution.active?.occurrence.id == item.occurrence.id && !skipped
        let shape = RoundedRectangle(cornerRadius: CelebrationMetrics.yearRadius)
        return Button {
            reveal(item.event.id)
        } label: {
            CelebrationPreview(event: item.event, size: CelebrationMetrics.yearIcon)
                .clipShape(shape)
                .overlay { shape.stroke(.dsSurface, lineWidth: CelebrationMetrics.yearRing) }
                .overlay {
                    if current {
                        shape.inset(by: -CelebrationMetrics.yearCurrentRingOutset)
                            .stroke(.dsTextPrimary, lineWidth: CelebrationMetrics.yearRing)
                    }
                }
                .opacity(skipped ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .dsHitTarget(CelebrationMetrics.yearIcon)
        .onHover { hovered = $0 ? item.event.id : nil }
        .accessibilityLabel(
            "\(item.event.contribution.title.resolved()), \(CelebrationDates.accessible(item.occurrence.display))"
        )
        .overlay(alignment: .bottomLeading) {
            if (hovered ?? previewHover) == item.event.id {
                Text(
                    "\(item.event.contribution.title.resolved()) · \(CelebrationDates.shortText(item.occurrence.display))"
                )
                .settingsText(.caption).foregroundStyle(.dsTextPrimary)
                .padding(.horizontal, DS.Space.sm).padding(.vertical, DS.Space.xs)
                .dsOverlayBackground(in: .rect(cornerRadius: DS.Radius.row))
                .dsShadow(.modal).fixedSize()
                .offset(y: -CelebrationMetrics.yearIcon - DS.Space.sm)
                .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .offset(x: item.x - CelebrationMetrics.yearIcon / 2, y: item.y)
        .zIndex((hovered ?? previewHover) == item.event.id ? 1 : 0)
    }

    private struct Placement: Identifiable {
        let event: CelebrationEvent
        let occurrence: CelebrationOccurrence
        let x: CGFloat
        let y: CGFloat
        var id: CelebrationID { event.id }
    }

    private func placements(width: CGFloat) -> [Placement] {
        var lanes = Array(repeating: -CGFloat.infinity, count: 3)
        return occurrences.map { event, occurrence in
            let half = CelebrationMetrics.yearIcon / 2
            let x = min(width - half, max(half, position(occurrence.display.first, width: width)))
            let lane = lanes.firstIndex { x - half > $0 + CelebrationMetrics.yearIconGap } ?? 2
            lanes[lane] = x + half
            return Placement(
                event: event, occurrence: occurrence, x: x,
                y: CelebrationMetrics.yearBaseline - CelebrationMetrics.yearStemGap
                    - CelebrationMetrics.yearIcon - CGFloat(lane) * CelebrationMetrics.yearLane)
        }
    }
}

#if DEBUG
#Preview("Celebrations - Year with hover") {
    DSPreviewPair { CelebrationPreviewGallery(.yearHover).settingsPreviewPage() }.environment(SettingsPresentation())
}
#endif
