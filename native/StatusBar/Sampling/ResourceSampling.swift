/// Where the status bar's memory and CPU figures come from. `ProcessSampler` reads this Mac's
/// processes; a client of a remote host (Native on iPad) would ask the host instead, since the
/// agents run there.
nonisolated protocol ResourceSampling: Sendable {
    /// Samples the app (or host) itself, each agent tree in `agents`, and its other descendants.
    func sample(agents: [ProcessSampler.Root]) async -> ResourceSnapshot
}

extension ProcessSampler: ResourceSampling {}
