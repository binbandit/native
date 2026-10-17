import Experiments
import SwiftUI

/// How wide the transcript and the composer can grow (the `transcriptWidth` experiment).
enum TranscriptWidth: String, ParameterChoice {
    case narrow
    case standard
    case wide
    case full

    var title: String {
        switch self {
        case .narrow: "Narrow"
        case .standard: "Standard"
        case .wide: "Wide"
        case .full: "Full window"
        }
    }

    /// The column's maximum width.
    var maxWidth: CGFloat {
        switch self {
        case .narrow: 640
        case .standard: transcriptColumnWidth
        case .wide: 960
        case .full: .infinity
        }
    }
}

/// The readable column width shared by the transcript and the composer.
let transcriptColumnWidth: CGFloat = 760

extension EnvironmentValues {
    /// How wide the session's transcript and composer may grow; `SessionView` sets it.
    @Entry var transcriptColumnMaxWidth: CGFloat = transcriptColumnWidth
}
