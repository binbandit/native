import Testing

@testable import CodeThemes

@Suite struct SpecimenSourceTests {
    private let completed = "    if (attempt >= 3) throw new Error(\"completed\"); // retry"
    private let running = "    if (attempt >= 4) throw new Error(\"running\"); // retry"

    @Test func runningTaskInSameCheckoutCannotSupplyCompletedTasksChange() {
        let path = "/fixture/pier/chunker.ts"
        let result = SpecimenSource.choose(from: [
            .init(project: "pier", isFinished: false, changes: [.init(path: path, before: nil, after: running)]),
            .init(project: "pier", isFinished: true, changes: [.init(path: path, before: nil, after: completed)]),
        ])
        #expect(!result.isSample)
        #expect(result.added.first?.text == completed)
        #expect(!result.added.contains { $0.text == running })
        #expect(
            SpecimenSource.choose(from: [
                .init(project: "pier", isFinished: false, changes: [.init(path: path, before: nil, after: running)])
            ]).isSample)
    }

    @Test func oversizedAndUnsupportedCapturedChangesUseSample() {
        let large = String(repeating: "x", count: 100_001)
        let result = SpecimenSource.choose(from: [
            .init(
                project: "pier", isFinished: true,
                changes: [
                    .init(path: "asset.bin", before: nil, after: large),
                    .init(path: "generated.ts", before: nil, after: large),
                    .init(path: "shrinking.ts", before: large, after: completed),
                    .init(path: "asset.png", before: nil, after: completed),
                ])
        ])
        #expect(result.isSample)
    }

    @Test func noCapturedDiffUsesSampleWithoutReadingCheckout() {
        #expect(SpecimenSource.choose(from: [.init(project: "pier", isFinished: true, changes: [])]).isSample)
    }
}
