import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import ACP

struct PromptAttachmentTests {
    private let readme = PromptAttachment(
        url: URL(filePath: "/repo/README.md"), content: .text("# Repo"), byteCount: 6)
    private let screenshot = PromptAttachment(
        url: URL(filePath: "/tmp/shot.png"), content: .image(Data([1, 2, 3]), mimeType: "image/png"), byteCount: 3)
    private let everything = PromptCapabilities(image: true, embeddedContext: true)
    private let nothing = PromptCapabilities()

    @Test func textOnlyIsOneTextBlock() {
        #expect(ContentBlock.prompt("Fix it", capabilities: everything) == [.text("Fix it")])
    }

    @Test func smallTextFilesAreEmbeddedForAgentsThatTakeIt() {
        let blocks = ContentBlock.prompt("Read this", attachments: [readme, readme], capabilities: everything)
        #expect(blocks == [.text("Read this"), .resource(uri: "file:///repo/README.md", text: "# Repo")])
    }

    @Test func everythingElseGoesByPath() {
        let blocks = ContentBlock.prompt("Look", attachments: [screenshot, readme], capabilities: nothing)
        #expect(
            blocks == [
                .text("Look"),
                .resourceLink(uri: "file:///tmp/shot.png", name: "shot.png"),
                .resourceLink(uri: "file:///repo/README.md", name: "README.md"),
            ])
    }

    @Test func imagesGoToAgentsThatTakeThem() {
        let blocks = ContentBlock.prompt("What's wrong?", attachments: [screenshot], capabilities: everything)
        #expect(blocks == [.text("What's wrong?"), .image(data: "AQID", mimeType: "image/png")])
    }

    /// The transcript shows what went: a picture sent as its path shows as a file.
    @Test func picturesSentAsPathsShowAsFiles() {
        #expect(MessageAttachment.shown([screenshot], capabilities: everything).first?.isImage == true)
        #expect(MessageAttachment.shown([screenshot], capabilities: nothing).first?.isImage == false)
    }

    @Test func blocksEncodeToTheWireShape() throws {
        let json = try JSONEncoder().encode(ContentBlock.prompt("", attachments: [readme], capabilities: nothing))
        let decoded = try JSONSerialization.jsonObject(with: json) as? [[String: String]]
        #expect(decoded == [["type": "resource_link", "uri": "file:///repo/README.md", "name": "README.md"]])
    }

    @Test func limitsCountAndInlineBytes() throws {
        let one = try PromptAttachment.adding(readme, to: [])
        #expect(try PromptAttachment.adding(readme, to: one).count == 1)
        let big = PromptAttachment(
            url: URL(filePath: "/tmp/big.png"),
            content: .image(Data(count: PromptAttachment.Limits.inlineBytes), mimeType: "image/png"), byteCount: 0)
        #expect(throws: PromptAttachment.LimitError.tooMuchInline(name: "big.png")) {
            try PromptAttachment.adding(big, to: one)
        }
        let many = (0..<PromptAttachment.Limits.count).map {
            PromptAttachment(url: URL(filePath: "/tmp/\($0)"), content: .reference, byteCount: 0)
        }
        #expect(throws: PromptAttachment.LimitError.tooMany) { try PromptAttachment.adding(readme, to: many) }
    }
}

struct PromptAttachmentLoadingTests {
    private let folder: URL

    init() throws {
        folder = URL.temporaryDirectory.appending(path: "PromptAttachmentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    @Test func smallTextIsReadAndBinaryIsLinked() throws {
        let notes = folder.appending(path: "notes.txt")
        try Data("hello".utf8).write(to: notes)
        #expect(try PromptAttachment.load(notes).content == .text("hello"))
        let binary = folder.appending(path: "blob.bin")
        try Data([0, 1, 2]).write(to: binary)
        #expect(try PromptAttachment.load(binary).content == .reference)
        #expect(try PromptAttachment.load(folder).content == .reference)
    }

    @Test func largeImagesAreScaledToFit() throws {
        let url = folder.appending(path: "wide.png")
        try writeImage(width: 4096, height: 1024, to: url)
        let attachment = try PromptAttachment.load(url)
        guard case .image(let data, let mimeType) = attachment.content else {
            Issue.record("not an image")
            return
        }
        #expect(mimeType == "image/png")
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        #expect(properties?[kCGImagePropertyPixelWidth] as? Int == PromptAttachment.Limits.imagePixels)
    }

    @Test func pastedImagesGetAFile() throws {
        let url = folder.appending(path: "small.png")
        try writeImage(width: 10, height: 10, to: url)
        let attachment = try PromptAttachment.pasted(try Data(contentsOf: url), type: .png)
        #expect(attachment.name == "Pasted Image.png")
        #expect(FileManager.default.fileExists(atPath: attachment.url.path(percentEncoded: false)))
        #expect(attachment.isImage)
    }

    /// Files that only look like images (an SVG, a broken PNG) go as text or by path, never fail.
    @Test func filesImageIOCantDrawStillAttach() throws {
        let svg = folder.appending(path: "logo.svg")
        try Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"/>"#.utf8).write(to: svg)
        #expect(
            try PromptAttachment.load(svg).content
                == .text(#"<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"/>"#))
        let broken = folder.appending(path: "broken.png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0, 1, 2, 3]).write(to: broken)
        let attachment = try PromptAttachment.load(broken)
        #expect(attachment.content == .reference)
        #expect(attachment.isImageFile)
    }

    /// Past what Native will read and scale, a picture goes by its path rather than not at all.
    @Test func oversizedImagesGoByPath() throws {
        let url = folder.appending(path: "huge.png")
        try writeImage(width: 10, height: 10, to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(PromptAttachment.Limits.imageFileBytes + 1))
        try handle.close()
        let attachment = try PromptAttachment.load(url)
        #expect(attachment.content == .reference)
        #expect(attachment.byteCount == PromptAttachment.Limits.imageFileBytes + 1)
    }

    @Test func missingFilesSaySo() {
        #expect(throws: PromptAttachment.LoadError.missing(name: "gone.txt")) {
            try PromptAttachment.load(folder.appending(path: "gone.txt"))
        }
    }

    @Test func mentionsLinkFilesThatExist() throws {
        try Data("x".utf8).write(to: folder.appending(path: "README.md"))
        try FileManager.default.createDirectory(
            at: folder.appending(path: "My Docs"), withIntermediateDirectories: true)
        let mentions = PromptAttachment.mentions(
            in: "See @README.md. and @\"My Docs\", not @nowhere or mail@README.md", relativeTo: folder)
        #expect(mentions.map(\.name) == ["README.md", "My Docs"])
        #expect(mentions.allSatisfy { $0.origin == .mentioned && $0.content == .reference })
    }

    private func writeImage(width: Int, height: Int, to url: URL) throws {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
