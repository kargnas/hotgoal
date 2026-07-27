import Dispatch
import Foundation
import ThermalIconCore

private final class FanService: @unchecked Sendable {
    private let reader: SMCReader
    private let lock = NSRecursiveLock()
    private let timerQueue = DispatchQueue(label: "as.kargn.ThermalIcon.FanHelper.temperature-control")
    private var controlTimer: DispatchSourceTimer?
    private var activeControl: FanControl?
    private var stabilizer = FanTargetStabilizer()

    init(reader: SMCReader) {
        self.reader = reader
    }

    func status() -> Result<Data, Error> {
        locked {
            Result {
                try FanControlCodec.encode(FanControlStatus(control: activeControl, fans: reader.fanSnapshots()))
            }
        }
    }

    func setControl(_ data: Data) -> Result<Void, Error> {
        locked {
            Result {
                try applyControlLocked(FanControlCodec.decodeControl(data))
            }
        }
    }

    func restoreAutomatic() -> Result<Void, Error> {
        locked { Result { try restoreAutomaticLocked() } }
    }

    private func applyControlLocked(_ control: FanControl) throws {
        activeControl = nil
        cancelControlTimerLocked()
        stabilizer = FanTargetStabilizer()

        do {
            try reconcileLocked(control)
            activeControl = control
            if control.requiresContinuousControl { startControlTimerLocked() }
        } catch {
            activeControl = nil
            try? reader.restoreAutomatic()
            throw error
        }
    }

    private func reconcile() {
        locked {
            guard let control = activeControl, control.requiresContinuousControl else { return }
            do {
                try reconcileLocked(control)
            } catch {
                NSLog("ThermalIconFanHelper fan control failed: \(error)")
                activeControl = nil
                cancelControlTimerLocked()
                do {
                    try reader.restoreAutomatic()
                } catch {
                    NSLog("ThermalIconFanHelper automatic reset failed: \(error)")
                }
            }
        }
    }

    private func reconcileLocked(_ control: FanControl) throws {
        switch control {
        case .noise(.systemDefault, _):
            try reader.restoreAutomatic()
            return
        case .noise(.ultra, _):
            try reader.setFanPercentage(100)
            return
        case .noise, .targetTemperature:
            break
        }

        guard let temperature = reader.cpuAverageTemperature(), temperature.isFinite else {
            throw SMCReader.ReaderError.temperatureUnavailable
        }
        let fans = try reader.fanSnapshots()
        guard !fans.isEmpty else { throw SMCReader.ReaderError.invalidFan }
        let requestedTargets: [Int]
        switch control {
        case let .noise(mode, hotThreshold):
            let effectiveTemperature = stabilizer.effectiveTemperature(for: temperature)
            requestedTargets = fans.compactMap {
                mode.targetRPM(
                    celsius: effectiveTemperature,
                    minimum: $0.minimumRPM,
                    maximum: $0.maximumRPM,
                    hotThreshold: hotThreshold
                )
            }
        case let .targetTemperature(target):
            requestedTargets = TargetTemperatureController.targets(celsius: temperature, target: target, fans: fans)
        }
        // At the 90 °C safety point, maximum fan speed must never wait for slew limiting.
        let targets = stabilizer.limitTargets(
            requestedTargets,
            at: ProcessInfo.processInfo.systemUptime,
            forceImmediate: temperature >= 90
        )
        try reader.setFanTargets(targets)
    }

    private func startControlTimerLocked() {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            self?.reconcile()
        }
        controlTimer = timer
        timer.resume()
    }

    private func cancelControlTimerLocked() {
        controlTimer?.cancel()
        controlTimer = nil
    }

    private func restoreAutomaticLocked() throws {
        activeControl = nil
        cancelControlTimerLocked()
        stabilizer = FanTargetStabilizer()
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

    func getStatus(reply: @escaping (Data?, String?) -> Void) {
        switch service.status() {
        case let .success(data): reply(data, nil)
        case let .failure(error): reply(nil, error.localizedDescription)
        }
    }

    func setControl(_ control: Data, reply: @escaping (Bool, String?) -> Void) {
        send(service.setControl(control), reply: reply)
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
