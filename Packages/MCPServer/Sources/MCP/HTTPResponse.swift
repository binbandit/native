import Foundation

/// An HTTP response. Every connection serves one request, so responses close it.
struct HTTPResponse: Sendable, Equatable {
    var status: Int
    var headers: [String: String] = [:]
    var body = Data()

    static func json(_ value: JSON, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: value.encoded())
    }

    func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(for: status))\r\n"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        // Even an empty 202 states its length, so clients don't wait for a body until the close.
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 411: "Length Required"
        case 413: "Content Too Large"
        case 431: "Request Header Fields Too Large"
        default: "Status \(status)"
        }
    }
}
