#if DEBUG
import ACP
import CoreGraphics
import Foundation
import ImageIO

enum UserMessageAttachmentsPreviewFixtures {
    static let wide = MessageAttachment(name: "Diagram-wide.png", url: nil, imageData: image(width: 960, height: 320))
    static let tall = MessageAttachment(name: "Diagram-tall.png", url: nil, imageData: image(width: 320, height: 960))
    static let notes = MessageAttachment(name: "notes.txt", url: nil, embeddedData: Data(repeating: 65, count: 2048))
    static let longName = MessageAttachment(
        name: "artifact-inspection-notes-with-a-very-long-descriptive-filename.txt", url: nil,
        embeddedData: Data(repeating: 65, count: 8192))

    static let mixed = [
        wide, notes, tall, longName,
        MessageAttachment(name: "Diagram.png", url: nil, imageData: ArtifactPreviewFixtures.imageData),
        MessageAttachment(name: "readme.txt", url: nil, embeddedData: Data("Artifact notes.".utf8)),
    ]

    static let files = [
        longName,
        MessageAttachment(name: "Empty.txt", url: nil, embeddedData: Data()),
        MessageAttachment(name: "Unavailable.pdf", url: URL(filePath: "/repo/Unavailable.pdf")),
        MessageAttachment(name: "Unavailable.png", url: nil, imageData: Data(), mimeType: "image/png"),
    ]

    static var messages: [TranscriptMessage] {
        let groups = [[wide], [tall], Array(mixed.prefix(2)), Array(mixed.prefix(3)), mixed, files]
        var state = SessionState()
        for attachments in groups {
            state.appendUserMessage("Inspect this diagram and the artifact notes.", attachments: attachments)
        }
        return state.items.compactMap { item in
            guard case .message(let message) = item else { return nil }
            return message
        }
    }

    private static func image(width: Int, height: Int) -> Data {
        guard let source = CGImageSourceCreateWithData(ArtifactPreviewFixtures.imageData as CFData, nil),
            let original = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return Data() }
        context.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        guard let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : Data()
    }
}
#endif
