import Foundation
import Testing

@testable import ACP

struct PromptAttachmentTests {
    private let readme = PromptAttachment.file(URL(filePath: "/repo/README.md"))
    private let screenshot = PromptAttachment.image(data: Data([1, 2, 3]), mimeType: "image/png", name: "shot.png")

    @Test func textOnlyIsOneTextBlock() {
        #expect(ContentBlock.prompt("Fix it", supportsImages: true) == [.text("Fix it")])
    }

    @Test func filesGoAsResourceLinksOnce() {
        let blocks = ContentBlock.prompt("Read @README.md", attachments: [readme, readme], supportsImages: false)
        #expect(blocks == [.text("Read @README.md"), .resourceLink(uri: "file:///repo/README.md", name: "README.md")])
    }

    @Test func imagesGoToAgentsThatTakeThem() {
        let blocks = ContentBlock.prompt("What's wrong?", attachments: [screenshot], supportsImages: true)
        #expect(blocks == [.text("What's wrong?"), .image(data: "AQID", mimeType: "image/png")])
    }

    @Test func imagesAreLeftOutWithANoteOtherwise() {
        let blocks = ContentBlock.prompt("What's wrong?", attachments: [screenshot, readme], supportsImages: false)
        #expect(blocks.count == 3)
        #expect(blocks[1] == .resourceLink(uri: "file:///repo/README.md", name: "README.md"))
        #expect(blocks[2].text?.contains("shot.png") == true)
    }

    @Test func blocksEncodeToTheWireShape() throws {
        let json = try JSONEncoder().encode(ContentBlock.prompt("", attachments: [readme], supportsImages: false))
        let decoded = try JSONSerialization.jsonObject(with: json) as? [[String: String]]
        #expect(decoded == [["type": "resource_link", "uri": "file:///repo/README.md", "name": "README.md"]])
    }
}
