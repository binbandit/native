import Foundation

/// Confirmation belongs to the model so every delete entry point has the same file promise.
struct ProjectFolderDeletion {
    let title: String
    let confirm: () -> Void
}
