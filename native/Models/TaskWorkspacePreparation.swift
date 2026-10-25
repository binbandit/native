import Foundation

/// Creation ownership travels with the folder so a canceled start never deletes a borrowed checkout.
struct TaskWorkspacePreparation {
    let folder: URL
    let createdForTask: Bool
}
