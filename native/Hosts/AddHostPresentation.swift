import NativeLink
import SwiftUI
import UserShell

extension EnvironmentValues {
    /// Opens Add Host over the main window (`openAddHost?()`); nil while remote hosts are off.
    /// Settings › Hosts and the device picker offer Add Host while it's set.
    @Entry var openAddHost: OpenAddHostAction?
}

/// What `openAddHost` holds: a value SwiftUI can compare, where a bare closure would make every
/// view reading it update whenever its parent does.
struct OpenAddHostAction: Equatable {
    fileprivate let id: UUID
    fileprivate let open: () -> Void

    func callAsFunction() {
        open()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

extension View {
    /// Add Host for everything inside this view: sets `openAddHost` and shows the sheet it opens,
    /// pairing into `hosts`. Nothing changes while remote hosts are off (`RemoteHosts.isEnabled`).
    func addHostPresentation(hosts: RemoteHosts) -> some View {
        modifier(AddHostPresenter(hosts: hosts))
    }
}

private struct AddHostPresenter: ViewModifier {
    let hosts: RemoteHosts
    @State private var isPresented = AddHostTesting.opensAtLaunch
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .environment(
                \.openAddHost, RemoteHosts.isEnabled ? OpenAddHostAction(id: id) { isPresented = true } : nil
            )
            .sheet(isPresented: $isPresented) {
                AddHostAttempt(hosts: hosts) { isPresented = false }
            }
    }
}

/// One Add Host attempt, for as long as its sheet shows: closing it stops whatever runs.
private struct AddHostAttempt: View {
    @State private var model: AddHostModel
    let close: () -> Void

    init(hosts: RemoteHosts, close: @escaping () -> Void) {
        _model = State(
            initialValue: AddHostModel(
                register: { paired in AddHostAttempt.register(paired, in: hosts) },
                environment: AddHostAttempt.shellEnvironment))
        self.close = close
    }

    var body: some View {
        AddHostSheet(model: model, close: close)
    }

    /// The login shell's environment, which carries the user's ssh-agent. SSH is Mac only.
    private static func shellEnvironment() async -> [String: String] {
        #if os(macOS)
        await LoginShell.environment()
        #else
        [:]
        #endif
    }

    /// Keeps the new pairing and connects to it: the one place Add Host hands a host to the app.
    private static func register(_ paired: PairedHost, in hosts: RemoteHosts) {
        hosts.add(paired)
    }
}

/// Launch arguments for checking Add Host in an isolated instance. Off by default, and only in
/// development builds.
enum AddHostTesting {
    /// `-NativeAddHostAtLaunch YES`: opens Add Host as the window appears, for automation.
    static var opensAtLaunch: Bool {
        #if DEBUG
        RemoteHosts.isEnabled && UserDefaults.standard.bool(forKey: "NativeAddHostAtLaunch")
        #else
        false
        #endif
    }

    /// `-NativeAddHostSSH <path>`: runs this instead of ssh, so the SSH path can be checked against
    /// a stand-in on a Mac without Remote Login.
    static var sshExecutable: String {
        #if DEBUG
        UserDefaults.standard.string(forKey: "NativeAddHostSSH") ?? "ssh"
        #else
        "ssh"
        #endif
    }
}
