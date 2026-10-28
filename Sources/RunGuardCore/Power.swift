import Foundation

@MainActor
public final class SleepAssertion {
    private var activity: NSObjectProtocol?

    public init() {}
    public var isActive: Bool { activity != nil }

    public func start(reason: String = "RunGuard session") {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: .idleSystemSleepDisabled,
            reason: reason
        )
    }

    public func stop() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }
}

public struct PowerStatus {
    public let batteryPercent: Int?
    public let isCharging: Bool?

    public static func read() -> PowerStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "batt"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8) else {
                return PowerStatus(batteryPercent: nil, isCharging: nil)
            }

            let percent = text.range(of: #"\d{1,3}(?=%)"#, options: .regularExpression)
                .flatMap { Int(text[$0]) }
            let charging: Bool? = text.contains("AC Power") ? true :
                (text.contains("Battery Power") ? false : nil)
            return PowerStatus(batteryPercent: percent, isCharging: charging)
        } catch {
            return PowerStatus(batteryPercent: nil, isCharging: nil)
        }
    }
}

public enum ThermalSafety {
    public static var isCritical: Bool {
        ProcessInfo.processInfo.thermalState == .critical
    }
}
