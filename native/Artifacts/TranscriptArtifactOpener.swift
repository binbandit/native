import ACP

/// Stable environment identity, so a streaming task does not invalidate every artifact button.
struct TranscriptArtifactOpener: Equatable {
    let session: SessionModel?
    let filesAreLocal: Bool

    func open(_ artifact: TranscriptArtifact) {
        session?.openArtifact(artifact, filesAreLocal: filesAreLocal)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.session === rhs.session && lhs.filesAreLocal == rhs.filesAreLocal
    }
}
