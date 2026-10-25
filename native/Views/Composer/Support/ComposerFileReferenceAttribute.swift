import ACP
import Foundation
import SwiftUI

/// Semantic identity survives the text editor's undo stack, unlike a visible basename alone.
nonisolated struct ComposerFileReferenceAttribute: AttributedStringKey {
    struct Value: Hashable, Sendable {
        let raw: String
        let display: String
    }

    static let name = "dev.binbandit.native.file-reference"
    static let inheritedByAddedText = false
    static let invalidationConditions: Set<AttributedString.AttributeInvalidationCondition>? = [.textChanged]

    struct Scope: AttributeScope {
        let swiftUI: AttributeScopes.SwiftUIAttributes
        let reference: ComposerFileReferenceAttribute
    }

    static func restoredTokens(in text: AttributedString) -> [FileReferenceProjection.RestoredToken] {
        text.runs[Self.self].compactMap { value, range in
            guard let value, String(text[range].characters) == value.display else { return nil }
            let lower = text.utf8.distance(from: text.startIndex, to: range.lowerBound)
            let upper = text.utf8.distance(from: text.startIndex, to: range.upperBound)
            return .init(
                display: lower..<upper,
                raw: value.raw)
        }
    }
}
