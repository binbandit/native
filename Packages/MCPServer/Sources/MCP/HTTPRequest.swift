import Foundation

/// An HTTP/1.1 request, as much of one as an MCP endpoint needs.
struct HTTPRequest: Sendable {
    var method: String
    /// The request target's path, without any query.
    var path: String
    /// Keyed by lowercased name; repeated headers are joined with ", ".
    var headers: [String: String]
    var body: Data

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    enum Parse {
        case incomplete
        case complete(HTTPRequest)
        /// The bytes can't become a request we'll serve; answer with this and close.
        case rejected(HTTPResponse)
    }

    static let maxHeaderBytes = 32 * 1024

    /// Reads one request from the start of `buffer`, which holds everything received so far.
    static func parse(_ buffer: Data, maxBodyBytes: Int) -> Parse {
        guard let headerEnd = buffer.firstRange(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > maxHeaderBytes ? .rejected(HTTPResponse(status: 431)) : .incomplete
        }
        guard headerEnd.lowerBound - buffer.startIndex <= maxHeaderBytes else {
            return .rejected(HTTPResponse(status: 431))
        }
        let head = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.split(separator: "\r\n", omittingEmptySubsequences: false)[...]
        let requestLine = lines.popFirst()?.split(separator: " ", omittingEmptySubsequences: false) ?? []
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1."),
            let target = requestLine[1].split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first,
            target.hasPrefix("/")
        else {
            return .rejected(HTTPResponse(status: 400))
        }

        var headers: [String: String] = [:]
        for line in lines {
            // Obsolete line folding (a line starting with whitespace) is a request smuggling vector.
            guard let colon = line.firstIndex(of: ":"), let first = line.first, first != " ", first != "\t" else {
                return .rejected(HTTPResponse(status: 400))
            }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = headers[name].map { "\($0), \(value)" } ?? value
        }

        if headers["transfer-encoding"] != nil {
            // MCP clients send JSON with a known length; chunked bodies aren't worth supporting.
            return .rejected(HTTPResponse(status: 411))
        }
        var length = 0
        if let value = headers["content-length"] {
            guard let parsed = Int(value), parsed >= 0 else { return .rejected(HTTPResponse(status: 400)) }
            length = parsed
        }
        guard length <= maxBodyBytes else { return .rejected(HTTPResponse(status: 413)) }

        let bodyStart = headerEnd.upperBound
        guard buffer.endIndex - bodyStart >= length else { return .incomplete }
        return .complete(
            HTTPRequest(
                method: String(requestLine[0]),
                path: String(target),
                headers: headers,
                body: Data(buffer[bodyStart..<bodyStart + length])
            ))
    }
}
