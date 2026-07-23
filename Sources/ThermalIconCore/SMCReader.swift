import Darwin
import Foundation
import IOKit

// AppleSMC protocol layout and fan-write flow are based on Stats and
// achen4020/MacFanControl (MIT). See THIRD_PARTY_NOTICES.md.
public final class SMCReader {
    public enum ReaderError: LocalizedError {
        case serviceUnavailable
        case kernel(kern_return_t)
        case smc(UInt8)
        case invalidKey(String)
        case invalidFan
        case invalidBoost
        case rootRequired
        case unsupportedValueType(String)
        case restoreFailed

        public var errorDescription: String? {
            switch self {
            case .serviceUnavailable: "AppleSMC service is unavailable"
            case let .kernel(code): "AppleSMC kernel error \(code)"
            case let .smc(code): "AppleSMC firmware error 0x\(String(code, radix: 16))"
            case let .invalidKey(key): "Invalid SMC key: \(key)"
            case .invalidFan: "Invalid or unavailable fan"
            case .invalidBoost: "Unsupported fan boost"
            case .rootRequired: "Fan control requires root privileges"
            case let .unsupportedValueType(type): "Unsupported SMC value type: \(type)"
            case .restoreFailed: "Failed to restore automatic fan control"
            }
        }
    }

    private enum Command: UInt8 {
        case readBytes = 5
        case writeBytes = 6
        case readKeyInfo = 9
    }

    private struct Version {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }

    private struct LimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct KeyInfo {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct KeyData {
        typealias Bytes = (
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
        )

        var key: UInt32 = 0
        var version = Version()
        var limitData = LimitData()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = Self.emptyBytes

        static let emptyBytes: Bytes = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private struct Value {
        let key: String
        let dataSize: Int
        let dataType: String
        var bytes: [UInt8]
    }

    private static let intelKeys = [
        "TC0D", "TC0E", "TC0F", "TC0H", "TC0P", "TCAD",
        "TC0C", "TC1C", "TC2C", "TC3C", "TC4C", "TC5C", "TC6C", "TC7C",
    ]
    private static let m1Keys = [
        "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b",
    ]
    private static let m2Keys = [
        "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j",
    ]
    private static let m3Keys = [
        "Te05", "Te0L", "Te0P", "Te0S",
        "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
    ]
    private static let m4Keys = [
        "Te05", "Te0S", "Te09", "Te0H",
        "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e",
    ]
    private static let m5Keys = [
        "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K",
        "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y",
    ]

    private var connection: io_connect_t = 0
    private let cpuKeys: [String]
    private let isAppleSilicon: Bool
    private var usesLowercaseFanModeKey: Bool?

