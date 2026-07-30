import Foundation

public final class TemperatureCSVLog {
    public static let sampleInterval: TimeInterval = 1
    public static let retention: TimeInterval = 3 * 24 * 60 * 60
    public let directoryURL: URL

    private var lastSampleAt: Date?
    private var lastCleanupAt: Date?
    private let timestampFormatter: ISO8601DateFormatter

    public init(directoryURL: URL = TemperatureCSVLog.defaultDirectoryURL) {
        self.directoryURL = directoryURL
        timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public func record(targetCelsius: Double, actualCelsius: Double, at date: Date = Date()) {
        guard targetCelsius.isFinite, actualCelsius.isFinite else { return }
        guard lastSampleAt.map({ date.timeIntervalSince($0) >= Self.sampleInterval }) != false else { return }

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let timestamp = timestampFormatter.string(from: date)
            let fileURL = directoryURL.appendingPathComponent("\(timestamp.prefix(10)).csv")
            let values = String(
                format: "%.1f,%.1f",
                locale: Locale(identifier: "en_US_POSIX"),
                targetCelsius,
                actualCelsius
            )
            let line = "\(timestamp),\(values)\n"
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try Data("timestamp,target_celsius,actual_celsius\n\(line)".utf8).write(to: fileURL, options: .atomic)
            }
            lastSampleAt = date
        } catch {
            NSLog("hottarget temperature log write failed: \(error)")
        }

        guard lastCleanupAt.map({ date.timeIntervalSince($0) >= 60 * 60 }) != false else { return }
        do {
            let cutoff = date.addingTimeInterval(-Self.retention)
            for fileURL in try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) where fileURL.pathExtension == "csv" {
                let modificationDate = try fileURL.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                if modificationDate.map({ $0 < cutoff }) == true {
                    try FileManager.default.removeItem(at: fileURL)
                }
            }
            lastCleanupAt = date
        } catch {
            NSLog("hottarget temperature log cleanup failed: \(error)")
        }
    }

    public func contents() throws -> String {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return "" }
        return try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "csv" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { fileURL in
            "# \(fileURL.lastPathComponent)\n" + (try String(contentsOf: fileURL, encoding: .utf8))
        }
        .joined(separator: "\n")
    }

    public static let defaultDirectoryURL = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/hottarget", isDirectory: true)

}
