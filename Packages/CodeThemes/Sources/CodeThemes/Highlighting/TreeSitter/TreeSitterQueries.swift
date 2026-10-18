import Foundation
import SwiftTreeSitter
import Synchronization

/// A grammar's compiled queries. Compiling takes milliseconds, so each grammar compiles once, on
/// first use, and every thread shares the result (queries are immutable; cursors are per use).
struct TreeSitterQueries: Sendable {
    let highlights: Query
    let injections: Query?
    /// Each highlight capture's role, by capture index; nil for captures that color nothing.
    let roles: [CodeTokenRole?]

    enum Failure: Error {
        case missingLanguage(TreeSitterGrammar)
        case missingFile(String)
    }

    /// Nil only when there's nothing to compile, and is remembered, so a broken grammar costs once.
    private static let compiled = Mutex<[TreeSitterGrammar: TreeSitterQueries?]>([:])

    static func shared(_ grammar: TreeSitterGrammar) -> TreeSitterQueries? {
        if let cached = compiled.withLock({ $0[grammar] }) {
            return cached
        }
        let queries = try? TreeSitterQueries(grammar)
        compiled.withLock { $0[grammar] = queries }
        return queries
    }

    init(_ grammar: TreeSitterGrammar) throws {
        guard let language = grammar.language else { throw Failure.missingLanguage(grammar) }
        let highlights = try Query(language: language, data: Self.source(grammar.highlightQueries))
        self.highlights = highlights
        injections = try grammar.injectionQuery.map { try Query(language: language, data: Self.source([$0])) }
        roles = (0..<highlights.captureCount).map { index in
            highlights.captureName(for: index).flatMap(grammar.role(forCapture:))
        }
    }

    /// The query files, joined in order.
    private static func source(_ files: [String]) throws -> Data {
        var source = Data()
        for file in files {
            guard let url = Bundle.module.url(forResource: file, withExtension: "scm", subdirectory: "Queries") else {
                throw Failure.missingFile(file)
            }
            source.append(try Data(contentsOf: url))
            source.append(0x0A)
        }
        return source
    }
}
