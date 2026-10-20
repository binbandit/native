import Foundation
import NativeOrchestration

// The tasks sessions handed each other through Native's tools (`HostTasks.swift`), kept for good so
// a parent and its siblings reach a task across host restarts. A row holds the engine's record as
// JSON; its id is a column too, since that's what it's replaced by.
extension HostStore {
    /// Created by the schema's version 8 step.
    static let tasksTable = """
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            created_at REAL NOT NULL,
            record TEXT NOT NULL
        );
        """

    /// Adds a task, or replaces its record (its session moved to a fresh agent session).
    func saveTask(_ task: OrchestrationTask) throws {
        try database.run(
            """
            INSERT INTO tasks (id, created_at, record) VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET record = excluded.record
            """,
            .text(task.id), .date(task.createdAt ?? .now), try JSONColumn.encode(task))
    }

    /// Every task, oldest first.
    func tasks() throws -> [OrchestrationTask] {
        try database.query("SELECT record FROM tasks ORDER BY created_at, rowid").compactMap {
            $0.first.flatMap { JSONColumn.decode(OrchestrationTask.self, $0) }
        }
    }
}
