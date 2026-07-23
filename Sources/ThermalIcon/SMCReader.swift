import Darwin
import Foundation
import IOKit

// AppleSMC protocol layout based on Stats by Serhiy Mytrovtsiy (MIT).
// See THIRD_PARTY_NOTICES.md.
final class SMCReader {
    enum ReaderError: LocalizedError {
        case serviceUnavailable
        case kernel(kern_return_t)
        case invalidKey(String)

        var errorDescription: String? {
            switch self {
            case .serviceUnavailable:
                "AppleSMC service is unavailable"
            case let .kernel(code):
                "AppleSMC error \(code)"
            case let .invalidKey(key):
                "Invalid SMC key: \(key)"
            }
        }
    }

    private enum Command: UInt8 {
        case readBytes = 5
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
        var bytes: Bytes = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private struct Value {
        let dataType: String
        let bytes: [UInt8]
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

    init() throws {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("AppleSMC") else {
            throw ReaderError.serviceUnavailable
        }

        var result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == kIOReturnSuccess else {
            throw ReaderError.kernel(result)
        }

        let device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        guard device != 0 else {
            throw ReaderError.serviceUnavailable
        }

        result = IOServiceOpen(device, mach_task_self_, 0, &connection)
        IOObjectRelease(device)
        guard result == kIOReturnSuccess else {
            throw ReaderError.kernel(result)
        }

        cpuKeys = Self.temperatureKeys(for: Self.cpuBrand())
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    func cpuAverageTemperature() -> Double? {
        let values = cpuKeys.compactMap { key -> Double? in
            guard let value = try? temperature(for: key), (5...115).contains(value) else {
                return nil
            }
            return value
        }

        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    private func temperature(for key: String) throws -> Double? {
        let value = try read(key)
        guard value.bytes.count >= 2 else {
            return nil
        }

        switch value.dataType {
        case "flt ":
            guard value.bytes.count >= 4 else { return nil }
            var floatValue: Float = 0
            withUnsafeMutableBytes(of: &floatValue) { destination in
                destination.copyBytes(from: value.bytes.prefix(4))
            }
            return Double(floatValue)
        case "sp1e": return fixedPoint(value.bytes, divisor: 16_384)
        case "sp3c": return fixedPoint(value.bytes, divisor: 4_096)
        case "sp4b": return fixedPoint(value.bytes, divisor: 2_048)
        case "sp5a": return fixedPoint(value.bytes, divisor: 1_024)
        case "sp69": return fixedPoint(value.bytes, divisor: 512)
        case "sp78": return fixedPoint(value.bytes, divisor: 256)
        case "sp87": return fixedPoint(value.bytes, divisor: 128)
        case "sp96": return fixedPoint(value.bytes, divisor: 64)
        case "spa5": return fixedPoint(value.bytes, divisor: 32)
        case "spb4": return fixedPoint(value.bytes, divisor: 16)
        case "spf0": return fixedPoint(value.bytes, divisor: 1)
        default: return nil
        }
    }

    private func read(_ key: String) throws -> Value {
        guard key.utf8.count == 4 else {
            throw ReaderError.invalidKey(key)
        }

        var input = KeyData()
        var output = KeyData()
        input.key = fourCharCode(key)
        input.data8 = Command.readKeyInfo.rawValue

        try call(input: &input, output: &output)
        let dataSize = Int(output.keyInfo.dataSize)
        let dataType = fourCharString(output.keyInfo.dataType)

        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = Command.readBytes.rawValue
        output = KeyData()
        try call(input: &input, output: &output)

        let bytes = withUnsafeBytes(of: output.bytes) { rawBuffer in
            Array(rawBuffer.prefix(min(dataSize, 32)))
        }
        return Value(dataType: dataType, bytes: bytes)
    }

    private func call(input: inout KeyData, output: inout KeyData) throws {
        let inputSize = MemoryLayout<KeyData>.stride
        var outputSize = MemoryLayout<KeyData>.stride
        let result = IOConnectCallStructMethod(
            connection,
            2,
            &input,
            inputSize,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess, output.result == 0 else {
            throw ReaderError.kernel(result == kIOReturnSuccess ? kIOReturnError : result)
        }
    }

    private func fixedPoint(_ bytes: [UInt8], divisor: Double) -> Double {
        let bits = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        return Double(Int16(bitPattern: bits)) / divisor
    }

    private func fourCharCode(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func fourCharString(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
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
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return ""
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return ""
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
