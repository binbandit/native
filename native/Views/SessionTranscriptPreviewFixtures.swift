#if DEBUG
import SwiftUI

/// Inert conversations for checking return visits, including a session with no transcript yet.
enum SessionTranscriptPreviewFixtures {
    static func sessions(in app: AppModel) -> [SessionModel] {
        ["First task", "Second task", "Empty task"].enumerated().compactMap { index, title in
            guard let session = SessionModel.preview(in: app, title: title) else { return nil }
            if index < 2 {
                for turn in 1...12 {
                    session.previewExchange(
                        "Step \(turn) in \(title)",
                        reply: """
                            ## Result \(turn)

                            Scroll to an earlier result, switch tasks, and come back. This paragraph
                            should return to the same position in the transcript.

                            - The conversation stays available while another task is selected.
                            - Expanded activity and the reading position belong to this task.
                            """
                    )
                }
            }
            return session
        }
    }
}
#endif
