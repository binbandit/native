import SwiftUI

extension View {
    /// Draws a row's part of its file's card: the fill, the side borders, and at the ends the
    /// rounded corners and the top or bottom border. Rows of a flat list put together look like
    /// one card per file.
    func fileCardSlice(_ slice: PullRequestFilesRow.Slice) -> some View {
        modifier(PullRequestFileCardSlice(slice: slice))
    }
}

private struct PullRequestFileCardSlice: ViewModifier {
    let slice: PullRequestFilesRow.Slice

    func body(content: Content) -> some View {
        if slice == .middle, UserDefaults.standard.bool(forKey: "gitHubExperimentPlainSlice") {
            content
                .background(.dsDiffBackground)
                .overlay(alignment: .leading) { Rectangle().fill(.dsSeparator).frame(width: 1) }
                .overlay(alignment: .trailing) { Rectangle().fill(.dsSeparator).frame(width: 1) }
        } else {
            sliced(content)
        }
    }

    @ViewBuilder private func sliced(_ content: Content) -> some View {
        let radius = DS.Radius.card
        let hasTop = slice == .top || slice == .single
        let hasBottom = slice == .bottom || slice == .single
        let top: CGFloat = hasTop ? radius : 0
        let bottom: CGFloat = hasBottom ? radius : 0
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: bottom,
            topTrailingRadius: top, style: .continuous)
        content
            .background(.dsDiffBackground, in: shape)
            .clipShape(shape)
            .overlay {
                PullRequestFileCardBorder(hasTop: hasTop, hasBottom: hasBottom, radius: radius)
                    .stroke(.dsSeparator, lineWidth: 1)
            }
            // Space between files.
            .padding(.bottom, hasBottom ? DS.Space.lg : 0)
    }
}

/// The card's border for one slice: the sides always, the top and bottom only at the ends.
private struct PullRequestFileCardBorder: Shape {
    let hasTop: Bool
    let hasBottom: Bool
    let radius: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: 0.5, dy: 0)
        var path = Path()
        // Left side, from the bottom up, rounding into the top if it's there.
        path.move(to: CGPoint(x: rect.minX, y: hasBottom ? rect.maxY - radius : rect.maxY))
        if hasTop {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 0.5 + radius))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.minY + 0.5),
                tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY + 0.5), radius: radius)
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY + 0.5))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.minY + 0.5),
                tangent2End: CGPoint(x: rect.maxX, y: rect.minY + 0.5 + radius), radius: radius)
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        // Right side down, rounding into the bottom if it's there.
        if hasBottom {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 0.5 - radius))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.maxY - 0.5),
                tangent2End: CGPoint(x: rect.maxX - radius, y: rect.maxY - 0.5), radius: radius)
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY - 0.5))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.maxY - 0.5),
                tangent2End: CGPoint(x: rect.minX, y: rect.maxY - 0.5 - radius), radius: radius)
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        return path
    }
}
