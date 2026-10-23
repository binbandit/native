/// Rebinds conversation history when a task keeps its identity but its agent gives it a new key.
public enum ConversationLinks {
    public static func replacing<Key: Hashable>(
        _ old: Key, with replacement: Key, in links: [Key: Key], kept: Set<Key>
    ) -> (links: [Key: Key], kept: Set<Key>) {
        var result: [Key: Key] = [:]
        for (later, earlier) in links {
            result[later == old ? replacement : later] = earlier == old ? replacement : earlier
        }
        var retained = kept
        if retained.remove(old) != nil { retained.insert(replacement) }
        return (result, retained)
    }
}
