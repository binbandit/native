import Foundation
import Testing

@testable import ACP

#if canImport(ImageIO)
import ImageIO
import UniformTypeIdentifiers
#endif

struct TranscriptArtifactTests {
    @Test func aSingleReadImageKeepsItsFileOriginWithoutGuessingBetweenFiles() {
        var call = ToolCallState(id: "read-image")
        call.kind = .read
        call.content = [.content(.image(data: "AQID", mimeType: "image/png"))]
        call.locations = [ToolCallLocation(path: "/repo/diagram.png")]
        #expect(call.artifacts.first?.url == URL(filePath: "/repo/diagram.png"))
        #expect(call.artifacts.first?.name == "diagram.png")
        call.locations.append(ToolCallLocation(path: "/repo/other.png"))
        #expect(call.artifacts.first?.url == nil)
        call.locations = [ToolCallLocation(path: "/repo/notes.txt")]
        #expect(call.artifacts.first?.url == nil)
    }

    #if canImport(ImageIO)
    @Test func jpegImagesHaveAThumbnailHeader() throws {
        let context = try #require(
            CGContext(
                data: nil, width: 30, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try #require(context.makeImage())
        let bytes = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let artifact = TranscriptArtifact(name: "Photo", data: bytes as Data, mimeType: "image/jpeg")
        #expect(artifact.hasImageHeader)
    }
    #endif

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

    @Test func textResourceKeepsItsMediaTypeForPreviewAndExport() throws {
        let block = try JSONDecoder().decode(
            ContentBlock.self,
            from: Data(
                #"{"type":"resource","resource":{"uri":"artifact:///diagram","mimeType":"image/svg+xml","text":"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"/>"}}"#
                    .utf8))
        let artifact = try #require(TranscriptArtifact(block))
        #expect(artifact.mimeType == "image/svg+xml")
        #expect(artifact.filename == "diagram.svg")
        #expect(artifact.isImage)
        let roundTrip = try JSONDecoder().decode(ContentBlock.self, from: JSONEncoder().encode(block))
        #expect(TranscriptArtifact(roundTrip) == artifact)
        let attachment = try #require(MessageAttachment(roundTrip))
        #expect(TranscriptArtifact(attachment) == artifact)
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
        let permissions = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
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
