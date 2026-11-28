import Dispatch
import Foundation

/// The AppleSMC operations `FanService` drives. `SMCReader` is the real hardware; tests
/// substitute a fake so the control loop runs without root or an AppleSMC connection.
public protocol FanHardware: AnyObject {
    func cpuAverageTemperature() -> Double?
    func fanSnapshots() throws -> [FanSnapshot]
    func setFanPercentage(_ percentage: Int) throws
    func setFanTargets(_ targets: [Int]) throws
    func restoreAutomatic() throws
}

extension SMCReader: FanHardware {}

/// The privileged helper's fan controller and the single authority over the active control.
public final class FanService: @unchecked Sendable {
    /// Pause after a failed tick, so a failure that outlasts a sleep transition rewrites the
    /// SMC and the log every few seconds rather than every second.
    private static let retryDelay: TimeInterval = 5

    private let hardware: FanHardware
    private let lock = NSRecursiveLock()
    private let timerQueue = DispatchQueue(label: "as.kargn.hotgoal.helper.temperature-control")
    private var controlTimer: DispatchSourceTimer?
    private var activeControl: FanControl?
    private var temperatureAverage = TemperatureAverage()
    private var criticalGate = CriticalTemperatureGate()
    private var stabilizer = FanTargetStabilizer()

    public init(hardware: FanHardware) {
        self.hardware = hardware
    }

    public func status() -> Result<Data, Error> {
        locked {
            Result {
                try FanControlCodec.encode(FanControlStatus(control: activeControl, fans: hardware.fanSnapshots()))
            }
        }
    }

    public func setControl(_ data: Data) -> Result<Void, Error> {
        locked {
            Result {
                try applyControlLocked(FanControlCodec.decodeControl(data))
            }
        }
    }

    public func restoreAutomatic() -> Result<Void, Error> {
        locked { Result { try restoreAutomaticLocked() } }
    }

    private func applyControlLocked(_ control: FanControl) throws {
        activeControl = nil
        cancelControlTimerLocked()
        resetControlStateLocked()

        do {
            try reconcileLocked(control)
            activeControl = control
            if control.requiresContinuousControl { startControlTimerLocked() }
        } catch {
            activeControl = nil
            try? hardware.restoreAutomatic()
            throw error
        }
    }

    /// One control-loop tick. Internal rather than private so tests can run a tick without
    /// waiting on the one-second timer.
    func reconcile() {
        locked {
            guard let control = activeControl, control.requiresContinuousControl else { return }
            do {
                try reconcileLocked(control)
            } catch {
                // AppleSMC readings can fail briefly around sleep and wake. The control outlives
                // such a gap: macOS drives the fans meanwhile, and the next readable tick resumes
                // the user's selection without a new command from the app.
                NSLog("hotgoal-helper fan control failed, retrying in \(Int(Self.retryDelay)) s: \(error)")
                resetControlStateLocked()
                controlTimer?.schedule(deadline: .now() + Self.retryDelay, repeating: 1, leeway: .milliseconds(250))
                do {
                    try hardware.restoreAutomatic()
                } catch {
                    NSLog("hotgoal-helper automatic reset failed: \(error)")
                }
            }
        }
    }

    private func reconcileLocked(_ control: FanControl) throws {
        switch control {
        case .noise(.systemDefault):
            try hardware.restoreAutomatic()
        case .noise(.ultra):
            try hardware.setFanPercentage(100)
        case .noise(.quiet):
            // Quiet is an unconditional promise of silence: it never reads the temperature,
            // so neither the 90 °C override nor a sensor failure can spin the fans up.
            let fans = try hardware.fanSnapshots()
            guard !fans.isEmpty else { throw SMCReader.ReaderError.invalidFan }
            try hardware.setFanTargets(fans.map(\.minimumRPM))
        case let .targetTemperature(target):
            guard let temperature = hardware.cpuAverageTemperature(), temperature.isFinite else {
                throw SMCReader.ReaderError.temperatureUnavailable
            }
            let now = ProcessInfo.processInfo.systemUptime
            let fans = try hardware.fanSnapshots()
            guard !fans.isEmpty else { throw SMCReader.ReaderError.invalidFan }
            if criticalGate.register(temperature, at: now) {
                // At the 90 °C safety point every fan heads for maximum on the critical ramp,
                // which is six times faster than the everyday rise.
                try hardware.setFanTargets(stabilizer.rampToMaximum(for: fans, at: now))
                return
            }
            guard let controlTemperature = temperatureAverage.append(temperature, at: now) else { return }
            let requestedTargets = TargetTemperatureController.targets(
                celsius: controlTemperature,
                target: target,
                fans: fans
            )
            try hardware.setFanTargets(stabilizer.limitTargets(requestedTargets, for: fans, at: now))
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
        resetControlStateLocked()
        try hardware.restoreAutomatic()
    }

    /// Samples and slew history from before an apply, a restore, or a failed tick describe a
    /// fan state that no longer holds; carrying them over would mix stale readings into the
    /// next decision.
    private func resetControlStateLocked() {
        temperatureAverage = TemperatureAverage()
        criticalGate = CriticalTemperatureGate()
        stabilizer = FanTargetStabilizer()
    }

    private func locked<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
