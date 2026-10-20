import NativeAutomation
import SwiftUI

/// A template in the Automations page, in the same card style as the workflow picker's.
struct AutomationTemplateCard: View {
    let template: AutomationTemplate
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        Button(action: action) {
            HStack(alignment: .top, spacing: DS.Space.md) {
                Image(systemName: template.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextSecondary)
                    .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                    .background(.dsSurfaceSunken, in: .circle)
                    .overlay { Circle().strokeBorder(.dsSeparator, lineWidth: 1) }
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(template.name)
                        .font(.dsCalloutMedium)
                        .foregroundStyle(.dsTextPrimary)
                    Text(template.summary)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextSecondary)
                        .lineLimit(3, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(
                        template.triggers.first?.summary ?? "Manual",
                        systemImage: template.triggers.first?.systemImage ?? "hand.tap"
                    )
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
                    .padding(.top, DS.Space.sm)
                }
                .tracking(DS.Tracking.tight)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DS.Space.lg)
            .background(isHovered ? Color.dsHover : .dsSurface, in: shape)
            .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Template cards") {
    DSPreviewPair {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: DS.Space.md)], spacing: DS.Space.md) {
            ForEach(AutomationTemplate.all) { template in
                AutomationTemplateCard(template: template) {}
            }
        }
        .frame(width: 700)
    }
}
#endif
