import SwiftUI

// Gallery sections for the tokens.

struct GalleryColors: View {
    private static let groups: [(String, [(String, Color)])] = [
        (
            "Layers",
            [
                ("dsBackground", .dsBackground), ("dsSurface", .dsSurface), ("dsSurfaceRaised", .dsSurfaceRaised),
                ("dsSurfaceSunken", .dsSurfaceSunken), ("dsOverlay", .dsOverlay),
            ]
        ),
        ("Fills", [("dsHover", .dsHover), ("dsSelected", .dsSelected), ("dsPressed", .dsPressed)]),
        (
            "Borders",
            [
                ("dsSeparator", .dsSeparator), ("dsBorder", .dsBorder), ("dsBorderHover", .dsBorderHover),
                ("dsBorderStrong", .dsBorderStrong), ("dsBorderInner", .dsBorderInner),
            ]
        ),
        (
            "Text",
            [
                ("dsTextPrimary", .dsTextPrimary), ("dsTextSecondary", .dsTextSecondary),
                ("dsTextTertiary", .dsTextTertiary), ("dsTextQuaternary", .dsTextQuaternary),
                ("dsTextInverse", .dsTextInverse),
            ]
        ),
        (
            "Accent",
            [
                ("dsAccent", .dsAccent), ("dsAccentHover", .dsAccentHover), ("dsAccentPressed", .dsAccentPressed),
                ("dsAccentText", .dsAccentText), ("dsAccentSubtle", .dsAccentSubtle),
            ]
        ),
        (
            "Semantic",
            [
                ("dsSuccess", .dsSuccess), ("dsWarning", .dsWarning), ("dsDanger", .dsDanger),
                ("dsInfo", .dsInfo), ("dsMerged", .dsMerged), ("dsDangerFill", .dsDangerFill),
                ("dsWarningFill", .dsWarningFill), ("dsAttention", .dsAttention),
            ]
        ),
        ("Charts", [("dsChart1", .dsChart1), ("dsChart2", .dsChart2), ("dsChart3", .dsChart3)]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            ForEach(Self.groups, id: \.0) { group in
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text(group.0)
                        .font(.dsCaptionMedium)
                        .foregroundStyle(.dsTextSecondary)
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: DS.Space.md, alignment: .leading), count: 3),
                        alignment: .leading, spacing: DS.Space.md
                    ) {
                        ForEach(group.1, id: \.0) { swatch in
                            GallerySwatch(name: swatch.0, color: swatch.1)
                        }
                    }
                }
            }
        }
    }
}

private struct GallerySwatch: View {
    let name: String
    let color: Color

    @Environment(\.self) private var environment

    var body: some View {
        HStack(spacing: DS.Space.md) {
            RoundedRectangle(cornerRadius: DS.Radius.control)
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay { RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(.dsSeparator) }
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextPrimary)
                Text(hex)
                    .font(.dsMonoMicro)
                    .foregroundStyle(.dsTextTertiary)
            }
        }
    }

    private var hex: String {
        let resolved = color.resolve(in: environment)
        func channel(_ value: Float) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        let rgb = String(
            format: "#%02x%02x%02x", channel(resolved.red), channel(resolved.green), channel(resolved.blue))
        return resolved.opacity < 0.999 ? "\(rgb) \(Int((resolved.opacity * 100).rounded()))%" : rgb
    }
}

struct GalleryTypography: View {
    private static let styles: [(String, Font, String)] = [
        ("dsTitle", .dsTitle, "24 medium"), ("dsTitle2", .dsTitle2, "20 medium"), ("dsTitle3", .dsTitle3, "16 medium"),
        ("dsHeadline", .dsHeadline, "14 medium"), ("dsCalloutSemibold", .dsCalloutSemibold, "13 semibold"),
        ("dsCalloutMedium", .dsCalloutMedium, "13 medium"), ("dsCalloutBook", .dsCalloutBook, "13 450"),
        ("dsCallout", .dsCallout, "13 regular"), ("dsBodyMedium", .dsBodyMedium, "12 medium"),
        ("dsBody", .dsBody, "12 regular"), ("dsCaptionMedium", .dsCaptionMedium, "11 medium"),
        ("dsCaption", .dsCaption, "11 regular"), ("dsMicro", .dsMicro, "10 regular"),
        ("dsMono", .dsMono, "mono 12"), ("dsMonoCaption", .dsMonoCaption, "mono 11"),
        ("dsMonoMicro", .dsMonoMicro, "mono 10"),
    ]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: DS.Space.xl, verticalSpacing: DS.Space.sm) {
            ForEach(Self.styles, id: \.0) { style in
                GridRow {
                    Text(style.0)
                        .font(.dsMonoMicro)
                        .foregroundStyle(.dsTextTertiary)
                    Text("Ship the agent harness")
                        .font(style.1)
                        .foregroundStyle(.dsTextPrimary)
                    Text(style.2)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
            }
        }
    }
}

struct GalleryMetrics: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(alignment: .bottom, spacing: DS.Space.md) {
                ForEach(
                    [
                        DS.Space.xxs, DS.Space.xs, DS.Space.sm, DS.Space.md, DS.Space.lg, DS.Space.xl, DS.Space.xxl,
                        DS.Space.xxxl,
                    ], id: \.self
                ) { space in
                    VStack(spacing: DS.Space.xs) {
                        Rectangle().fill(.dsAccent).frame(width: space, height: space)
                        Text("\(Int(space))").font(.dsMicro).foregroundStyle(.dsTextTertiary)
                    }
                }
            }
            HStack(spacing: DS.Space.lg) {
                ForEach(
                    [
                        ("small", DS.Radius.small), ("control", DS.Radius.control), ("row", DS.Radius.row),
                        ("card", DS.Radius.card), ("panel", DS.Radius.panel),
                    ], id: \.0
                ) { radius in
                    VStack(spacing: DS.Space.xs) {
                        RoundedRectangle(cornerRadius: radius.1, style: .continuous)
                            .fill(.dsSurface)
                            .strokeBorder(.dsBorder)
                            .frame(width: 56, height: 40)
                        Text("\(radius.0) \(Int(radius.1))").font(.dsMicro).foregroundStyle(.dsTextTertiary)
                    }
                }
            }
            HStack(spacing: DS.Space.xl) {
                ForEach(
                    [("modal", DS.Shadow.modal), ("drag", DS.Shadow.drag), ("floating", DS.Shadow.floating)], id: \.0
                ) { shadow in
                    RoundedRectangle(cornerRadius: DS.Radius.card)
                        .fill(.dsOverlay)
                        .frame(width: 96, height: 48)
                        .overlay { Text(shadow.0).font(.dsCaption).foregroundStyle(.dsTextSecondary) }
                        .dsShadow(shadow.1)
                }
            }
            .padding(.vertical, DS.Space.md)
        }
    }
}
