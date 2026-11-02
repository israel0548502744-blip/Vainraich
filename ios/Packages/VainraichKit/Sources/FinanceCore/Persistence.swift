import Foundation

/// Reads and writes `FinanceData` as a single JSON document on disk.
///
/// Writes are atomic. On iOS the app sets `FileProtectionType.complete` on the file so it is
/// encrypted while the phone is locked.
public struct FinanceFileStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        e.dateEncodingStrategy = .deferredToDate // exact round-trip (timestamps only; money days are LocalDate strings)
        return e
    }

    public static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .deferredToDate
        return d
    }

    public func exists() -> Bool { FileManager.default.fileExists(atPath: url.path) }

    public func load() throws -> FinanceData {
        let data = try Data(contentsOf: url)
        return try FinanceFileStore.decode(data)
    }

    public func save(_ value: FinanceData) throws {
        let data = try FinanceFileStore.encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    public func delete() throws {
        if exists() { try FileManager.default.removeItem(at: url) }
    }

    public static func encode(_ value: FinanceData) throws -> Data { try makeEncoder().encode(value) }

    public static func decode(_ data: Data) throws -> FinanceData {
        let value = try makeDecoder().decode(FinanceData.self, from: data)
        guard value.schemaVersion <= FinanceData.currentSchemaVersion else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return value
    }
}
