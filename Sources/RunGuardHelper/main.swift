import Darwin
import Foundation

private struct HelperState: Codable {
    let uid: UInt32
    let previousSleepDisabled: Int
    var lastHeartbeat: Date
}

private enum RunGuardHelper {
    private static let socketPath = "/var/run/com.runguard.closedlid.sock"
    private static let statePath = "/var/db/com.runguard.closedlid.state"
    private static let heartbeatTimeout: TimeInterval = 30
    private static var allowedUID: UInt32 = 0

    static func main() {
        guard getuid() == 0,
              CommandLine.arguments.count == 2,
              let uid = UInt32(CommandLine.arguments[1]) else {
            exit(EXIT_FAILURE)
        }
        allowedUID = uid
        signal(SIGPIPE, SIG_IGN)
        guard let listener = makeListener() else { exit(EXIT_FAILURE) }
        defer { close(listener); unlink(socketPath) }

        while true {
            var descriptor = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            let result = poll(&descriptor, 1, 5_000)
            if result > 0, descriptor.revents & Int16(POLLIN) != 0 {
                serveOne(listener)
            }
            restoreIfHeartbeatExpired()
        }
    }

    private static func makeListener() -> Int32? {
        _ = unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard socketPath.utf8.count + 1 <= pathCapacity else {
            close(fd)
            return nil
        }
        socketPath.withCString { path in
            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) {
                    _ = strlcpy($0, path, pathCapacity)
                }
            }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(socketPath, 0o666) == 0, listen(fd, 8) == 0 else {
            close(fd)
            unlink(socketPath)
            return nil
        }
        return fd
    }

    private static func serveOne(_ listener: Int32) {
        let client = accept(listener, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }

        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(client, &peerUID, &peerGID) == 0, peerUID == allowedUID else {
            reply("denied", to: client)
            return
        }

        var buffer = [UInt8](repeating: 0, count: 64)
        let count = recv(client, &buffer, buffer.count - 1, 0)
        guard count > 0,
              let command = String(bytes: buffer[..<count], encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            reply("invalid", to: client)
            return
        }

        switch command {
        case "status": reply(readState() == nil ? "ready" : "active", to: client)
        case "enable": reply(enable() ? "ok" : "error", to: client)
        case "disable": reply(disable() ? "ok" : "error", to: client)
        case "heartbeat": reply(heartbeat() ? "ok" : "off", to: client)
        default: reply("invalid", to: client)
        }
    }

    private static func reply(_ text: String, to client: Int32) {
        _ = text.withCString { send(client, $0, strlen($0), 0) }
    }

    private static func enable() -> Bool {
        var state = readState() ?? HelperState(
            uid: allowedUID,
            previousSleepDisabled: currentSleepDisabled(),
            lastHeartbeat: Date()
        )
        guard state.uid == allowedUID else { return false }
        state.lastHeartbeat = Date()
        guard writeState(state), setSleepDisabled(1) else {
            removeState()
            return false
        }
        return true
    }

    private static func disable() -> Bool {
        guard let state = readState() else { return true }
        guard state.uid == allowedUID, setSleepDisabled(state.previousSleepDisabled) else { return false }
        removeState()
        return true
    }

    private static func heartbeat() -> Bool {
        guard var state = readState(), state.uid == allowedUID else { return false }
        state.lastHeartbeat = Date()
        return writeState(state)
    }

    private static func restoreIfHeartbeatExpired() {
        guard let state = readState(),
              Date().timeIntervalSince(state.lastHeartbeat) > heartbeatTimeout else { return }
        if setSleepDisabled(state.previousSleepDisabled) { removeState() }
    }

    private static func currentSleepDisabled() -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(separator: "\n") where line.contains("SleepDisabled") {
                return Int(line.split(whereSeparator: \.isWhitespace).last ?? "0") ?? 0
            }
        } catch { }
        return 0
    }

    private static func setSleepDisabled(_ value: Int) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", value == 1 ? "1" : "0"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 && currentSleepDisabled() == value
        } catch {
            return false
        }
    }

    private static func readState() -> HelperState? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: statePath)) else { return nil }
        return try? PropertyListDecoder().decode(HelperState.self, from: data)
    }

    private static func writeState(_ state: HelperState) -> Bool {
        guard let data = try? PropertyListEncoder().encode(state) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: statePath), options: .atomic)
            return chmod(statePath, 0o600) == 0
        } catch {
            return false
        }
    }

    private static func removeState() {
        _ = unlink(statePath)
    }
}

RunGuardHelper.main()
