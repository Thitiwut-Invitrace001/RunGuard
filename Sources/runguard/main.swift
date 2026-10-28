import Foundation
import RunGuardCore
import Darwin

@MainActor
@main
enum RunGuardCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.first == "--", arguments.count > 1 else {
            fputs("Usage: runguard -- <command> [arguments…]\n", stderr)
            exit(64)
        }

        let assertion = SleepAssertion()
        assertion.start(reason: "RunGuard command")

        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        command.arguments = Array(arguments.dropFirst(1))
        command.standardInput = FileHandle.standardInput
        command.standardOutput = FileHandle.standardOutput
        command.standardError = FileHandle.standardError

        do {
            try command.run()
            command.waitUntilExit()
            assertion.stop()
            exit(command.terminationStatus)
        } catch {
            assertion.stop()
            fputs("runguard: \(error.localizedDescription)\n", stderr)
            exit(127)
        }
    }
}
