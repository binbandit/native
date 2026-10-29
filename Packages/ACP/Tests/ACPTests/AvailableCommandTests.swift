import Foundation
import Testing

@testable import ACP

@Suite struct AvailableCommandTests {
    @Test(arguments: [
        ("review", "/review"),
        ("compact", "/compact"),
        ("plugin:check", "/plugin:check"),
        ("$review", "$review"),
        ("$plugin:check", "$plugin:check"),
        ("$déployer", "$déployer"),
        ("cash$flow", "/cash$flow"),
    ])
    func invocationPreservesSkillPrefixes(name: String, expected: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["name": name, "description": "Fixture"])
        let command = try JSONDecoder().decode(AvailableCommand.self, from: data)
        #expect(command.name == name)
        #expect(command.invocation == expected)
    }
}
