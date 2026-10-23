import Foundation

extension ToolCallState {
    /// Artifacts remain visible beside command, read and MCP text presentations. Some agents put
    /// MCP content only in rawOutput; others repeat it in both places.
    public var artifacts: [TranscriptArtifact] {
        var result = content.compactMap { content -> TranscriptArtifact? in
            guard case .content(let block) = content else { return nil }
            return TranscriptArtifact(block)
        }
        let raw = rawOutput?["result"]?["content"] ?? rawOutput?["content"]
        if case .array(let blocks) = raw {
            for value in blocks {
                guard let encoded = try? JSONEncoder().encode(value),
                    let block = try? JSONDecoder().decode(ContentBlock.self, from: encoded),
                    let artifact = TranscriptArtifact(block), !result.contains(artifact)
                else { continue }
                result.append(artifact)
            }
        }
        // A read can return image bytes without their URI. Only attach an origin when the tool
        // identifies one image file, so reveal never points at a guessed source or another output.
        if kind == .read, result.count == 1, result[0].isImage, result[0].url == nil,
            locations.count == 1, let path = locations.first?.path, path.hasPrefix("/")
        {
            let url = URL(filePath: path)
            if TranscriptArtifact(name: url.lastPathComponent, url: url).isImage {
                result[0].url = url
                result[0].name = url.lastPathComponent
            }
        }
        return result
    }
}
