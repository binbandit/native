import Foundation
import Testing

@testable import MCP

struct HTTPTests {
    private func parse(_ text: String, maxBodyBytes: Int = 1024) -> HTTPRequest.Parse {
        HTTPRequest.parse(Data(text.utf8), maxBodyBytes: maxBodyBytes)
    }

    @Test func parsesARequestWithItsBody() throws {
        guard
            case .complete(let request) = parse(
                "POST /mcp/abc?x=1 HTTP/1.1\r\nHost: 127.0.0.1:1\r\nContent-Length: 4\r\nX-A: 1\r\nx-a: 2\r\n\r\n{}{}")
        else {
            Issue.record("Expected a complete request")
            return
        }
        #expect(request.method == "POST")
        #expect(request.path == "/mcp/abc")
        #expect(request.header("HOST") == "127.0.0.1:1")
        #expect(request.header("x-a") == "1, 2")
        #expect(request.body == Data("{}{}".utf8))
    }

    @Test func waitsForTheWholeHeadAndBody() {
        guard case .incomplete = parse("POST /mcp/abc HTTP/1.1\r\nContent-Length: 4\r\n") else {
            Issue.record("Expected to wait for the rest of the head")
            return
        }
        guard case .incomplete = parse("POST /mcp/abc HTTP/1.1\r\nContent-Length: 4\r\n\r\n{}") else {
            Issue.record("Expected to wait for the rest of the body")
            return
        }
    }

    @Test(arguments: [
        ("POST /mcp/abc HTTP/1.1\r\nContent-Length: 2048\r\n\r\n", 413),
        ("POST /mcp/abc HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n", 411),
        ("POST /mcp/abc HTTP/1.1\r\nContent-Length: -1\r\n\r\n", 400),
        ("POST mcp HTTP/1.1\r\n\r\n", 400),
        ("GARBAGE\r\n\r\n", 400),
        ("POST /mcp/abc HTTP/1.1\r\nX-A: 1\r\n folded\r\n\r\n", 400),
    ])
    func rejectsRequestsItWontServe(text: String, status: Int) {
        guard case .rejected(let response) = parse(text) else {
            Issue.record("Expected a rejection")
            return
        }
        #expect(response.status == status)
    }

    @Test func rejectsAnEndlessHead() {
        let text = "POST /mcp/abc HTTP/1.1\r\n" + String(repeating: "X-Long: value\r\n", count: 4000)
        guard case .rejected(let response) = parse(text) else {
            Issue.record("Expected a rejection")
            return
        }
        #expect(response.status == 431)
    }

    @Test func responsesStateTheirLengthAndClose() {
        let response = HTTPResponse.json(["id": 1])
        let text = String(decoding: response.serialized(), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Content-Type: application/json\r\n"))
        #expect(text.contains("Content-Length: 8\r\n"))
        #expect(text.contains("Connection: close\r\n"))
        // Whole numbers keep no fraction, so integer request ids echo back as sent.
        #expect(text.hasSuffix("\r\n\r\n{\"id\":1}"))
    }
}
