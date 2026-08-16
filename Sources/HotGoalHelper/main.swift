import Dispatch
import Foundation
import HotGoalCore

private final class FanService: @unchecked Sendable {
    private let reader: SMCReader
    private let lock = NSRecursiveLock()
    private let timerQueue = DispatchQueue(label: "as.kargn.hotgoal.helper.temperature-control")
    private var controlTimer: DispatchSourceTimer?
    private var activeControl: FanControl?
    private var temperatureAverage = TemperatureAverage()
    private var criticalGate = CriticalTemperatureGate()
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
        temperatureAverage = TemperatureAverage()
        criticalGate = CriticalTemperatureGate()
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
                NSLog("hot-goal-helper fan control failed: \(error)")
                activeControl = nil
                cancelControlTimerLocked()
                do {
                    try reader.restoreAutomatic()
                } catch {
                    NSLog("hot-goal-helper automatic reset failed: \(error)")
                }
            }
        }
    }

    private func reconcileLocked(_ control: FanControl) throws {
        switch control {
        case .noise(.systemDefault):
            try reader.restoreAutomatic()
        case .noise(.ultra):
            try reader.setFanPercentage(100)
        case .noise(.quiet):
            // Quiet is an unconditional promise of silence: it never reads the temperature,
            // so neither the 90 °C override nor a sensor failure can spin the fans up.
            let fans = try reader.fanSnapshots()
            guard !fans.isEmpty else { throw SMCReader.ReaderError.invalidFan }
            try reader.setFanTargets(fans.map(\.minimumRPM))
        case let .targetTemperature(target):
            guard let temperature = reader.cpuAverageTemperature(), temperature.isFinite else {
                throw SMCReader.ReaderError.temperatureUnavailable
            }
            let now = ProcessInfo.processInfo.systemUptime
            let fans = try reader.fanSnapshots()
            guard !fans.isEmpty else { throw SMCReader.ReaderError.invalidFan }
            if criticalGate.register(temperature, at: now) {
                // At the 90 °C safety point, maximum fan speed must never wait for slew limiting.
                try reader.setFanTargets(stabilizer.forceMaximumTargets(for: fans, at: now))
                return
            }
            guard let controlTemperature = temperatureAverage.append(temperature, at: now) else { return }
            let requestedTargets = TargetTemperatureController.targets(
                celsius: controlTemperature,
                target: target,
                fans: fans
            )
            try reader.setFanTargets(stabilizer.limitTargets(requestedTargets, at: now))
        }
    }

    private func startControlTimerLocked() {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(250))
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
        temperatureAverage = TemperatureAverage()
        criticalGate = CriticalTemperatureGate()
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
        NSLog("hot-goal-helper disconnect reset failed: \(error)")
        }
    }
}

guard geteuid() == 0 else {
    NSLog("hot-goal-helper must run as root")
    exit(77)
}

let reader: SMCReader
do {
    reader = try SMCReader()
} catch {
    NSLog("hot-goal-helper cannot open AppleSMC: \(error)")
    exit(78)
}

private let fanService = FanService(reader: reader)
if case let .failure(error) = fanService.restoreAutomatic() {
    NSLog("hot-goal-helper startup reset failed: \(error)")
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
    NSLog("hot-goal-helper cannot establish signed client requirement: \(error)")
    exit(78)
}

listener.delegate = delegate
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let signalQueue = DispatchQueue(label: "as.kargn.hotgoal.helper.signal")
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
