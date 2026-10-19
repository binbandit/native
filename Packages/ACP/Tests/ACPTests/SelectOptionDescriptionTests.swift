import Foundation
import Testing

@testable import ACP

@Suite struct SelectOptionDescriptionTests {
    private func option(_ name: String, _ description: String?) throws -> ConfigOption.SelectOption {
        var fields: [String: String] = ["value": "v", "name": name]
        fields["description"] = description
        return try JSONDecoder().decode(ConfigOption.SelectOption.self, from: JSONEncoder().encode(fields))
    }

    @Test func dropsALeadingNameIgnoringCaseSpacesAndHyphens() throws {
        #expect(
            try option("Read-only", "Read only: looks around, asks before any edit").descriptionWithoutName
                == "Looks around, asks before any edit")
        #expect(
            try option("Full access", "FULL-ACCESS:   does everything").descriptionWithoutName == "Does everything")
    }

    @Test func keepsDescriptionsThatDontStartWithTheName() throws {
        // Claude Code's words, from captured wire data.
        #expect(
            try option("Manual", "Always ask before making changes").descriptionWithoutName
                == "Always ask before making changes")
        #expect(try option("Auto", "Note: asks when risky").descriptionWithoutName == "Note: asks when risky")
    }

    @Test func nothingLeftOrNoDescriptionIsNil() throws {
        #expect(try option("Auto", "Auto:").descriptionWithoutName == nil)
        #expect(try option("Auto", nil).descriptionWithoutName == nil)
    }
}
