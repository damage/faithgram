import Foundation

public struct FaithgramHistoryRevision: Codable, Equatable {
    public let text: String
    public let messageDate: Int32
    public let capturedAt: Date
    public let authorId: Int64?
    public let media: Data
    public let attributes: Data
    public init(text: String, messageDate: Int32, authorId: Int64?, media: Data, attributes: Data) {
        self.text = text
        self.messageDate = messageDate
        self.authorId = authorId
        self.media = media
        self.attributes = attributes
        self.capturedAt = Date()
    }
    public func sameContent(as other: FaithgramHistoryRevision) -> Bool {
        return text == other.text && media == other.media && attributes == other.attributes
    }
}

public struct FaithgramHistoryRecord: Codable {
    public let peerId: Int64
    public let namespace: Int32
    public let messageId: Int32
    public var deletedAt: Date?
    public var revisions: [FaithgramHistoryRevision]
    public var key: String { return "\(peerId)_\(namespace)_\(messageId)" }
}

/// This directory is independent of the message database and media cache.
/// Atomic authenticated files survive cache cleanup and application relaunch.
public final class FaithgramHistoryStore {
    private static let lock = NSRecursiveLock()
    private let directory: URL
    private let encryptionKey: Data
    public init(directory: URL, encryptionKey: Data) throws {
        guard encryptionKey.count == 32 else { throw FaithgramVaultError.invalidKey }
        self.directory = directory
        self.encryptionKey = encryptionKey
    }
    public func record(peerId: Int64, namespace: Int32, messageId: Int32) throws -> FaithgramHistoryRecord? {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let name = "\(peerId)_\(namespace)_\(messageId)"
        let path = directory.appendingPathComponent(name + ".fgh")
        if !FileManager.default.fileExists(atPath: path.path) { return nil }
        let data = try FaithgramVault.open(Data(contentsOf: path), key: encryptionKey, context: "faithgram.history.v1|" + name)
        let record = try JSONDecoder().decode(FaithgramHistoryRecord.self, from: data)
        guard record.key == name else { throw FaithgramVaultError.invalidFile }
        return record
    }
    public func capture(peerId: Int64, namespace: Int32, messageId: Int32, revision: FaithgramHistoryRevision, deleted: Bool) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        var record = try self.record(peerId: peerId, namespace: namespace, messageId: messageId) ?? FaithgramHistoryRecord(peerId: peerId, namespace: namespace, messageId: messageId, deletedAt: nil, revisions: [])
        if record.revisions.last.map({ !$0.sameContent(as: revision) }) ?? true { record.revisions.append(revision) }
        if deleted { record.deletedAt = record.deletedAt ?? Date() }
        let data = try FaithgramVault.seal(JSONEncoder().encode(record), key: encryptionKey, context: "faithgram.history.v1|" + record.key)
        try FaithgramVault.write(data, to: directory.appendingPathComponent(record.key + ".fgh"))
    }
    public func records() throws -> [FaithgramHistoryRecord] {
        Self.lock.lock(); defer { Self.lock.unlock() }
        if !FileManager.default.fileExists(atPath: directory.path) { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "fgh" }.map { url in
            let name = url.deletingPathExtension().lastPathComponent
            let data = try FaithgramVault.open(Data(contentsOf: url), key: encryptionKey, context: "faithgram.history.v1|" + name)
            let record = try JSONDecoder().decode(FaithgramHistoryRecord.self, from: data)
            guard record.key == name else { throw FaithgramVaultError.invalidFile }
            return record
        }.sorted { ($0.deletedAt ?? $0.revisions.last?.capturedAt ?? .distantPast) > ($1.deletedAt ?? $1.revisions.last?.capturedAt ?? .distantPast) }
    }
}
