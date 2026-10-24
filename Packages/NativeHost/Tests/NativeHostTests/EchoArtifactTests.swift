import ACP
import Foundation
import Testing

@testable import NativeHostProtocol

struct EchoArtifactTests {
    @Test func attachedFilesKeepTheirContentsAndOriginAcrossTheHost() throws {
        let original = MessageAttachment(
            name: "notes.txt", url: URL(filePath: "/outside-project/notes.txt"),
            embeddedData: Data("Attached notes".utf8), mimeType: "text/plain", isLocalFile: true, byteCount: 4096)
        let wire = try JSONEncoder().encode(EchoAttachment(original))
        let echo = try JSONDecoder().decode(EchoAttachment.self, from: wire)
        let restored = echo.messageAttachment
        #expect(restored.embeddedData == original.embeddedData)
        #expect(restored.mimeType == original.mimeType)
        #expect(restored.isLocalFile)
        #expect(restored.byteCount == 4096)
        #expect(echo.withoutImage.messageAttachment.byteCount == 4096)
        #expect(echo.withoutImage.messageAttachment.embeddedData == nil)
        #expect(echo.withoutImage.imageBase64 == nil)
    }

    @Test func olderAttachmentEchoesStillDecodeAsUserFiles() throws {
        let data = Data(#"{"name":"report.pdf","url":"file:///outside-project/report.pdf"}"#.utf8)
        let restored = try JSONDecoder().decode(EchoAttachment.self, from: data).messageAttachment
        #expect(restored.isLocalFile)
        #expect(restored.embeddedData == nil)
        #expect(restored.mimeType == nil)
        #expect(restored.byteCount == nil)
    }
}
