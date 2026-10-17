import SwiftUI

/// Native's emblem: two rounded links interlocking. A `Shape`, so it renders crisp at any size in
/// any color; it keeps its aspect ratio, centered in the rect it's given. The links don't overlap,
/// so even-odd and non-zero fills agree.
///
///     NativeMark().fill(.dsTextPrimary)
///
/// The outline is translated from the app-icon artwork (`design/app-icon/layers/native-mark.svg`,
/// owned by the icon work; regenerate this file from it rather than editing points by hand).
public nonisolated struct NativeMark: Shape {
    /// Draws one link alone, for animating them separately; `nil` draws both.
    let link: Link?

    /// The emblem's two links, each a hooked loop open where the other passes through it.
    public enum Link: CaseIterable, Sendable {
        case left, right

        fileprivate var index: Int {
            switch self {
            case .right: 0
            case .left: 1
            }
        }
    }

    public init(link: Link? = nil) {
        self.link = link
    }

    /// Width over height of the emblem.
    public static let aspectRatio: CGFloat = 1 / 0.64304

    public func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height * Self.aspectRatio)
        let origin = CGPoint(
            x: rect.midX - scale / 2,
            y: rect.midY - scale / Self.aspectRatio / 2
        )
        func point(_ p: (Double, Double)) -> CGPoint {
            CGPoint(x: origin.x + p.0 * scale, y: origin.y + p.1 * scale)
        }
        var path = Path()
        let links = link.map { [Self.links[$0.index]] } ?? Self.links
        for segments in links {
            for segment in segments {
                switch segment {
                case .move(let p): path.move(to: point(p))
                case .line(let p): path.addLine(to: point(p))
                case .quad(let p, let control): path.addQuadCurve(to: point(p), control: point(control))
                }
            }
            path.closeSubpath()
        }
        return path
    }

    private enum Segment: Sendable {
        case move((Double, Double))
        case line((Double, Double))
        /// To a point, through a control point.
        case quad((Double, Double), (Double, Double))
    }

    /// Each link's outline in units of the emblem's width, from its top-left corner.
    private static let links: [[Segment]] = [
        // The right link.
        [
            .move((0.62473, 0.00096)),
            .quad((0.67022, 0.00294), (0.64055, -0.00168)),
            .quad((0.72363, 0.02206), (0.69989, 0.00755)),
            .quad((0.86209, 0.14931), (0.74736, 0.03656)),
            .quad((0.98538, 0.2759), (0.97681, 0.26206)),
            .quad((0.99725, 0.30096), (0.99396, 0.28975)),
            .quad((0.99989, 0.32865), (1.00055, 0.31217)),
            .quad((0.9933, 0.35964), (0.99923, 0.34513)),
            .quad((0.9656, 0.3959), (0.98736, 0.37415)),
            .quad((0.89637, 0.45195), (0.94385, 0.41766)),
            .quad((0.7856, 0.52711), (0.8489, 0.48623)),
            .quad((0.70385, 0.5759), (0.72231, 0.56799)),
            .quad((0.66758, 0.58645), (0.68538, 0.58382)),
            .quad((0.62077, 0.58447), (0.64978, 0.58909)),
            .quad((0.56868, 0.56667), (0.59176, 0.57986)),
            .quad((0.45857, 0.46909), (0.5456, 0.55349)),
            .quad((0.36429, 0.37085), (0.37154, 0.38469)),
            .quad((0.35703, 0.34447), (0.35703, 0.357)),
            .quad((0.36099, 0.3214), (0.35703, 0.33195)),
            .quad((0.37286, 0.30162), (0.36495, 0.31085)),
            .quad((0.39791, 0.28118), (0.38077, 0.29239)),
            .line((0.40954, 0.27358)),
            .quad((0.41986, 0.27448), (0.41506, 0.26997)),
            .line((0.51396, 0.36294)),
            .quad((0.62473, 0.4625), (0.61286, 0.4559)),
            .quad((0.6478, 0.46975), (0.63659, 0.46909)),
            .quad((0.67022, 0.46645), (0.65901, 0.47041)),
            .quad((0.71176, 0.44272), (0.68143, 0.4625)),
            .quad((0.79813, 0.38074), (0.74209, 0.42294)),
            .quad((0.85615, 0.32601), (0.85418, 0.33854)),
            .quad((0.85549, 0.30821), (0.85813, 0.31349)),
            .quad((0.76648, 0.22052), (0.85286, 0.30294)),
            .quad((0.67088, 0.13414), (0.68011, 0.1381)),
            .quad((0.64517, 0.13151), (0.66165, 0.13019)),
            .quad((0.59242, 0.15986), (0.62868, 0.13283)),
            .line((0.56144, 0.18295)),
            .quad((0.55138, 0.18234), (0.55615, 0.18689)),
            .line((0.47389, 0.10836)),
            .quad((0.47422, 0.09964), (0.46912, 0.10382)),
            .line((0.52055, 0.06162)),
            .quad((0.59044, 0.01151), (0.57198, 0.01942)),
            .quad((0.62473, 0.00096), (0.6089, 0.0036)),
        ],
        // The left link.
        [
            .move((0.3122, 0.07349)),
            .quad((0.35835, 0.07217), (0.32934, 0.06953)),
            .quad((0.41374, 0.08865), (0.38736, 0.0748)),
            .quad((0.53044, 0.18821), (0.44011, 0.1025)),
            .quad((0.62736, 0.29041), (0.62077, 0.27393)),
            .quad((0.62868, 0.32404), (0.63396, 0.30689)),
            .quad((0.60495, 0.357), (0.62341, 0.34118)),
            .quad((0.57462, 0.37942), (0.58648, 0.37283)),
            .line((0.56851, 0.38281)),
            .quad((0.55799, 0.38145), (0.56275, 0.38601)),
            .line((0.46978, 0.297)),
            .quad((0.3656, 0.20206), (0.37681, 0.20799)),
            .quad((0.34385, 0.19546), (0.3544, 0.19612)),
            .quad((0.31945, 0.20074), (0.3333, 0.1948)),
            .quad((0.22582, 0.26799), (0.3056, 0.20667)),
            .quad((0.14341, 0.33854), (0.14604, 0.32931)),
            .quad((0.14538, 0.357), (0.14077, 0.34777)),
            .quad((0.2311, 0.4414), (0.15, 0.36623)),
            .quad((0.32275, 0.52052), (0.3122, 0.51656)),
            .quad((0.34846, 0.5225), (0.3333, 0.52447)),
            .quad((0.39989, 0.49678), (0.36363, 0.52052)),
            .line((0.43064, 0.47666)),
            .quad((0.4409, 0.47762), (0.43615, 0.47305)),
            .line((0.50657, 0.541)),
            .quad((0.50665, 0.55024), (0.51132, 0.54557)),
            .line((0.49549, 0.5614)),
            .quad((0.45198, 0.59766), (0.47967, 0.57722)),
            .quad((0.40912, 0.62601), (0.42429, 0.6181)),
            .quad((0.3722, 0.6392), (0.39396, 0.63393)),
            .quad((0.32275, 0.6425), (0.35044, 0.64447)),
            .quad((0.27857, 0.63393), (0.29506, 0.64052)),
            .quad((0.24956, 0.61876), (0.26209, 0.62733)),
            .quad((0.12824, 0.50667), (0.23703, 0.61019)),
            .quad((0.0122, 0.39195), (0.01945, 0.40316)),
            .quad((0.00165, 0.36887), (0.00495, 0.38074)),
            .quad((0.00165, 0.33722), (-0.00165, 0.357)),
            .quad((0.01813, 0.29964), (0.00495, 0.31744)),
            .quad((0.14473, 0.18953), (0.03132, 0.28184)),
            .quad((0.27659, 0.08733), (0.25813, 0.09722)),
            .quad((0.3122, 0.07349), (0.29506, 0.07744)),
        ],
    ]
}
