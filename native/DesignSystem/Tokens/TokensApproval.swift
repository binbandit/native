import SwiftUI

extension DS {
    nonisolated enum Approval {
        static let composerWidth: CGFloat = 808
        static let inset: CGFloat = 24
        static let commandInset: CGFloat = 14
        static let commandTop: CGFloat = 12
        static let commandLine: CGFloat = 20
        static let annotationLine: CGFloat = 22
        static let annotationStem: CGFloat = 7
        static let annotationGap: CGFloat = 12
        static let underlineOffset: CGFloat = 5
        static let buttonHeight: CGFloat = 26
        static let buttonInset: CGFloat = 11
        static let ringSize: CGFloat = 12
        static let ringStroke: CGFloat = 1.5
        static let rule: CGFloat = 1
        static let maximumHeight: CGFloat = 470
        static let commandFont = DSTypography.font(size: 13, design: .mono)
        static let monoAdvance: CGFloat = 7.8
        static let ringTrackOpacity: Double = 0.3
        static let sweepOpacity: Double = 0.14
        static let hintOpacity: Double = 0.55
        static let pressedOpacity: Double = 0.8
        static let cancelAnimation = Animation.linear(duration: 0.15)
    }
}
