import AppKit
import Darwin
import Foundation
import ServiceManagement
import ThermalIconCore

@main
enum ThermalIconApp {
    @MainActor
    static func main() {
        if runCommandLine() { return }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    @MainActor
    private static func runCommandLine() -> Bool {
        if CommandLine.arguments.contains("--print-temperature") {
            do {
                let reader = try SMCReader()
                guard let temperature = reader.cpuAverageTemperature() else {
                    fputs("CPU temperature unavailable\n", stderr)
                    exit(1)
                }
                print(String(format: "CPU temperature: %.1f °C", temperature))
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return true
        }

        if CommandLine.arguments.contains("--print-fans") {
            do {
                let fans = try SMCReader().fanSnapshots()
                guard !fans.isEmpty else {
                    fputs("No controllable fans found\n", stderr)
                    exit(1)
                }
                for fan in fans {
                    let target = fan.targetRPM.map(String.init) ?? "n/a"
                    print("Fan \(fan.index + 1): \(fan.currentRPM) RPM (min \(fan.minimumRPM), max \(fan.maximumRPM), target \(target), mode \(fan.mode))")
                }
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return true
        }

        if CommandLine.arguments.contains("--helper-status") {
            print(helperStatusText())
            return true
        }

        if CommandLine.arguments.contains("--register-helper") {
            let service = SMAppService.daemon(plistName: fanHelperPlistName)
            do {
                if service.status != .enabled && service.status != .requiresApproval {
                    try service.register()
                }
                print(helperStatusText())
            } catch {
                print(helperStatusText())
                fputs("Bundle: \(Bundle.main.bundlePath)\n", stderr)
                fputs("\(error.localizedDescription)\n", stderr)
                if service.status != .requiresApproval { exit(1) }
            }
            return true
        }

        return false
    }

    @MainActor
    private static func helperStatusText() -> String {
        switch SMAppService.daemon(plistName: fanHelperPlistName).status {
        case .notRegistered: "Fan helper: not registered"
        case .enabled: "Fan helper: enabled"
        case .requiresApproval: "Fan helper: approval required"
        case .notFound: "Fan helper: not found"
        @unknown default: "Fan helper: unknown"
        }
    }
}
