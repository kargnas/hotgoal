import AppKit
import Darwin
import Foundation

@main
enum ThermalIconApp {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--print-temperature") {
            do {
                let reader = try SMCReader()
                guard let temperature = reader.cpuAverageTemperature() else {
                    fputs("CPU temperature unavailable\n", stderr)
                    exit(1)
                }
                print(String(format: "CPU temperature: %.1f °C", temperature))
                return
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
