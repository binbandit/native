import Foundation

/// An organization's OpenTelemetry collector, over OTLP/HTTP with JSON bodies (gzip). Events are
/// log records named after the event; the organization's attributes join the resource.
public struct OTLPLogDestination: TelemetryDestination {
    public let url: URL
    public let headers: [String: String]
    public let attributes: [String: String]
    private let transport: any TelemetryTransport

    /// `url` is the collector's logs endpoint; a bare host gets OTLP's `/v1/logs` path.
    public init(
        url: URL, headers: [String: String] = [:], attributes: [String: String] = [:],
        transport: any TelemetryTransport = URLSessionTelemetryTransport()
    ) {
        self.url = url
        self.headers = headers
        self.attributes = attributes
        self.transport = transport
    }

    public var id: TelemetryDestinationID { .organization(url) }

    public var logsURL: URL {
        url.path().isEmpty || url.path() == "/" ? url.appending(path: "v1/logs") : url
    }

    public func send(_ batch: TelemetryBatch) async throws {
        var request = URLRequest(url: logsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = try Gzip.compress(OTLPEncoding.logs(batch, extraAttributes: attributes))
        let status = try await transport.send(request)
        guard (200..<300).contains(status) else { throw TelemetrySendError.status(status) }
    }
}

public enum TelemetrySendError: Error, Equatable {
    case status(Int)
}

/// Sends an HTTP request and returns its status code.
public protocol TelemetryTransport: Sendable {
    func send(_ request: URLRequest) async throws -> Int
}

public struct URLSessionTelemetryTransport: TelemetryTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> Int {
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }
}

/// OTLP's JSON encoding of `ExportLogsServiceRequest` (opentelemetry-proto, `logs/v1`).
enum OTLPEncoding {
    struct Request: Encodable {
        let resourceLogs: [ResourceLogs]
    }

    struct ResourceLogs: Encodable {
        let resource: Resource
        let scopeLogs: [ScopeLogs]
    }

    struct Resource: Encodable {
        let attributes: [KeyValue]
    }

    struct ScopeLogs: Encodable {
        let scope: Scope
        let logRecords: [LogRecord]
    }

    struct Scope: Encodable {
        let name: String
        let version: String
    }

    struct LogRecord: Encodable {
        let timeUnixNano: String
        let observedTimeUnixNano: String
        let severityNumber: Int
        let severityText: String
        let eventName: String
        let body: AnyValue
        let attributes: [KeyValue]
    }

    struct KeyValue: Encodable {
        let key: String
        let value: AnyValue
    }

    /// proto3 JSON writes 64-bit integers as strings.
    enum AnyValue: Encodable {
        case string(String)
        case int(Int64)

        enum CodingKeys: String, CodingKey {
            case stringValue, intValue
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .string(let value): try container.encode(value, forKey: .stringValue)
            case .int(let value): try container.encode(String(value), forKey: .intValue)
            }
        }
    }

    static func logs(_ batch: TelemetryBatch, extraAttributes: [String: String], now: Date = .now) throws -> Data {
        let resource = batch.resource
        var attributes: [KeyValue] = [
            KeyValue(key: "service.name", value: .string("native")),
            KeyValue(key: "service.instance.id", value: .string(resource.installationID.uuidString.lowercased())),
            KeyValue(key: "os.type", value: .string(resource.platform.rawValue)),
        ]
        if let version = resource.appVersion {
            attributes.append(KeyValue(key: "service.version", value: .string(version.description)))
        }
        if let version = resource.osVersion {
            attributes.append(KeyValue(key: "os.version", value: .string(version.description)))
        }
        attributes += extraAttributes.sorted { $0.key < $1.key }.map { KeyValue(key: $0.key, value: .string($0.value)) }
        let records = batch.records.map { record in
            LogRecord(
                timeUnixNano: nanoseconds(record.time),
                observedTimeUnixNano: nanoseconds(now),
                severityNumber: 9,
                severityText: "INFO",
                eventName: record.name.rawValue,
                body: .string(record.name.rawValue),
                attributes: [KeyValue(key: "event.name", value: .string(record.name.rawValue))]
                    + record.attributes.map { attribute in
                        switch attribute.value.kind {
                        case .int(let value): KeyValue(key: attribute.key.rawValue, value: .int(value))
                        case .token(let value): KeyValue(key: attribute.key.rawValue, value: .string(value))
                        }
                    })
        }
        let request = Request(resourceLogs: [
            ResourceLogs(
                resource: Resource(attributes: attributes),
                scopeLogs: [ScopeLogs(scope: Scope(name: "native.telemetry", version: "1"), logRecords: records)])
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(request)
    }

    private static func nanoseconds(_ date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1_000_000).rounded()) * 1000)
    }
}
