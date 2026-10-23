import ACP
import Foundation

/// A message Native delivered to the agent on the user's (or a tool's) behalf: a turn's prompt, or
/// a message steered into a running turn. Agents don't echo live prompts, so this is the record.
public struct PromptEcho: Codable, Hashable, Sendable {
    public enum Origin: String, WireEnum {
        case user
        /// Sent from the queue when the previous turn ended.
        case queued
        /// Sent by Native's tools (orchestration, workflows).
        case task
        /// Native telling the agent its previous turn was interrupted.
        case recovery
        case unknown
    }

    public var text: String
    /// Added to a turn that was already running.
    public var steered: Bool
    public var origin: Origin
    /// The `session/prompt` request it came from; nil for Native's own messages.
    public var requestID: UUID?
    /// Whether the transcript shows it (`PromptParams.echo`).
    public var shown: Bool
    public var attachments: [EchoAttachment]
    /// The instructions that went ahead of it, if any did.
    public var preamble: PreambleMarker?

    public init(
        text: String, steered: Bool = false, origin: Origin = .user, requestID: UUID? = nil, shown: Bool = true,
        attachments: [EchoAttachment] = [], preamble: PreambleMarker? = nil
    ) {
        self.text = text
        self.steered = steered
        self.origin = origin
        self.requestID = requestID
        self.shown = shown
        self.attachments = attachments
        self.preamble = preamble
    }
}

/// A file or image that went with a message, as the transcript shows it (ACP's `MessageAttachment`).
public struct EchoAttachment: Codable, Hashable, Sendable {
    public var name: String
    public var url: URL?
    /// The image, base64-encoded; summaries leave it out.
    public var imageBase64: String?
    public var embeddedBase64: String?
    public var mimeType: String?

    public init(
        name: String, url: URL? = nil, imageBase64: String? = nil, embeddedBase64: String? = nil,
        mimeType: String? = nil
    ) {
        self.name = name
        self.url = url
        self.imageBase64 = imageBase64
        self.embeddedBase64 = embeddedBase64
        self.mimeType = mimeType
    }

    public init(_ attachment: MessageAttachment) {
        self.init(
            name: attachment.name, url: attachment.url, imageBase64: attachment.imageData?.base64EncodedString(),
            embeddedBase64: attachment.embeddedData?.base64EncodedString(), mimeType: attachment.mimeType)
    }

    public var messageAttachment: MessageAttachment {
        MessageAttachment(
            name: name, url: url, imageData: imageBase64.flatMap { Data(base64Encoded: $0) },
            embeddedData: embeddedBase64.flatMap { Data(base64Encoded: $0) }, mimeType: mimeType, isLocalFile: true)
    }

    /// Without embedded contents, for summaries every client gets on every change.
    var withoutImage: EchoAttachment {
        EchoAttachment(name: name, url: url)
    }
}

/// What the transcript shows where a preamble's instructions went (ACP's `PromptPreamble.Marker`).
public struct PreambleMarker: Codable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var symbol: String?

    public init(id: String, label: String, symbol: String? = nil) {
        self.id = id
        self.label = label
        self.symbol = symbol
    }

    public init(_ marker: PromptPreamble.Marker) {
        self.init(id: marker.id, label: marker.label, symbol: marker.symbol)
    }

    public var marker: PromptPreamble.Marker {
        PromptPreamble.Marker(id: id, label: label, symbol: symbol)
    }
}

/// Instructions to send ahead of a message (ACP's `PromptPreamble`).
public struct PromptPreambleSpec: Codable, Hashable, Sendable {
    public var marker: PreambleMarker
    public var instructions: String

    public init(marker: PreambleMarker, instructions: String) {
        self.marker = marker
        self.instructions = instructions
    }

    public init(_ preamble: PromptPreamble) {
        self.init(marker: PreambleMarker(preamble.marker), instructions: preamble.instructions)
    }

    public var preamble: PromptPreamble {
        PromptPreamble(marker: marker.marker, instructions: instructions)
    }
}
