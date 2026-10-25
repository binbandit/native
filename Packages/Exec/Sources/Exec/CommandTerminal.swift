#if os(macOS) || os(Linux)
import Foundation

/// A private terminal for a CLI, with terminal echo disabled. A CLI may still print its own input,
/// so sign-in callers must treat all captured output as sensitive and never log it.
final class CommandTerminal {
    let slave: FileHandle
    let output: FileHandle
    private let channel: DispatchIO
    private let queue = DispatchQueue(label: "Exec.CommandTerminal.input")

    init() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var size = winsize(ws_row: 24, ws_col: 4096, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        _ = fcntl(master, F_SETFD, FD_CLOEXEC)
        _ = fcntl(slave, F_SETFD, FD_CLOEXEC)
        var attributes = termios()
        if tcgetattr(slave, &attributes) == 0 {
            attributes.c_lflag &= ~tcflag_t(ECHO | ECHONL)
            _ = tcsetattr(slave, TCSANOW, &attributes)
        }
        self.slave = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        let reader = fcntl(master, F_DUPFD_CLOEXEC, 0)
        guard reader >= 0 else {
            close(master)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EMFILE)
        }
        output = FileHandle(fileDescriptor: reader, closeOnDealloc: true)
        let descriptor = master
        channel = DispatchIO(type: .stream, fileDescriptor: descriptor, queue: queue) { _ in close(descriptor) }
    }

    func forward(_ input: CommandInput) -> Task<Void, Never> {
        let channel = channel
        let queue = queue
        return Task {
            for await data in input.chunks {
                guard !Task.isCancelled else { break }
                await withCheckedContinuation { continuation in
                    channel.write(offset: 0, data: data.withUnsafeBytes { DispatchData(bytes: $0) }, queue: queue) {
                        done, _, _ in
                        if done { continuation.resume() }
                    }
                }
            }
        }
    }

    func stop() {
        try? slave.close()
        channel.close(flags: .stop)
    }

    deinit { stop() }
}
#endif
