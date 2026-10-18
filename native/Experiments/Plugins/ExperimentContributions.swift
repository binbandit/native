import Experiments

/// A manifest's experiments (docs/plugins.md, Experiments): the ones it declares, and which of its
/// contributions each gate switches. Contributions are marked `"experiment": "<gate-id>"` in their
/// own JSON, which their types don't keep, so the marks are read from the manifest as written.
struct ExperimentContributions: Hashable, Sendable {
    var declared = ManifestExperimentList()
    var marks: [ContributionMark] = []

    init(declared: ManifestExperimentList = ManifestExperimentList(), marks: [ContributionMark] = []) {
        self.declared = declared
        self.marks = marks
    }

    /// Reads the whole manifest, and never fails: problems with the experiments are listed instead.
    init(manifest decoder: any Decoder) {
        guard let container = try? decoder.container(keyedBy: Key.self) else { return }
        declared = (try? container.decodeIfPresent(ManifestExperimentList.self, forKey: .experiments)) ?? .init()
        func entries(_ key: Key) -> [MarkedEntry] {
            (try? container.decodeIfPresent([MarkedEntry].self, forKey: key)) ?? []
        }
        let themes = try? container.nestedContainer(keyedBy: ThemeKey.self, forKey: .themes)
        func themeEntries(_ key: ThemeKey) -> [MarkedEntry] {
            (try? themes?.decodeIfPresent([MarkedEntry].self, forKey: key)) ?? []
        }
        let lists: [(ContributionMark.Kind, [MarkedEntry])] = [
            (.agent, entries(.agents)), (.mcpServer, entries(.mcpServers)), (.workflow, entries(.workflows)),
            (.codeTheme, themeEntries(.code)), (.accent, themeEntries(.accents)), (.iconSet, entries(.iconSets)),
            (.celebration, entries(.celebrations)),
        ]
        marks = lists.flatMap { kind, entries in
            entries.compactMap { entry in
                // MCP servers are known by name; everything else by id.
                guard let gate = entry.experiment, let id = kind == .mcpServer ? entry.name : entry.id else {
                    return nil
                }
                return ContributionMark(kind: kind, id: id, name: entry.name ?? id, gate: gate)
            }
        }
    }

    private enum Key: String, CodingKey {
        case experiments, agents, mcpServers, workflows, themes, iconSets, celebrations
    }

    private enum ThemeKey: String, CodingKey {
        case code, accents
    }

    /// Just the fields a mark needs; anything else in the entry is ignored, and nothing fails.
    private struct MarkedEntry: Decodable {
        var id: String?
        var name: String?
        var experiment: String?

        private enum Key: String, CodingKey {
            case id, name, experiment
        }

        init(from decoder: any Decoder) {
            let container = try? decoder.container(keyedBy: Key.self)
            func string(_ key: Key) -> String? {
                try? container?.decodeIfPresent(String.self, forKey: key)
            }
            id = string(.id)
            name = string(.name)
            experiment = string(.experiment)
        }
    }
}

extension ExperimentContributions: Codable {
    init(from decoder: any Decoder) throws {
        self.init(declared: try ManifestExperimentList(from: decoder))
    }

    /// Writes the declared experiments; marks live in the contributions they're on.
    func encode(to encoder: any Encoder) throws {
        try declared.encode(to: encoder)
    }
}

/// A contribution that's there only while a gate is on.
struct ContributionMark: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case agent
        case mcpServer = "MCP server"
        case workflow
        case codeTheme = "code theme"
        case accent
        case iconSet = "icon set"
        case celebration
    }

    let kind: Kind
    /// Its id (an MCP server's name), to find it among the manifest's contributions.
    let id: String
    let name: String
    /// The gate's id as the manifest writes it.
    let gate: String

    var place: String {
        "the \(kind.rawValue) “\(name)”"
    }
}
