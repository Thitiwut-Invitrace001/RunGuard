import Darwin
import Foundation

enum ClosedLidHelperClient {
    private static let socketPath = "/var/run/com.runguard.closedlid.sock"

    static func request(_ command: String) -> String? {
        guard ["status", "enable", "disable", "heartbeat"].contains(command) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSignal: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard socketPath.utf8.count + 1 <= pathCapacity else { return nil }
        socketPath.withCString { path in
            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) {
                    _ = strlcpy($0, path, pathCapacity)
                }
            }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        let message = Array(command.utf8)
        let sent = message.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        guard sent == message.count else { return nil }
        shutdown(fd, SHUT_WR)

        var response = [UInt8](repeating: 0, count: 64)
        let received = recv(fd, &response, response.count, 0)
        guard received > 0 else { return nil }
        return String(bytes: response[..<received], encoding: .utf8)
    }
}