    public init() throws {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("AppleSMC") else {
            throw ReaderError.serviceUnavailable
        }

        var result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == kIOReturnSuccess else { throw ReaderError.kernel(result) }

        let device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        guard device != 0 else { throw ReaderError.serviceUnavailable }

        result = IOServiceOpen(device, mach_task_self_, 0, &connection)
        IOObjectRelease(device)
        guard result == kIOReturnSuccess else { throw ReaderError.kernel(result) }

        let brand = Self.cpuBrand()
        cpuKeys = Self.temperatureKeys(for: brand)
        isAppleSilicon = brand.hasPrefix("Apple ")
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    public func cpuAverageTemperature() -> Double? {
        let values = cpuKeys.compactMap { key -> Double? in
            guard let value = try? numericValue(for: key), (5...115).contains(value) else { return nil }
            return value
        }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    public func fanSnapshots() throws -> [FanSnapshot] {
        let count = Int(try numericValue(for: "FNum").rounded())
        guard (0...8).contains(count) else { throw ReaderError.invalidFan }

        return try (0..<count).map { index in
            let snapshot = FanSnapshot(
                index: index,
                currentRPM: Int(try numericValue(for: "F\(index)Ac").rounded()),
                minimumRPM: Int(try numericValue(for: "F\(index)Mn").rounded()),
                maximumRPM: Int(try numericValue(for: "F\(index)Mx").rounded()),
                targetRPM: try? Int(numericValue(for: "F\(index)Tg").rounded()),
                mode: Int(try numericValue(for: fanModeKey(index)).rounded())
            )
            guard snapshot.isValid else { throw ReaderError.invalidFan }
            return snapshot
        }
    }

    public func setBoost(_ boost: FanBoost) throws {
        guard geteuid() == 0 else { throw ReaderError.rootRequired }
        let fans = try fanSnapshots()
        guard !fans.isEmpty else { throw ReaderError.invalidFan }

        do {
            for fan in fans {
                try setFanSpeed(
                    index: fan.index,
                    rpm: boost.targetRPM(minimum: fan.minimumRPM, maximum: fan.maximumRPM)
                )
            }
        } catch {
            try? restoreAutomaticInternal(fanCount: fans.count)
            throw error
        }
    }

    public func restoreAutomatic() throws {
        guard geteuid() == 0 else { throw ReaderError.rootRequired }
        let count = Int(try numericValue(for: "FNum").rounded())
        guard (0...8).contains(count) else { throw ReaderError.invalidFan }
        try restoreAutomaticInternal(fanCount: count)
    }

    private func setFanSpeed(index: Int, rpm: Int) throws {
        let minimum = Int(try numericValue(for: "F\(index)Mn").rounded())
        let maximum = Int(try numericValue(for: "F\(index)Mx").rounded())
        guard minimum...maximum ~= rpm else { throw ReaderError.invalidFan }

        if isAppleSilicon {
            try unlockAppleSiliconFan(index: index)
        } else {
            try setIntelManualMode(index: index, manual: true)
        }

        var target = try read("F\(index)Tg")
        target.bytes = try encodedFanSpeed(rpm, dataType: target.dataType, size: target.dataSize)
        try writeWithRetry(target)
    }

    private func unlockAppleSiliconFan(index: Int) throws {
        var mode = try read(fanModeKey(index))
        if mode.bytes.first == 1 { return }
        mode.bytes[0] = 1

        if (try? write(mode)) != nil { return }

        var testMode = try read("Ftst")
        if testMode.bytes.first != 1 {
            testMode.bytes[0] = 1
            try writeWithRetry(testMode, attempts: 20, delayMicroseconds: 50_000)
            usleep(3_000_000)
        }
        try writeWithRetry(mode, attempts: 100, delayMicroseconds: 100_000)
    }

    private func setIntelManualMode(index: Int, manual: Bool) throws {
        if var mode = try? read(fanModeKey(index)) {
            mode.bytes[0] = manual ? 1 : 0
            try writeWithRetry(mode)
        }

        if var force = try? read("FS! "), force.bytes.count >= 2 {
            let mask = UInt8(1 << index)
            force.bytes[1] = manual ? force.bytes[1] | mask : force.bytes[1] & ~mask
            try writeWithRetry(force)
        }
    }

    private func restoreAutomaticInternal(fanCount: Int) throws {
        var failed = false
        for index in 0..<fanCount {
            do {
                if var mode = try? read(fanModeKey(index)) {
                    mode.bytes[0] = 0
                    try writeWithRetry(mode)
                }
                if var target = try? read("F\(index)Tg") {
                    target.bytes = try encodedFanSpeed(0, dataType: target.dataType, size: target.dataSize)
                    try writeWithRetry(target)
                }
                if !isAppleSilicon {
                    try setIntelManualMode(index: index, manual: false)
                }
            } catch {
                failed = true
            }
        }

        if isAppleSilicon, var testMode = try? read("Ftst") {
            do {
                testMode.bytes[0] = 0
                try writeWithRetry(testMode)
            } catch {
                failed = true
            }
        }
        if failed { throw ReaderError.restoreFailed }
    }

    private func fanModeKey(_ index: Int) throws -> String {
        if usesLowercaseFanModeKey == nil {
            usesLowercaseFanModeKey = (try? read("F0md")) != nil
        }
        return usesLowercaseFanModeKey == true ? "F\(index)md" : "F\(index)Md"
    }

    private func numericValue(for key: String) throws -> Double {
        let value = try read(key)
        let bytes = value.bytes

        switch value.dataType {
        case "ui8 ": return Double(bytes[0])
        case "ui16": return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        case "flt ":
            guard bytes.count >= 4 else { throw ReaderError.unsupportedValueType(value.dataType) }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let float = Float(bitPattern: bits)
            guard float.isFinite else { throw ReaderError.unsupportedValueType(value.dataType) }
            return Double(float)
        case "fpe2": return Double((Int(bytes[0]) << 6) + (Int(bytes[1]) >> 2))
        case "sp1e": return fixedPoint(bytes, divisor: 16_384)
        case "sp3c": return fixedPoint(bytes, divisor: 4_096)
        case "sp4b": return fixedPoint(bytes, divisor: 2_048)
        case "sp5a": return fixedPoint(bytes, divisor: 1_024)
        case "sp69": return fixedPoint(bytes, divisor: 512)
        case "sp78": return fixedPoint(bytes, divisor: 256)
        case "sp87": return fixedPoint(bytes, divisor: 128)
        case "sp96": return fixedPoint(bytes, divisor: 64)
        case "spa5": return fixedPoint(bytes, divisor: 32)
        case "spb4": return fixedPoint(bytes, divisor: 16)
        case "spf0": return fixedPoint(bytes, divisor: 1)
        default: throw ReaderError.unsupportedValueType(value.dataType)
        }
    }

    private func read(_ key: String) throws -> Value {
        guard key.utf8.count == 4 else { throw ReaderError.invalidKey(key) }

        var input = KeyData()
        var output = KeyData()
        input.key = fourCharCode(key)
        input.data8 = Command.readKeyInfo.rawValue
        try call(input: &input, output: &output)

        let dataSize = Int(output.keyInfo.dataSize)
        let dataType = fourCharString(output.keyInfo.dataType)
        guard (1...32).contains(dataSize) else { throw ReaderError.unsupportedValueType(dataType) }

        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = Command.readBytes.rawValue
        output = KeyData()
        try call(input: &input, output: &output)

        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(dataSize)) }
        return Value(key: key, dataSize: dataSize, dataType: dataType, bytes: bytes)
    }

