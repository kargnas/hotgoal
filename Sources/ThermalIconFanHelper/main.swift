import Dispatch
import Foundation
import ThermalIconCore

private final class FanService: @unchecked Sendable {
    private let reader: SMCReader
    private let lock = NSRecursiveLock()
    private let timerQueue = DispatchQueue(label: "as.kargn.ThermalIcon.FanHelper.quiet")
    private var quietTimer: DispatchSourceTimer?
    private var activeMode = FanControlMode.standard
    private var quietThresholds = TemperatureThresholds(
        warm: TemperatureThresholds.defaultWarm,
        hot: TemperatureThresholds.defaultHot
    )

    init(reader: SMCReader) {
        self.reader = reader
    }

    func status() -> Result<Data, Error> {
        locked {
            Result { try FanPayloadCodec.encode(try reader.fanSnapshots()) }
        }
    }

    func setMode(mode rawMode: String, warmThreshold: Double, hotThreshold: Double) -> Result<Void, Error> {
        locked {
            Result {
                guard let mode = FanControlMode(rawValue: rawMode),
                      TemperatureThresholds.warmChoices.contains(warmThreshold),
                      TemperatureThresholds.hotChoices.contains(hotThreshold) else {
                    throw SMCReader.ReaderError.invalidMode
                }
                let thresholds = TemperatureThresholds(warm: warmThreshold, hot: hotThreshold)
                try applyModeLocked(mode, thresholds: thresholds)
            }
        }
    }

    func restoreAutomatic() -> Result<Void, Error> {
        locked { Result { try restoreAutomaticLocked() } }
    }

    private func applyModeLocked(_ mode: FanControlMode, thresholds: TemperatureThresholds) throws {
        cancelQuietTimerLocked()

        switch mode {
        case .standard:
            activeMode = .standard
            try reader.restoreAutomatic()
        case .ultra:
            do {
                try reader.setFanPercentage(100)
                activeMode = .ultra
            } catch {
                activeMode = .standard
                try? reader.restoreAutomatic()
                throw error
            }
        case .quiet:
            activeMode = .quiet
            quietThresholds = thresholds
            do {
                try refreshQuietLocked()
                startQuietTimerLocked()
            } catch {
                activeMode = .standard
                try? reader.restoreAutomatic()
                throw error
            }
        }
    }

    private func refreshQuiet() {
        locked {
            guard activeMode == .quiet else { return }
            do {
                try refreshQuietLocked()
            } catch {
                NSLog("ThermalIconFanHelper Quiet mode failed: \(error)")
                activeMode = .standard
                cancelQuietTimerLocked()
                do {
                    try reader.restoreAutomatic()
                } catch {
                    NSLog("ThermalIconFanHelper Quiet reset failed: \(error)")
                }
            }
        }
    }

    private func refreshQuietLocked() throws {
        guard let temperature = reader.cpuAverageTemperature(), temperature.isFinite else {
            throw SMCReader.ReaderError.temperatureUnavailable
        }
        let percentage = QuietFanCurve.percentage(celsius: temperature, thresholds: quietThresholds)
        try reader.setFanPercentage(percentage)
    }

    private func startQuietTimerLocked() {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            self?.refreshQuiet()
        }
        quietTimer = timer
        timer.resume()
    }

    private func cancelQuietTimerLocked() {
        quietTimer?.cancel()
        quietTimer = nil
    }

    private func restoreAutomaticLocked() throws {
        cancelQuietTimerLocked()
        activeMode = .standard
        try reader.restoreAutomatic()
    }

    private func locked<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

private final class ExportedFanService: NSObject, FanHelperProtocol {
    private let service: FanService

    init(service: FanService) {
        self.service = service
    }

    func getFanStatus(reply: @escaping (Data?, String?) -> Void) {
        switch service.status() {
        case let .success(data): reply(data, nil)
        case let .failure(error): reply(nil, error.localizedDescription)
        }
    }

    func setMode(
        mode: String,
        warmThreshold: Double,
        hotThreshold: Double,
        reply: @escaping (Bool, String?) -> Void
    ) {
        send(
            service.setMode(
                mode: mode,
                warmThreshold: warmThreshold,
                hotThreshold: hotThreshold
            ),
            reply: reply
        )
    }

    func restoreAutomatic(reply: @escaping (Bool, String?) -> Void) {
        send(service.restoreAutomatic(), reply: reply)
    }

    private func send(_ result: Result<Void, Error>, reply: (Bool, String?) -> Void) {
        switch result {
        case .success: reply(true, nil)
        case let .failure(error): reply(false, error.localizedDescription)
        }
    }
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let exportedService: ExportedFanService
    private let fanService: FanService
    private let lock = NSLock()
    private var connections: [ObjectIdentifier: NSXPCConnection] = [:]

    init(exportedService: ExportedFanService, fanService: FanService) {
        self.exportedService = exportedService
        self.fanService = fanService
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        let identifier = ObjectIdentifier(connection)
        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.exportedObject = exportedService
        connection.invalidationHandler = { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.removeConnection(ObjectIdentifier(connection))
        }
        lock.lock()
        connections[identifier] = connection
        lock.unlock()
        connection.activate()
        return true
    }

    private func removeConnection(_ identifier: ObjectIdentifier) {
        lock.lock()
        connections.removeValue(forKey: identifier)
        let shouldRestore = connections.isEmpty
        lock.unlock()
        if shouldRestore, case let .failure(error) = fanService.restoreAutomatic() {
            NSLog("ThermalIconFanHelper disconnect reset failed: \(error)")
        }
    }
}

guard geteuid() == 0 else {
    NSLog("ThermalIconFanHelper must run as root")
    exit(77)
}

let reader: SMCReader
do {
    reader = try SMCReader()
} catch {
    NSLog("ThermalIconFanHelper cannot open AppleSMC: \(error)")
    exit(78)
}

private let fanService = FanService(reader: reader)
if case let .failure(error) = fanService.restoreAutomatic() {
    NSLog("ThermalIconFanHelper startup reset failed: \(error)")
}
private let exportedService = ExportedFanService(service: fanService)
private let delegate = ListenerDelegate(exportedService: exportedService, fanService: fanService)
private let listener = NSXPCListener(machServiceName: fanHelperMachServiceName)

do {
    let teamID = try CurrentCodeSignature.teamIdentifier()
    let requirement = try CodeSigningRequirement(
        identifier: mainAppBundleIdentifier,
        teamID: teamID
    ).text
    listener.setConnectionCodeSigningRequirement(requirement)
} catch {
    NSLog("ThermalIconFanHelper cannot establish signed client requirement: \(error)")
    exit(78)
}

listener.delegate = delegate
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let signalQueue = DispatchQueue(label: "as.kargn.ThermalIcon.FanHelper.signal")
let signals = [SIGTERM, SIGINT].map { signalNumber in
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: signalQueue)
    source.setEventHandler {
        let result = fanService.restoreAutomatic()
        listener.invalidate()
        exit((try? result.get()) != nil ? EXIT_SUCCESS : EXIT_FAILURE)
    }
    source.resume()
    return source
}

_ = signals
listener.activate()
dispatchMain()
