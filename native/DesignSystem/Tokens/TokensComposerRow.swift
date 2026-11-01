import SwiftUI

extension DS {
    nonisolated enum ComposerRow {
        static let height: CGFloat = 44
        #if os(iOS)
        static let controlHeight: CGFloat = 44
        static let actionWidth: CGFloat = 44
        static let modeWidth: CGFloat = 154
        #else
        static let controlHeight: CGFloat = 32
        static let actionWidth: CGFloat = 32
        static let modeWidth: CGFloat = 144
        #endif
        static let locationWidth: CGFloat = 154
        static let contextDiameter: CGFloat = 18
        static let menuWidth: CGFloat = 360
        static let menuMaxHeight: CGFloat = 352
        static let menuRowHeight: CGFloat = 44
        static let checkWidth: CGFloat = 16
        static let searchThreshold = 8
        static let borderWidth: CGFloat = 1
        static let previewWidth: CGFloat = 720
        static let narrowPreviewWidth: CGFloat = 600
        static let previewHeight: CGFloat = 120
        static let menuPreviewHeight: CGFloat = 440
    }
}
