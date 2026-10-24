import Foundation
import Testing

@testable import AppAppearance

struct TranscriptReadingPositionTests {
    private typealias Position = TranscriptReadingPosition

    @Test func foldRoundTripsKeepThePassageAndItsOffset() throws {
        var position = reading()
        let place = try #require(position.place)
        #expect(place.id == "pass-6")
        #expect(place.anchorY == 0.2)
        for _ in 0..<10 {
            // Width reflow changes every preceding row; the system initially lands at the end.
            position.update(layout(width: 800, height: 900, top: 4100, rowTop: 1700, rowHeight: 150))
            #expect(position.isRestoring)
            #expect(position.place == place)
            position.update(layout(width: 800, height: 900, top: 1550, rowTop: 1700, rowHeight: 150))
            #expect(position.isInPlace)
            position.finishRestoration()
            #expect(!position.isRestoring)
            #expect(position.place == place)
            position.update(layout(width: 400, height: 600, top: 4400, rowTop: 2100, rowHeight: 100))
            #expect(position.isRestoring)
            position.update(layout(width: 400, height: 600, top: 2000, rowTop: 2100, rowHeight: 100))
            #expect(position.isInPlace)
            position.finishRestoration()
            #expect(!position.isRestoring)
            #expect(position.place == place)
        }
    }

    @Test func teardownAndLateRowsDoNotReplaceTheSavedPassage() throws {
        var position = reading()
        let place = try #require(position.place)
        position.update(Position.Layout(viewport: .zero, contentHeight: 0, rows: [:]))
        #expect(position.place == place)
        position.detach()
        position.update(
            Position.Layout(
                viewport: CGRect(x: 0, y: 4400, width: 400, height: 600),
                contentHeight: 5000, rows: [:]))
        #expect(position.isRestoring)
        #expect(position.place == place)
        position.update(layout(width: 400, height: 600, top: 2000, rowTop: 2100, rowHeight: 100))
        #expect(position.isInPlace)
        position.finishRestoration()
        #expect(!position.isRestoring)
        #expect(position.place == place)
    }

    @Test func measuredBottomStillFollowsNewOutputAfterRecreation() {
        var position = reading()
        position.update(layout(width: 400, height: 600, top: 4400, rowTop: 4500, rowHeight: 100))
        #expect(position.place == nil)
        position.detach()
        position.update(
            Position.Layout(
                viewport: CGRect(x: 0, y: 4400, width: 400, height: 600),
                contentHeight: 6000, rows: [:]))
        #expect(position.isRestoring)
        position.update(
            Position.Layout(
                viewport: CGRect(x: 0, y: 5400, width: 400, height: 600),
                contentHeight: 6000, rows: [:]))
        #expect(position.isInPlace)
        position.finishRestoration()
        #expect(!position.isRestoring)
        #expect(position.place == nil)
    }

    @Test func recreatedViewUsesTheMeasuredAnchorInsteadOfJustTheRowID() throws {
        let saved = try #require(reading().place)
        var recreated = Position(place: saved)
        recreated.update(layout(width: 400, height: 600, top: 2100, rowTop: 2100, rowHeight: 100))
        #expect(recreated.isRestoring)
        #expect(recreated.place == saved)
        recreated.update(layout(width: 400, height: 600, top: 2000, rowTop: 2100, rowHeight: 100))
        #expect(recreated.isInPlace)
        recreated.finishRestoration()
        #expect(!recreated.isRestoring)
        #expect(recreated.place == saved)
    }

    @Test func deliberateScrollCancelsRestorationAndRecordsTheNewPassage() {
        var position = reading()
        position.detach()
        position.update(layout(width: 800, height: 900, top: 4100, rowTop: 1700, rowHeight: 150))
        position.userDidScroll()
        position.update(
            Position.Layout(
                viewport: CGRect(x: 0, y: 2300, width: 800, height: 900),
                contentHeight: 5000, rows: ["pass-8": CGRect(x: 0, y: 2400, width: 800, height: 200)]))
        #expect(!position.isRestoring)
        #expect(position.place?.id == "pass-8")
    }

