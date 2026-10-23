import SwiftUI

/// Geometry shared by the celebration catalogue, details and year strip.
enum CelebrationMetrics {
    static let hairline: CGFloat = 1
    static let previewTile: CGFloat = 28
    static let surfacePreview: CGFloat = 28
    static let statusPreview: CGFloat = 40
    static let detailPreview: CGFloat = 52
    static let decoratedMarkScale: CGFloat = 0.8
    static let rowHeight: CGFloat = 44
    static let chevron: CGFloat = 9
    static let menuSize: CGFloat = 26
    static let factGlyph: CGFloat = 12
    static let offlineGlyph: CGFloat = 14
    static let windowSelectWidth: CGFloat = 280
    static let yearHeight: CGFloat = 104
    static let yearBaseline: CGFloat = 78
    static let yearIcon: CGFloat = 18
    static let yearRadius: CGFloat = 5
    static let yearLane: CGFloat = 22
    static let yearIconGap: CGFloat = 2
    static let yearStemGap: CGFloat = 8
    static let yearRing: CGFloat = 1.5
    static let yearCurrentRingOutset = yearRing * 1.5
    static let yearSpan: CGFloat = 3
    static let yearTick: CGFloat = 5
    static let yearLabelOffset: CGFloat = 9
    static let yearTodayClearance: CGFloat = 30
    static let yearLabelFont = Font.ds(10.5)
    static let bulkFade = Animation.easeOut(duration: 1.2)
}
