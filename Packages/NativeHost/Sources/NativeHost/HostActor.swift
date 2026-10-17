/// Where all of the host's state lives: sessions, agents, clients and the store. One serial
/// executor keeps the turn bookkeeping simple and in order; nothing on it blocks (agents and clients
/// are read and written asynchronously).
@globalActor
public actor HostActor {
    public static let shared = HostActor()
}
