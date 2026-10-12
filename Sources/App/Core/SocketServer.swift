import Foundation
import Darwin

/// Accepts connections from pip-bridge on a Unix socket and hands events to the main thread.
final class SocketServer {
    let path: String
    /// Called on the main thread. `connection` is non-nil only for blocking events.
    var onEvent: ((HookEnvelope, BridgeConnection?) -> Void)?

    private var listenFD: Int32 = -1
    /// Inode of the socket file we bound, to notice when something replaces or deletes it.
    private var boundInode: ino_t = 0
    private var watchdog: DispatchSourceTimer?
    private let workQueue = DispatchQueue(label: "pip.socket.clients", attributes: .concurrent)

    init(path: String = PipPaths.socketPath) {
        self.path = path
    }

    func start() throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Another Pip is already listening; taking its socket would leave whichever of us
        // quits first with a dead file and every hook event dropped.
        if Self.isLive(path) { throw ServerError.alreadyRunning }
        unlink(path)

        guard var addr = SocketIO.makeAddress(path) else { throw ServerError.pathTooLong }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.posix(errno) }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
        }
        guard bound == 0, listen(fd, 32) == 0 else {
            let code = errno
            close(fd)
            throw ServerError.posix(code)
        }
        chmod(path, 0o600)
        listenFD = fd
        boundInode = Self.inode(of: path) ?? 0

        let thread = Thread { [weak self] in self?.acceptLoop(fd) }
        thread.name = "pip.socket.accept"
        thread.start()
        startWatchdog()
    }

    func stop() {
        watchdog?.cancel()
        watchdog = nil
        // Only remove the file we bound; it may now belong to another running Pip.
        let ours = boundInode != 0 && Self.inode(of: path) == boundInode
        closeListener()
        if ours { unlink(path) }
    }

    private func closeListener() {
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        boundInode = 0
    }

    /// If our socket file is deleted or replaced by a process that then exits,
    /// bind a fresh one so hooks reach us again.
    private func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in self?.checkSocketFile() }
        watchdog = timer
        timer.resume()
    }

    private func checkSocketFile() {
        guard Self.inode(of: path) != boundInode || listenFD < 0, !Self.isLive(path) else { return }
        Log.events.notice("Socket at \(self.path, privacy: .public) was replaced or removed; rebinding")
        closeListener()
        do {
            try start()
        } catch {
            Log.events.error("Could not rebind socket: \(String(describing: error), privacy: .public)")
        }
    }

    private static func isLive(_ path: String) -> Bool {
        let fd = SocketIO.connect(to: path)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }

    private static func inode(of path: String) -> ino_t? {
        var info = stat()
        return lstat(path, &info) == 0 ? info.st_ino : nil
    }

    deinit {
        stop()
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            SocketIO.disableSigpipe(client)
            workQueue.async { [weak self] in self?.serve(client) }
        }
    }

    private func serve(_ fd: Int32) {
        guard let line = SocketIO.readLine(fd, timeout: 5), let envelope = HookEnvelope(data: line) else {
            close(fd)
            return
        }
        let connection = envelope.isBlocking ? BridgeConnection(fd: fd) : nil
        if connection == nil { close(fd) }
        DispatchQueue.main.async { [weak self] in
            guard let self, let onEvent = self.onEvent else {
                connection?.finish(nil)
                return
            }
            onEvent(envelope, connection)
        }
    }

    enum ServerError: Error {
        case pathTooLong
        case alreadyRunning
        case posix(Int32)
    }
}

/// A bridge process waiting for an answer. Main-thread only.
final class BridgeConnection {
    private let fd: Int32
    private var source: DispatchSourceRead?
    private var finished = false

    init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        finish(nil)
    }

    /// Calls `onHangup` if the bridge goes away before we answer (the user pressed Esc, the agent died).
    func watchForHangup(_ onHangup: @escaping () -> Void) {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var byte: UInt8 = 0
            if recv(self.fd, &byte, 1, MSG_PEEK) <= 0 {
                self.finish(nil)
                onHangup()
            }
        }
        source.setCancelHandler { [fd] in close(fd) }
        self.source = source
        source.resume()
    }

    /// Sends the decision (or nothing, for pass-through) and closes the connection.
    func finish(_ decision: ApprovalDecision?) {
        guard !finished else { return }
        finished = true
        var reply: [String: Any]?
        switch decision {
        case .allow: reply = ["decision": "allow"]
        case .deny(let message): reply = ["decision": "deny", "message": message ?? "The user denied this from Pip."]
        case .passthrough, nil: reply = nil
        }
        if let reply, var data = try? JSONSerialization.data(withJSONObject: reply) {
            data.append(0x0A)
            SocketIO.writeAll(fd, data)
        }
        if let source {
            source.cancel()
        } else {
            close(fd)
        }
    }
}