    @Test func transientBottomBeforeReflowDoesNotReplaceTheLatestAnchor() {
        var position = Position()
        position.update(layout(width: 640, height: 771, top: 822, rowTop: 1400, rowHeight: 100, contentHeight: 1593))
        position.finishRestoration()
        #expect(position.place == nil)
        // Captured Duo fold: the first narrower layout still has the old content height.
        position.update(layout(width: 585, height: 771, top: 821, rowTop: 1400, rowHeight: 100, contentHeight: 1592))
        #expect(position.isInPlace)
        // Reflow then restores a stale offset at that same width. Keep the latest-output target.
        position.update(layout(width: 585, height: 771, top: 720, rowTop: 774, rowHeight: 37, contentHeight: 1840))
        #expect(position.isRestoring)
        #expect(position.place == nil)
    }

    @Test func transientAlignmentBeforeReflowKeepsTheReadingAnchor() throws {
        var position = reading()
        let saved = try #require(position.place)
        position.update(layout(width: 800, height: 900, top: 1550, rowTop: 1700, rowHeight: 150))
        #expect(position.isInPlace)
        position.update(layout(width: 800, height: 900, top: 1550, rowTop: 1400, rowHeight: 150))
        #expect(position.isRestoring)
        #expect(position.place == saved)
        position.update(layout(width: 800, height: 900, top: 1250, rowTop: 1400, rowHeight: 150))
        position.finishRestoration()
        #expect(position.place == saved)
    }

    @Test func restorationDeadlineAllowsLaterScrollsToReplaceTheOldPassage() {
        var position = reading()
        position.update(layout(width: 800, height: 900, top: 2200, rowTop: 1700, rowHeight: 150))
        #expect(position.isRestoring)
        position.finishRestoration()
        #expect(!position.isRestoring)
        #expect(position.place != nil)
        // Accessibility can scroll instantly, without an interacting or animating phase.
        position.update(layout(width: 800, height: 900, top: 4100, rowTop: 4500, rowHeight: 150))
        #expect(position.place == nil)
        position.detach()
        #expect(position.place == nil)
    }

    @Test func restorationDeadlineWithoutRowsKeepsTheRememberedPassage() {
        var position = reading()
        let saved = position.place
        position.detach()
        position.update(
            Position.Layout(
                viewport: CGRect(x: 0, y: 4400, width: 400, height: 600),
                contentHeight: 5000, rows: [:]))
        position.finishRestoration()
        #expect(!position.isRestoring)
        #expect(position.place == saved)
        position.update(layout(width: 400, height: 600, top: 4400, rowTop: 2100, rowHeight: 100))
        #expect(position.isRestoring)
        #expect(position.place == saved)
    }

    @Test func partialAndOversizedRowsHaveFiniteAnchors() throws {
        for rowHeight: CGFloat in [400, 1200] {
            var position = Position()
            position.update(layout(width: 400, height: 600, top: 4400, rowTop: 4500, rowHeight: 100))
            position.finishRestoration()
            position.update(layout(width: 400, height: 600, top: 2000, rowTop: 1800, rowHeight: rowHeight))
            let place = try #require(position.place)
            #expect(place.anchorY.isFinite)
            #expect(abs(place.anchorY * (600 - rowHeight) + 200) < 0.001)
        }
    }

    @Test func missingGeometryWhileReadingKeepsTheLastValidSnapshot() {
        var position = reading()
        let place = position.place
        position.update(
            Position.Layout(
                viewport: CGRect(x: 0, y: 2000, width: 400, height: 600),
                contentHeight: 5000, rows: [:]))
        #expect(position.place == place)
        position.update(
            Position.Layout(
                viewport: CGRect(x: 0, y: 4400, width: 400, height: 600),
                contentHeight: 5000, rows: [:]))
        #expect(position.place == place)
        position.update(layout(width: 400, height: 600, top: 2000, rowTop: 2000, rowHeight: 600))
        #expect(position.place == place)
    }

    private func reading() -> Position {
        var position = Position()
        position.update(layout(width: 400, height: 600, top: 4400, rowTop: 4500, rowHeight: 100))
        position.finishRestoration()
        position.update(layout(width: 400, height: 600, top: 2000, rowTop: 2100, rowHeight: 100))
        return position
    }

    private func layout(
        width: CGFloat, height: CGFloat, top: CGFloat, rowTop: CGFloat, rowHeight: CGFloat,
        contentHeight: CGFloat = 5000
    )
        -> Position.Layout
    {
        Position.Layout(
            viewport: CGRect(x: 0, y: top, width: width, height: height), contentHeight: contentHeight,
            rows: ["pass-6": CGRect(x: 0, y: rowTop, width: width, height: rowHeight)])
    }
}
