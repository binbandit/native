import Foundation

extension NativePolicy {
    /// Both inputs must already have symlinks resolved by the local platform adapter. Component
    /// boundaries prevent an approved /work from permitting /work-private.
    public func allowsFolder(_ canonicalPath: String, canonicalRoots: [String]?) -> Bool {
        guard decision(for: .folderAdd).isPermitted else { return false }
        guard foldersAllowedRoots != nil else { return true }
        guard let roots = canonicalRoots else { return false }
        return roots.contains { root in
            canonicalPath == root || canonicalPath.hasPrefix(root == "/" ? "/" : root + "/")
        }
    }
}