    private func write(_ value: Value) throws {
        var input = KeyData()
        var output = KeyData()
        input.key = fourCharCode(value.key)
        input.data8 = Command.writeBytes.rawValue
        input.keyInfo.dataSize = IOByteCount32(value.dataSize)
        input.bytes = byteTuple(value.bytes)
        try call(input: &input, output: &output)
    }

    private func writeWithRetry(
        _ value: Value,
        attempts: Int = 10,
        delayMicroseconds: UInt32 = 50_000
    ) throws {
        var lastError: Error = ReaderError.restoreFailed
        for attempt in 0..<attempts {
            do {
                try write(value)
                return
            } catch {
                lastError = error
                if attempt + 1 < attempts { usleep(delayMicroseconds) }
            }
        }
        throw lastError
    }

    private func call(input: inout KeyData, output: inout KeyData) throws {
        let inputSize = MemoryLayout<KeyData>.stride
        var outputSize = MemoryLayout<KeyData>.stride
        let result = IOConnectCallStructMethod(connection, 2, &input, inputSize, &output, &outputSize)
        guard result == kIOReturnSuccess else { throw ReaderError.kernel(result) }
        guard output.result == 0 else { throw ReaderError.smc(output.result) }
    }

    private func encodedFanSpeed(_ rpm: Int, dataType: String, size: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size)
        switch dataType {
        case "flt ":
            guard size >= 4 else { throw ReaderError.unsupportedValueType(dataType) }
            let bits = Float(rpm).bitPattern
            bytes[0] = UInt8(truncatingIfNeeded: bits)
            bytes[1] = UInt8(truncatingIfNeeded: bits >> 8)
            bytes[2] = UInt8(truncatingIfNeeded: bits >> 16)
            bytes[3] = UInt8(truncatingIfNeeded: bits >> 24)
        case "fpe2":
            guard size >= 2, rpm <= Int(UInt16.max >> 2) else { throw ReaderError.unsupportedValueType(dataType) }
            let raw = UInt16(rpm) << 2
            bytes[0] = UInt8(raw >> 8)
            bytes[1] = UInt8(raw & 0xff)
        default:
            throw ReaderError.unsupportedValueType(dataType)
        }
        return bytes
    }

    private func fixedPoint(_ bytes: [UInt8], divisor: Double) -> Double {
        Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / divisor
    }

    private func fourCharCode(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func fourCharString(_ value: UInt32) -> String {
        String(bytes: [
            UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff), UInt8(value & 0xff),
        ], encoding: .ascii) ?? ""
    }

    private func byteTuple(_ bytes: [UInt8]) -> KeyData.Bytes {
        let b = bytes + [UInt8](repeating: 0, count: max(0, 32 - bytes.count))
        return (
            b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
            b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15],
            b[16], b[17], b[18], b[19], b[20], b[21], b[22], b[23],
            b[24], b[25], b[26], b[27], b[28], b[29], b[30], b[31]
        )
    }

    private static func temperatureKeys(for brand: String) -> [String] {
        let chip = brand.split(separator: " ").first { $0.first == "M" }.map(String.init)
        switch chip {
        case "M1": return m1Keys
        case "M2": return m2Keys
        case "M3": return m3Keys
        case "M4": return m4Keys
        case "M5": return m5Keys
        default: return intelKeys
        }
    }

    private static func cpuBrand() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
