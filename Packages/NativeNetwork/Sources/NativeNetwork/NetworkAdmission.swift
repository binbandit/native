import Foundation
import NativePolicy

public struct NetworkFailure: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Reason: String, Sendable {
        case unknownService, invalidPolicy, unavailablePolicy, disabled, localDenied, offMachineDenied
        case destinationDenied, invalidDestination, unsupportedScheme, integrationRequired
        case redirectDenied, tooManyRedirects, finalOriginMismatch, revoked, transportFailed, cancelled
    }
    // Unknown caller-provided ids are never echoed: they may contain content.
    public let service: NativePolicy.NetworkService?
    public let reason: Reason
    public var description: String { "\(service?.rawValue ?? "unknown-service"):\(reason.rawValue)" }

    public init(service: NativePolicy.NetworkService?, reason: Reason) {
        self.service = service
        self.reason = reason
    }
}

public enum NetworkDestination: Sendable {
    case url(URL)
    case localIPC
}

public enum NetworkAdmission {
    public static func check(serviceID: String, destination: NetworkDestination, policy: NativePolicy.Network?) throws {
        guard let service = NativePolicy.NetworkService(rawValue: serviceID) else {
            throw NetworkFailure(service: nil, reason: .unknownService)
        }
        try check(service: service, destination: destination, policy: policy)
    }

    public static func checkService(service: NativePolicy.NetworkService, policy: NativePolicy.Network?) throws {
        guard let policy else { throw NetworkFailure(service: service, reason: .unavailablePolicy) }
        guard policy.isValid else { throw NetworkFailure(service: service, reason: .invalidPolicy) }
        guard policy.services[service]?.enabled != false else {
            throw NetworkFailure(service: service, reason: .disabled)
        }
        if policy.mode != .ordinary {
            guard policy.services[service]?.enabled == true else {
                throw NetworkFailure(service: service, reason: .disabled)
            }
            guard NetworkInventory.declaration(service).integration == .mediated else {
                throw NetworkFailure(service: service, reason: .integrationRequired)
            }
        }
    }

    public static func check(
        service: NativePolicy.NetworkService, destination: NetworkDestination, policy: NativePolicy.Network?
    ) throws {
        func deny(_ reason: NetworkFailure.Reason) throws { throw NetworkFailure(service: service, reason: reason) }
        try checkService(service: service, policy: policy)
        guard let policy else { return try deny(.unavailablePolicy) }
        let rule = policy.services[service]
        let declaration = NetworkInventory.declaration(service)
        switch destination {
        case .localIPC:
            guard declaration.location == .local, policy.localIPC else { return try deny(.localDenied) }
        case .url(let url):
            guard let origin = NetworkOrigin(url: url) else { return try deny(.invalidDestination) }
            if origin.isLoopback {
                guard policy.localIPC else { return try deny(.localDenied) }
            } else {
                guard declaration.location != .local else { return try deny(.destinationDenied) }
                guard policy.mode != .airGapped else { return try deny(.offMachineDenied) }
            }
            // HTTP is only supported for literal loopback; TLS verification is never bypassed.
            guard origin.scheme != "http" || origin.isLoopback else { return try deny(.unsupportedScheme) }
            if policy.mode != .ordinary || rule != nil {
                guard rule?.enabled == true, rule?.origins.contains(origin) == true else {
                    return try deny(.destinationDenied)
                }
            }
        }
    }
}
