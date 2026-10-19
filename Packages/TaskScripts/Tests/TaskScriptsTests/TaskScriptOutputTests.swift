import Foundation
import TaskScripts
import Testing

struct TaskScriptOutputTests {
    @Test func showsWhatAProgressBarLastDrewAndDropsColors() {
        var output = TaskScriptOutput()
        output.append(Data("Resolving\r\n10%\r55%\r100%\n\u{1B}[32mdone\u{1B}[0m \u{1B}]0;title\u{07}ok\n".utf8))
        #expect(output.text == "Resolving\n100%\ndone ok\n")
        #expect(output.lastLines(2) == ["100%", "done ok"])
    }

    @Test func keepsTheNewestOutputPastItsLimit() {
        var output = TaskScriptOutput(limit: 20)
        output.append(Data("line one\nline two\n".utf8))
        output.append(Data("line three\n".utf8))
        // Cut back to a whole line, never mid-line.
        #expect(output.text == "line three\n")
        #expect(output.droppedBytes == 18)
    }

    @Test func nativesOwnLinesStartOnALineOfTheirOwn() {
        var output = TaskScriptOutput()
        output.append(Data("no newline".utf8))
        output.appendLine("› Project script")
        #expect(output.text == "no newline\n› Project script\n")
    }

    @Test func survivesACharacterSplitAcrossChunks() {
        var output = TaskScriptOutput()
        let bytes = Data("✓ installed\n".utf8)
        output.append(bytes.prefix(2))
        output.append(bytes.dropFirst(2))
        #expect(output.text == "✓ installed\n")
    }
}
