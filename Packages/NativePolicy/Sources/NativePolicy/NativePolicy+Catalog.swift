import Foundation

extension NativePolicy {
    /// Inputs for a future catalog consumer; these values perform no fetching or enforcement.
    public struct Catalog: Equatable, Sendable {
        /// Whether the catalog consumer may fetch. Defaults to allowed without starting any network activity.
        public var isEnabled = true
        /// A mirror index URL. Nil leaves endpoint selection to the future consumer.
        public var indexURL: URL?
    }
}
