/// Two tasks started from one brief stay together in a list: the later one moves up to sit right
/// after the earlier, so the pair reads as one group. Only pairs with both tasks in the same list
/// are grouped; a pair split by a filter, or across lists, keeps each task where it was.
public enum TaskPairGrouping {
    /// Each list with its pairs together, in the position of the pair's first task in that list.
    public static func grouped<ID: Hashable>(_ lists: [[ID]], pairs: [[ID]]) -> [[ID]] {
        lists.map { list in
            let present = Set(list)
            let together = pairs.filter { $0.count > 1 && $0.allSatisfy(present.contains) }
            guard !together.isEmpty else { return list }
            let pairOf = Dictionary(
                together.flatMap { pair in pair.map { ($0, pair) } }, uniquingKeysWith: { first, _ in first })
            var placed: Set<ID> = []
            var result: [ID] = []
            for id in list where !placed.contains(id) {
                // The pair takes the place of whichever of its tasks comes first, in its own order.
                let group = pairOf[id] ?? [id]
                result += group
                placed.formUnion(group)
            }
            return result
        }
    }
}
