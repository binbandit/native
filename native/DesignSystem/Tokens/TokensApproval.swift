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
        static let buttonHeight: CGFloat = 26
        static let buttonInset: CGFloat = 11
        static let smallButtonHeight: CGFloat = 22
        static let smallButtonInset: CGFloat = 9
        static let fixItGap: CGFloat = 10
        static let ringSize: CGFloat = 12
        static let ringStroke: CGFloat = 1.5
        static let rule: CGFloat = 1
        static let maximumHeight: CGFloat = 470
        /// Leaves room for the question's pager, actions and answer field in a normal window.
        static let questionMaximumHeight: CGFloat = 320
        static let instructionHeight: CGFloat = 52
        static let instructionMaximumHeight: CGFloat = 78
        static let editorInsets = EdgeInsets()
        static let commandLineSpacing: CGFloat = 4
        static let commandFont = DSTypography.font(size: 13, design: .mono)
        static let titleFont = DSTypography.font(size: 14, weight: .medium)
        static let fixItFont = DSTypography.font(size: 11.5, design: .mono)
        static let smallButtonFont = DSTypography.font(size: 11.5, weight: .medium)
        static let monoAdvance: CGFloat = 7.8
        /// A push's dropped commits: an abbreviated hash, then the subject.
        static let commitHashWidth: CGFloat = 66
        static let commitRowHeight: CGFloat = 22
        static let reasonLineLimit = 3
        static let ringTrackOpacity: Double = 0.3
        static let sweepOpacity: Double = 0.14
        static let hintOpacity: Double = 0.55
        static let pressedOpacity: Double = 0.8
        static let cancelAnimation = Animation.linear(duration: 0.15)
        // Questions and failed starts share the approval's frame and type.
        static let askTop: CGFloat = 14
        static let questionTitleTop: CGFloat = 6
        static let questionTitleBottom: CGFloat = 10
        static let optionInset: CGFloat = 10
        static let optionGap: CGFloat = 12
        static let optionDetailGap: CGFloat = 1
        static let keycapSize: CGFloat = 18
        static let keycapFont = DSTypography.font(size: 10.5, weight: .medium, design: .mono)
        static let footerTop: CGFloat = 10
        static let failureIcon: CGFloat = 16
        /// The failure's text and source hang from the end of its icon.
        static let failureIndent: CGFloat = 24
        static let failureDetailTop: CGFloat = 3
        static let failureFooterTop: CGFloat = 16
        static let sourceTop: CGFloat = 14
        static let sourceInset: CGFloat = 10
        static let lineNumberWidth: CGFloat = 40
        static let squiggleAmplitude: CGFloat = 1.25
        static let squiggleWavelength: CGFloat = 4
        static let squiggleOffset: CGFloat = 3
        static let outputMaximumHeight: CGFloat = 160
        static let surfaceTintOpacity: Double = 0.78
        static let shadowRadius: CGFloat = 16
        static let shadowOffset: CGFloat = 8

        static func surface(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? Color(red: 29 / 255, green: 29 / 255, blue: 33 / 255) : .white
        }

        static func edge(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.085) : Color.black.opacity(0.1)
        }

        static func separator(_ scheme: ColorScheme) -> Color {
            (scheme == .dark ? Color.white : .black).opacity(0.065)
        }

        static func shadow(_ scheme: ColorScheme) -> Color {
            Color.black.opacity(scheme == .dark ? 0.3 : 0.08)
        }

        static func well(_ scheme: ColorScheme) -> Color {
            Color.black.opacity(scheme == .dark ? 0.28 : 0.035)
        }

        static func buttonFill(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.06) : .white
        }

        static func buttonBorder(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.14)
        }
    }
}
