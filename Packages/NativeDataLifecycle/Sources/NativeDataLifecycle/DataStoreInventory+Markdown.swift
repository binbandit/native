extension DataStoreInventory {
    /// The inventory as docs/enterprise/data-lifecycle.md shows it: a summary table, then each store.
    var markdown: String {
        var lines = [
            "| Store | Owner | Records | Delete | Hold | Follow-up |",
            "| --- | --- | --- | --- | --- | --- |",
        ]
        for entry in entries {
            lines.append(
                "| `\(entry.id.rawValue)` | \(entry.ownership.label) | \(entry.records.rawValue)"
                    + " | \(entry.support.delete.label) | \(entry.support.hold.label)"
                    + " | \(entry.followUp.map { "`\($0.rawValue)`" } ?? "-") |")
        }
        for entry in entries {
            lines += ["", "### `\(entry.id.rawValue)`", "", entry.summary, ""]
            lines.append(
                "- **Owner:** \(entry.ownership.label) (\(entry.integration.label)). **Records:** "
                    + "\(entry.records.rawValue). **Holds:** "
                    + entry.content.sorted().map(\.label).joined(separator: ", ") + ".")
            lines.append(
                "- **Copies:** "
                    + entry.copies.map { "\($0.kind.label) \($0.location.markdown), \($0.format.description)" }
                    .joined(separator: "; ") + ".")
            lines.append("- **Retention:** \(entry.retention.description). **Today:** \(entry.today)")
            var support =
                "- **Export:** \(entry.support.export.label). **Delete:** \(entry.support.delete.label)."
                + " **Hold:** \(entry.support.hold.label)."
            if entry.needsTombstones {
                support +=
                    " **Tombstones:** reimported from "
                    + entry.reimportedFrom.map { "`\($0.rawValue)`" }.joined(separator: ", ") + "."
            }
            lines.append(support)
            let code = entry.owners.isEmpty ? "none" : entry.owners.map { "`\($0)`" }.joined(separator: ", ")
            lines.append(
                "- **Follow-up:** \(entry.followUp.map { "`\($0.rawValue)`" } ?? "none"). **Code:** \(code).")
        }
        return lines.joined(separator: "\n")
    }
}

extension DataLocation {
    var markdown: String {
        switch self {
        case .file(let root, let components): "`" + ([root.label] + components).joined(separator: "/") + "`"
        case .defaults(let keys): "defaults " + keys.map { "`\($0)`" }.joined(separator: ", ")
        case .keychain(let service): "Keychain service `\(service)`"
        case .gitRefs(let patterns): "repository " + patterns.map { "`\($0)`" }.joined(separator: ", ")
        case .elsewhere(let root, let text): "\(root.label): \(text)"
        case .undetermined: "location not determined"
        }
    }
}

extension DataOwnership {
    var label: String {
        switch self {
        case .native: "Native"
        case .externalAgent: "external agent"
        case .customer: "customer"
        case .operatingSystem: "operating system"
        case .unknown: "unknown"
        }
    }
}

extension DataIntegrationStatus {
    var label: String {
        switch self {
        case .verified: "verified in source"
        case .dormant: "dormant: no production caller"
        case .unknown(let reason): "unknown: \(reason)"
        }
    }
}

extension DataContentClass {
    var label: String {
        switch self {
        case .userContent: "user content"
        case .paths: "paths"
        case .commands: "commands"
        case .credentials: "credentials"
        case .credentialReferences: "credential references"
        case .identifiers: "identifiers"
        case .configuration: "configuration"
        case .diagnostics: "diagnostics"
        case .audit: "audit"
        case .cache: "cache"
        }
    }
}

extension DataCopyKind {
    var label: String {
        switch self {
        case .primary: "primary"
        case .writeAheadLog: "write-ahead log"
        case .sharedMemory: "shared memory"
        case .temporary: "temporary"
        case .trash: "trash"
        case .gitObjects: "git objects"
        case .reflog: "reflog"
        }
    }
}

extension DataSupportLevel {
    var label: String {
        switch self {
        case .adapterPending: "adapter pending"
        case .outsideNative: "outside Native"
        case .notApplicable: "-"
        }
    }
}

extension DataHoldSupport {
    var label: String {
        switch self {
        case .userActionsIgnoreHolds: "user deletes ignore holds"
        case .automaticPruningIgnoresHolds: "pruned automatically, ignoring holds"
        case .ownerOutsideNative: "owner outside Native"
        case .undetermined: "not determined"
        case .notApplicable: "-"
        }
    }
}
