#if canImport(UniformTypeIdentifiers)
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import TextInput

@Suite struct TextInputDropProviderTests {
    @MainActor
    @Test(arguments: [UTType.pdf, .plainText])
    func typedFileWithoutURLIsPreserved(type: UTType) async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(type.preferredFilenameExtension ?? "dat")
        let contents = Data("fixture document".utf8)
        try contents.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let provider = NSItemProvider()
        provider.registerFileRepresentation(
            forTypeIdentifier: type.identifier, fileOptions: .openInPlace, visibility: .all
        ) {
            completion in
            completion(source, false, nil)
            return nil
        }
        #expect(!provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        #expect(TextInputDropProvider.representation(of: provider) == .document(type.identifier))
        let copy = try await TextInputDropProvider.loadFile(provider, type: type.identifier)
        #expect(TextInputDropProvider.representation(of: provider) == .document(type.identifier))
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        try FileManager.default.removeItem(at: source)
        #expect(try Data(contentsOf: copy) == contents)
    }

    @Test func ordinaryTextKeepsNativeDrop() {
        let provider = NSItemProvider(object: "selected text" as NSString)
        #expect(TextInputDropProvider.representation(of: provider) == nil)
    }
}
#endif
