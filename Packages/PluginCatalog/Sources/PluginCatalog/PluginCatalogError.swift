public enum PluginCatalogError: Error, Equatable, Sendable {
    case malformedPublicKey
    case malformedSignature
    case signatureMismatch
    case malformedJSON
    case unsupportedSchema(Int)
    case duplicateID(String)
    case invalidEntry(id: String, field: PluginCatalogEntry.Field)
}
