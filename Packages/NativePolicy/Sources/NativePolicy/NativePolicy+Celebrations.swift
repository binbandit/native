import Foundation

extension NativePolicy {
    public struct Celebrations: Equatable, Sendable {
        /// False prevents celebration index, signature and pack requests, including automatic fetching.
        public var downloadsEnabled = true
        /// An internal mirror of Native-signed packs. Nil uses the configured release repository.
        public var baseURL: URL?
    }
}
