import AppKit
import Foundation
import RunGuardCore
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let assertion = SleepAssertion()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let menuModel = RunGuardMenuModel()
    private var pollTimer: Timer?
    private var expiryTimer: Timer?
    private var awakeRequested = false
    private var autoMode = false
    private var chargingOnly = false
    private var watchdogEnabled = false
    private var closedLidEnabled = false
    private var workloadFound = false
    private let watchdog = Watchdog()
    private var pauseReason: String?
    private var power = PowerStatus.read()
    private var timerEnd: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        autoMode = UserDefaults.standard.bool(forKey: "autoMode")
        chargingOnly = UserDefaults.standard.bool(forKey: "chargingOnly")
        watchdogEnabled = UserDefaults.standard.bool(forKey: "watchdogEnabled")
        if UserDefaults.standard.bool(forKey: "closedLidEnabled") {
            if ClosedLidHelperClient.request("disable") == "ok" {
                UserDefaults.standard.set(false, forKey: "closedLidEnabled")
                addLog("Closed-Lid mode stopped on app launch")
            } else {
                closedLidEnabled = true
                addLog("RunGuard helper unavailable; sleep setting may still be disabled")
            }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "RunGuard")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 330, height: 460)
        popover.contentViewController = NSHostingController(rootView: RunGuardPopover(model: menuModel))
        menuModel.onAwake = { [weak self] in self?.toggleAwake() }
        menuModel.onAutoMode = { [weak self] in self?.toggleAutoMode() }
        menuModel.onChargingOnly = { [weak self] in self?.toggleChargingOnly() }
        menuModel.onClosedLid = { [weak self] in self?.toggleClosedLid() }
        menuModel.onWatchdog = { [weak self] in self?.toggleWatchdog() }
        menuModel.onTimer = { [weak self] minutes in self?.startTimer(minutes: minutes) }
        menuModel.onCancelTimer = { [weak self] in self?.cancelTimer() }
        menuModel.onActivity = { [weak self] in self?.showActivity() }
        menuModel.onQuit = { [weak self] in self?.quit() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        expiryTimer?.invalidate()
        assertion.stop()
        if closedLidEnabled { disableClosedLid(refreshUI: false) }
    }

    private func refresh() {
        if closedLidEnabled, ClosedLidHelperClient.request("heartbeat") == "off" {
            closedLidEnabled = false
            UserDefaults.standard.set(false, forKey: "closedLidEnabled")
            addLog("Closed-Lid helper restored normal sleep")
        }
        power = PowerStatus.read()
        let workloads = autoMode || watchdogEnabled ? WorkloadMonitor.running() : []
        workloadFound = autoMode && !workloads.isEmpty
        if watchdogEnabled {
            for message in watchdog.update(workloads) {
                addLog(message)
                sendNotification(message)
            }
        }

        if let timerEnd, Date() >= timerEnd {
            self.timerEnd = nil
            awakeRequested = false
            expiryTimer?.invalidate()
            expiryTimer = nil
            addLog("Timer finished")
        }

        let reason: String?
        if ThermalSafety.isCritical {
            reason = "Critical thermal pressure; released keep-awake"
        } else if let battery = power.batteryPercent, battery <= 20, power.isCharging == false {
            reason = "Battery at \(battery)%; released keep-awake"
        } else if chargingOnly && power.isCharging != true {
            reason = "Waiting for power"
        } else {
            reason = nil
        }

        if closedLidEnabled, reason != nil { disableClosedLid(refreshUI: false) }

        let requested = awakeRequested || workloadFound
        let canHold = reason == nil && requested
        if canHold != assertion.isActive {
            if canHold {
                assertion.start()
                addLog(workloadFound ? "Auto Mode started" : "Keep Awake started")
            } else {
                assertion.stop()
                if requested, let reason, reason != "Waiting for power", reason != pauseReason {
                    addLog(reason)
                } else if !requested, pauseReason == nil {
                    addLog("Keep-awake released")
                }
            }
        }
        pauseReason = reason
        statusItem.button?.image = NSImage(systemSymbolName: assertion.isActive ? "bolt.fill" : "bolt", accessibilityDescription: assertion.isActive ? "RunGuard active" : "RunGuard idle")
        statusItem.button?.contentTintColor = assertion.isActive ? .systemGreen : .secondaryLabelColor
        menuModel.status = statusText(reason: reason)
        menuModel.isActive = assertion.isActive
        menuModel.keepAwake = awakeRequested
        menuModel.autoMode = autoMode
        menuModel.chargingOnly = chargingOnly
        menuModel.closedLid = closedLidEnabled
        menuModel.watchdog = watchdogEnabled
        menuModel.timerActive = timerEnd != nil
        menuModel.timerRemaining = timerEnd.map { max(0, Int($0.timeIntervalSinceNow / 60)) } ?? 0
        menuModel.battery = power.batteryPercent
        menuModel.isCharging = power.isCharging
        menuModel.batteryTemperature = power.batteryTemperature
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    private func statusText(reason: String?) -> String {
        if assertion.isActive { return "Keeping awake" }
        if let reason { return reason }
        if let end = timerEnd { return "Timer active · \(max(0, Int(end.timeIntervalSinceNow / 60))) min" }
        if let battery = power.batteryPercent {
            return "Idle · Battery \(battery)% · \(power.isCharging == true ? "Charging" : "On battery")"
        }
        return "Idle"
    }

    @objc private func toggleAwake() {
        awakeRequested.toggle()
        if !awakeRequested { cancelTimer() }
        refresh()
    }

    @objc private func toggleAutoMode() {
        autoMode.toggle()
        UserDefaults.standard.set(autoMode, forKey: "autoMode")
        refresh()
    }

    @objc private func toggleChargingOnly() {
        chargingOnly.toggle()
        UserDefaults.standard.set(chargingOnly, forKey: "chargingOnly")
        refresh()
    }

    @objc private func toggleWatchdog() {
        watchdogEnabled.toggle()
        UserDefaults.standard.set(watchdogEnabled, forKey: "watchdogEnabled")
        if watchdogEnabled {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                guard !granted else { return }
                Task { @MainActor in self?.addLog("Watchdog alerts need notification permission") }
            }
        }
        refresh()
    }

    @objc private func toggleClosedLid() {
        if closedLidEnabled {
            disableClosedLid()
        } else {
            guard reasonForClosedLid() == nil else {
                addLog("Closed-Lid mode blocked by battery or thermal safety")
                refresh()
                return
            }
            guard ClosedLidHelperClient.request("enable") == "ok" else {
                addLog("Install the RunGuard helper before using Closed-Lid mode")
                let alert = NSAlert()
                alert.messageText = "RunGuard Helper Required"
                alert.informativeText = "Run ./install-runguard.sh from the RunGuard project folder. macOS will ask for administrator approval once to install the helper."
                alert.addButton(withTitle: "OK")
                alert.runModal()
                refresh()
                return
            }
            closedLidEnabled = true
            UserDefaults.standard.set(true, forKey: "closedLidEnabled")
            addLog("Closed-Lid mode enabled")
            refresh()
        }
    }

    private func reasonForClosedLid() -> String? {
        if ThermalSafety.isCritical { return "critical thermal pressure" }
        if let battery = power.batteryPercent, battery <= 20, power.isCharging == false {
            return "battery at or below 20%"
        }
        return nil
    }

    private func disableClosedLid(refreshUI: Bool = true) {
        guard ClosedLidHelperClient.request("disable") == "ok" else {
            addLog("Could not contact the RunGuard helper; sleep will restore after its heartbeat timeout")
            if refreshUI { refresh() }
            return
        }
        closedLidEnabled = false
        UserDefaults.standard.set(false, forKey: "closedLidEnabled")
        addLog("Closed-Lid mode disabled; previous sleep setting restored")
        if refreshUI { refresh() }
    }

    private func startTimer(minutes: Int) {
        awakeRequested = true
        let seconds = minutes * 60
        timerEnd = Date().addingTimeInterval(TimeInterval(seconds))
        expiryTimer?.invalidate()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        addLog("Timer started · \(minutes) minutes")
        refresh()
    }

    @objc private func cancelTimer() {
        timerEnd = nil
        expiryTimer?.invalidate()
        expiryTimer = nil
        refresh()
    }

    @objc private func showActivity() {
        let entries = UserDefaults.standard.stringArray(forKey: "activity") ?? []
        let alert = NSAlert()
        alert.messageText = "Recent Activity"
        alert.informativeText = entries.isEmpty ? "No activity yet." : entries.prefix(10).joined(separator: "\n")
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func addLog(_ message: String) {
        let line = "\(Date.now.formatted(date: .omitted, time: .shortened))  \(message)"
        var entries = UserDefaults.standard.stringArray(forKey: "activity") ?? []
        entries.insert(line, at: 0)
        UserDefaults.standard.set(Array(entries.prefix(50)), forKey: "activity")
    }

    private func sendNotification(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "RunGuard Watchdog"
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

@MainActor
private final class RunGuardMenuModel: ObservableObject {
    @Published var status = "Idle"
    @Published var isActive = false
    @Published var keepAwake = false
    @Published var autoMode = false
    @Published var chargingOnly = false
    @Published var closedLid = false
    @Published var watchdog = false
    @Published var timerActive = false
    @Published var timerRemaining = 0
    @Published var battery: Int?
    @Published var isCharging: Bool?
    @Published var batteryTemperature: Double?

    var onAwake: (() -> Void)?
    var onAutoMode: (() -> Void)?
    var onChargingOnly: (() -> Void)?
    var onClosedLid: (() -> Void)?
    var onWatchdog: (() -> Void)?
    var onTimer: ((Int) -> Void)?
    var onCancelTimer: (() -> Void)?
    var onActivity: (() -> Void)?
    var onQuit: (() -> Void)?
}

private struct RunGuardPopover: View {
    @ObservedObject var model: RunGuardMenuModel
    @State private var showingTimers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()

            VStack(spacing: 2) {
                settingRow("Keep Awake", detail: "Prevent idle sleep", symbol: "moon.zzz.fill", isOn: model.keepAwake, action: model.onAwake)
                settingRow("Auto Mode", detail: "Keep active work awake", symbol: "sparkles", isOn: model.autoMode, action: model.onAutoMode)
                settingRow("Only When Charging", detail: "Pause on battery", symbol: "powerplug.fill", isOn: model.chargingOnly, action: model.onChargingOnly)
                settingRow("Closed-Lid Mode", detail: "One-time helper setup", symbol: "laptopcomputer", isOn: model.closedLid, action: model.onClosedLid, badge: "ADMIN")
                settingRow("Watchdog", detail: "Alert on idle processes", symbol: "waveform.path", isOn: model.watchdog, action: model.onWatchdog)
            }

            VStack(spacing: 8) {
                Button { withAnimation(.easeInOut(duration: 0.18)) { showingTimers.toggle() } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "timer").frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.timerActive ? "Timer · \(model.timerRemaining) min left" : "Set a timer")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Keep awake for a set time").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: showingTimers ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showingTimers {
                    HStack(spacing: 7) {
                        timerButton("30 min", minutes: 30)
                        timerButton("1 hour", minutes: 60)
                        timerButton("3 hours", minutes: 180)
                        timerButton("8 hours", minutes: 480)
                    }
                    if model.timerActive {
                        Button("Cancel timer", action: { model.onCancelTimer?() })
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))

            HStack {
                Button("Recent Activity", systemImage: "clock.arrow.circlepath", action: { model.onActivity?() })
                Spacer()
                Button("Quit", systemImage: "power", action: { model.onQuit?() })
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 330)
        .background(.regularMaterial)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.gradient)
                Image(systemName: "bolt.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text("RunGuard").font(.system(size: 15, weight: .bold))
                Text(model.status).font(.system(size: 11, weight: .medium)).foregroundStyle(model.isActive ? .green : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let battery = model.battery {
                VStack(alignment: .trailing, spacing: 3) {
                    Image(systemName: model.isCharging == true ? "battery.100percent" : "battery.75percent")
                        .font(.system(size: 14, weight: .medium))
                    Text("\(battery)%").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
        }
        HStack(spacing: 7) {
            Image(systemName: "thermometer.medium").foregroundStyle(.secondary)
            Text("Battery temperature").foregroundStyle(.secondary)
            Spacer()
            Text(model.batteryTemperature.map { String(format: "%.1f°C", $0) } ?? "—")
                .fontWeight(.semibold)
        }
        .font(.system(size: 11))
        }
    }

    private func settingRow(_ title: String, detail: String, symbol: String, isOn: Bool, action: (() -> Void)?, badge: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    if let badge {
                        Text(badge).font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                }
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Toggle(title, isOn: Binding(get: { isOn }, set: { _ in action?() }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isOn ? Color.accentColor.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
    }

    private func timerButton(_ title: String, minutes: Int) -> some View {
        Button(title) { model.onTimer?(minutes) }
            .font(.system(size: 10, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .buttonStyle(.plain)
    }
}

private struct WatchedProcess {
    let pid: Int32
    let name: String
    let cpu: Double
    let isAgent: Bool
}

private enum WorkloadMonitor {
    private static let watched = ["claude", "cursor", "codex", "ollama", "docker", "xcodebuild", "cargo", "npm", "python"]
    private static let agents = ["claude", "cursor", "codex"]

    static func running() -> [WatchedProcess] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,%cpu=,comm="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let lines = String(data: data, encoding: .utf8)?.split(separator: "\n") ?? []
            return lines.compactMap { line in
                let fields = line.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
                guard fields.count == 3,
                      let pid = Int32(fields[0]),
                      let cpu = Double(fields[1]) else { return nil }
                let name = String(fields[2]).lowercased()
                guard watched.contains(where: name.contains) else { return nil }
                return WatchedProcess(pid: pid, name: name, cpu: cpu, isAgent: agents.contains(where: name.contains))
            }
        } catch {
            return []
        }
    }
}

private final class Watchdog {
    private var idleSince: [Int32: Date] = [:]
    private var alreadyReported: Set<Int32> = []

    func update(_ workloads: [WatchedProcess]) -> [String] {
        let now = Date()
        let currentPIDs = Set(workloads.map(\.pid))
        idleSince = idleSince.filter { currentPIDs.contains($0.key) }
        alreadyReported = alreadyReported.filter { currentPIDs.contains($0) }

        var alerts: [String] = []
        for workload in workloads {
            if workload.cpu > 0.5 {
                idleSince.removeValue(forKey: workload.pid)
                alreadyReported.remove(workload.pid)
                continue
            }

            let start = idleSince[workload.pid] ?? now
            idleSince[workload.pid] = start
            let limit: TimeInterval = workload.isAgent ? 20 * 60 : 5 * 60
            if now.timeIntervalSince(start) >= limit, alreadyReported.insert(workload.pid).inserted {
                alerts.append("\(workload.name) has been near idle for \(Int(limit / 60)) minutes")
            }
        }
        return alerts
    }
}

@main
enum RunGuardApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
