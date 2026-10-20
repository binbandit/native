import Testing

@testable import SessionTitling

@Suite("On-device titles")
struct OnDeviceTitleGeneratorTests {
    @Test(
        "The model writes a short title through the hand-written schema",
        .enabled(if: OnDeviceTitleGenerator.isAvailable, "Apple Intelligence isn't available here"))
    func writesTitle() async throws {
        let request = SessionTitleRequest(
            projectName: "native", prompt: "Add a retry with backoff to the upload client when the network drops")
        let title = try #require(try await OnDeviceTitleGenerator().title(for: request))
        #expect((1...10).contains(title.split(separator: " ").count))
        #expect(title.first?.isUppercase == true)
    }
}
