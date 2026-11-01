import ACP
import Foundation
import NativeHostProtocol
import Testing

struct HostCompactionTests {
    @Test func compactionSurvivesHostWireAndReplay() throws {
        let compactedAt = Date(timeIntervalSince1970: 200)
        let completion = try json(
            #"{"sessionUpdate":"compaction_update","compactionId":"compact-1","status":"completed"}"#)
        let events = [
            HostEvent(
                seq: 1, payload: .update(try json(#"{"sessionUpdate":"usage_update","used":22519,"size":258400}"#))),
            HostEvent(seq: 2, at: compactedAt, payload: .update(completion)),
        ]
        var live = SessionMirror()
        var replay = SessionMirror()
        for event in events {
            live.apply(event)
            replay.apply(try JSONDecoder().decode(HostEvent.self, from: JSONEncoder().encode(event)))
        }
        #expect(live.state.usage == nil)
        #expect(replay.state.usage == nil)
        #expect(live.state.contextCompactedAt == compactedAt)
        #expect(replay.state.contextCompactedAt == compactedAt)
        replay.apply(
            HostEvent(
                seq: 3, payload: .update(try json(#"{"sessionUpdate":"usage_update","used":19339,"size":258400}"#))))
        replay.apply(HostEvent(seq: 4, payload: .update(completion)))
        #expect(replay.state.usage?.used == 19_339)
        #expect(replay.state.contextCompactedAt == compactedAt)
    }

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }
}
