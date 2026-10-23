import Foundation
import Testing

@testable import ACP

struct TranscriptArtifactTests {
    @Test func extractsRawMCPImagesBesideTextWithoutRepeatingTypedContent() throws {
        var call = ToolCallState(id: "read-image")
        call.content = [.content(.image(data: "AQID", mimeType: "image/png"))]
        call.rawOutput = try JSONDecoder().decode(
            JSONValue.self,
            from: Data(
                #"{"result":{"content":[{"type":"text","text":"Read image"},{"type":"image","data":"AQID","mimeType":"image/png"},{"type":"resource_link","uri":"file:///repo/report.pdf","name":"report.pdf"}]}}"#
                    .utf8))
        #expect(call.artifacts.count == 2)
        #expect(call.artifacts.first?.data == Data([1, 2, 3]))
        #expect(call.artifacts.last?.filename == "report.pdf")
    }

    @Test func binaryResourceKeepsItsBytesAndMediaType() throws {
        let block = try JSONDecoder().decode(
            ContentBlock.self,
            from: Data(
                #"{"type":"resource","resource":{"uri":"artifact:///chart","mimeType":"image/png","blob":"AQID"}}"#.utf8
            ))
        let artifact = try #require(TranscriptArtifact(block))
        #expect(artifact.data == Data([1, 2, 3]))
        #expect(artifact.mimeType == "image/png")
        #expect(artifact.filename == "chart.png")
        let roundTrip = try JSONDecoder().decode(ContentBlock.self, from: JSONEncoder().encode(block))
        #expect(TranscriptArtifact(roundTrip) == artifact)
    }

    @Test func malformedImageRemainsAnActionableArtifact() {
        let artifact = TranscriptArtifact(.image(data: "not base64", mimeType: "image/png"))
        #expect(artifact?.isImage == true)
        #expect(artifact?.data == nil)
    }

    @Test func privatePreviewKeepsContentsAndCleansUpOnlyItsDirectory() throws {
        let artifact = TranscriptArtifact(name: "../../notes.txt", data: Data("Notes".utf8))
        #expect(artifact.filename == "notes.txt")
        let file = try ArtifactPreviewFile(artifact: artifact, data: Data("Notes".utf8))
        defer { file.remove() }
        #expect(file.url.lastPathComponent == "notes.txt")
        #expect(try Data(contentsOf: file.url) == Data("Notes".utf8))
        file.remove()
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test func agentImageSurvivesFollowingTextChunks() throws {
        var state = SessionState()
        for content in [
            #"{"type":"text","text":"Here is the diagram."}"#,
            #"{"type":"image","data":"AQID","mimeType":"image/png"}"#,
            #"{"type":"text","text":" Inspect the labels."}"#,
        ] {
            let line = """
                {"sessionId":"artifact-task","update":{"sessionUpdate":"agent_message_chunk",\
                "messageId":"reply","content":\(content)}}
                """
            state.apply(try JSONDecoder().decode(SessionNotification.self, from: Data(line.utf8)).update)
        }
        let message = try #require(
            state.items.compactMap { item -> TranscriptMessage? in
                if case .message(let message) = item { message } else { nil }
            }.last)
        #expect(message.text == "Here is the diagram. Inspect the labels.")
        #expect(message.attachments.first?.imageData == Data([1, 2, 3]))
    }

    @Test func agentProseStaysTextAndAnImageOnlyReplyIsNotEmpty() {
        var state = SessionState()
        let prose = "[@notes.txt](file:///repo/notes.txt)"
        state.apply(.agentMessageChunk(ContentChunk(content: .text(prose))))
        guard case .message(let text) = state.items.last else { Issue.record("No reply"); return }
        #expect(text.text == prose)
        #expect(text.attachments.isEmpty)

        state = SessionState()
        state.apply(.agentMessageChunk(ContentChunk(content: .image(data: "AQID", mimeType: "image/png"))))
        guard case .message(let image) = state.items.last else { Issue.record("No image reply"); return }
        #expect(image.text.isEmpty)
        #expect(image.attachments.count == 1)
    }
}
