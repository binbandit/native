import Foundation
import NativeHostProtocol

/// Takes one method's notifications for a `NativeHostClient` instead of them becoming `Event`s:
/// what only one caller cares about, such as a remote command's output. Routes run in order with the
/// client's event handlers, so a request's answer still arrives after everything sent before it. Like
/// an event handler, a route must never wait on a request to the same client.
protocol HostNotificationRoute: AnyObject, Sendable {
    func receive(_ message: JSONRPCPeer.Message) async
}

extension NativeHostClient {
    /// The client's route for `method`, made the first time it's asked for.
    func route<Route: HostNotificationRoute>(_ method: String, make: () -> Route) -> Route {
        if let route = notificationRoutes[method] as? Route { return route }
        let route = make()
        notificationRoutes[method] = route
        return route
    }
}
