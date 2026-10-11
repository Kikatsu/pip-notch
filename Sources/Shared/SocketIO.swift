import Foundation
import Darwin

/// Minimal blocking Unix-socket helpers shared by the app and the bridge.
enum SocketIO {
    static func makeAddress(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < capacity else { return nil }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strncpy($0, path, capacity - 1) }
        }
        return addr
    }

    static func disableSigpipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Connects to the socket at `path`; returns -1 when nothing is listening.
    static func connect(to path: String) -> Int32 {
        guard var addr = makeAddress(path) else { return -1 }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        disableSigpipe(fd)
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, len) }
        }
        if rc != 0 {
            close(fd)
            return -1
        }
        return fd
    }

    @discardableResult
    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard var ptr = raw.baseAddress else { return true }
            var remaining = raw.count
            while remaining > 0 {
                let n = write(fd, ptr, remaining)
                if n < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                remaining -= n
                ptr = ptr.advanced(by: n)
            }
            return true
        }
    }

    /// Reads up to the first newline. Returns nil on timeout, EOF or oversize input.
    static func readLine(_ fd: Int32, timeout: TimeInterval) -> Data? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return nil }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, Int32(min(remaining, 60) * 1000))
            if ready < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if ready == 0 { continue }
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return nil }
            buffer.append(chunk, count: n)
            if let newline = buffer.firstIndex(of: 0x0A) {
                return Data(buffer[buffer.startIndex..<newline])
            }
            if buffer.count > 8_000_000 { return nil }
        }
    }
}
