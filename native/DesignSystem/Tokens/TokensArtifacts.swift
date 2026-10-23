import SwiftUI

extension DS {
    nonisolated enum Artifact {
        static let viewerWidth: CGFloat = 880
        static let viewerHeight: CGFloat = 640
        static let minimumWidth: CGFloat = 320
        static let minimumHeight: CGFloat = 360
        static let thumbnailWidth: CGFloat = 280
        static let thumbnailHeight: CGFloat = 140
        /// Mixed message attachments form compact, equally tall tiles.
        static let messageTileWidth: CGFloat = 160
        static let messageTileHeight: CGFloat = 96
        static let keyboardPan: CGFloat = 60
    }
}
