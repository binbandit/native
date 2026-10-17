import Foundation

extension URL {
    /// The folder's path as agents record it for `cwd`: no trailing slash, which a folder URL's
    /// `path()` keeps and which stops `session/list` matching the sessions started there. It isn't
    /// standardized either, since that turns `/private/tmp` into `/tmp` and agents compare paths
    /// as given.
    var folderPath: String {
        let path = path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
