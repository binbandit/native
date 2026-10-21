extension TurnSummary.ChangedFile {
    /// Adds changes found outside edit tools, keeping reported files first and using the detected
    /// net counts when both sources name a file. Missing detections keep the reported edit: it may
    /// be outside the repository or have been undone. The caller identifies equivalent path spellings.
    public static func merging(
        reported: [Self], detected: [Self], pathKey: (String) -> String
    ) -> [Self] {
        let observed = Dictionary(detected.map { (pathKey($0.path), $0) }) { _, last in last }
        var indices: [String: Int] = [:]
        var files: [Self] = []
        for file in reported {
            let key = pathKey(file.path)
            if let index = indices[key] {
                if observed[key] == nil {
                    files[index].added += file.added
                    files[index].removed += file.removed
                }
                continue
            }
            indices[key] = files.count
            let counts = observed[key] ?? file
            files.append(Self(path: file.path, added: counts.added, removed: counts.removed))
        }
        for file in detected {
            let key = pathKey(file.path)
            guard indices[key] == nil else { continue }
            indices[key] = files.count
            files.append(observed[key] ?? file)
        }
        return files
    }
}
