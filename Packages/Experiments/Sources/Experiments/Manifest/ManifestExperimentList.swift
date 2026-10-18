/// A manifest's `experiments`, decoded one at a time: a malformed entry becomes a problem and the
/// others still load.
public struct ManifestExperimentList: Codable, Hashable, Sendable {
    public var valid: [ManifestExperiment]
    public var malformed: [ManifestExperimentProblem]

    public init(_ valid: [ManifestExperiment] = [], malformed: [ManifestExperimentProblem] = []) {
        self.valid = valid
        self.malformed = malformed
    }

    public var isEmpty: Bool { valid.isEmpty && malformed.isEmpty }

    public init(from decoder: any Decoder) throws {
        self.init()
        guard let entries = try? decoder.singleValueContainer().decode([Entry].self) else {
            malformed = [ManifestExperimentProblem(experiment: nil, message: "\"experiments\" should be a list.")]
            return
        }
        for entry in entries {
            switch entry.result {
            case .success(let experiment): valid.append(experiment)
            case .failure(let problem): malformed.append(problem)
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(valid)
    }

    /// Decoding never fails, so the list moves on to the next entry.
    private struct Entry: Decodable {
        let result: Result<ManifestExperiment, ManifestExperimentProblem>

        init(from decoder: any Decoder) {
            do {
                result = .success(try ManifestExperiment(from: decoder))
            } catch {
                let id = try? decoder.container(keyedBy: ManifestExperiment.CodingKeys.self)
                    .decode(String.self, forKey: .id)
                result = .failure(ManifestExperimentProblem(experiment: id, message: Self.describe(error)))
            }
        }

        private static func describe(_ error: any Error) -> String {
            switch error {
            case DecodingError.keyNotFound(let key, _): "Missing \"\(key.stringValue)\"."
            case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context),
                DecodingError.dataCorrupted(let context):
                "Wrong value at \"\(context.codingPath.map(\.stringValue).joined(separator: "."))\"."
            default: "It couldn't be read."
            }
        }
    }
}
