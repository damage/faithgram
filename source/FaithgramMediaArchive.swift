import Foundation
import CryptoKit

@available(iOS 13.4, *)
public final class FaithgramMediaArchive {
    private static let lock = NSLock()
    private let directory: URL
    private let key: Data
    private let chunkSize = 512 * 1024
    public static let maximumFileSize = 256 * 1024 * 1024
    public init(directory: URL, key: Data) throws {
        guard key.count == 32 else { throw FaithgramVaultError.invalidKey }
        self.directory = directory
        self.key = key
    }
    private func name(_ resource: String) -> String { SHA256.hash(data: Data(resource.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func context(_ name: String, _ index: Int, final: Bool = false) -> String { "faithgram.media.v1|\(name)|\(index)|\(final ? "end" : "chunk")" }
    public func save(resource: String, source: URL) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let name = self.name(resource)
        let destination = directory.appendingPathComponent(name + ".fgm")
        if FileManager.default.fileExists(atPath: destination.path) { return }
        guard let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= Self.maximumFileSize else { return }
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FaithgramVault.write(Data("FGM1".utf8), to: temporary)
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? input.close(); try? output.close() }
        let _ = try output.seekToEnd()
        var index = 0
        var total = 0
        while let data = try input.read(upToCount: chunkSize), !data.isEmpty {
            total += data.count
            guard total <= Self.maximumFileSize else { throw FaithgramVaultError.invalidFile }
            let sealed = try FaithgramVault.seal(data, key: key, context: context(name, index))
            var count = UInt32(sealed.count).bigEndian
            try output.write(contentsOf: withUnsafeBytes(of: &count) { Data($0) })
            try output.write(contentsOf: sealed)
            index += 1
        }
        try output.write(contentsOf: Data(repeating: 0, count: 4))
        try output.write(contentsOf: FaithgramVault.seal(Data(), key: key, context: context(name, index, final: true)))
        try output.synchronize()
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
    public func restore(resource: String, destination: URL) throws -> Bool {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let name = self.name(resource)
        let source = directory.appendingPathComponent(name + ".fgm")
        if !FileManager.default.fileExists(atPath: source.path) { return false }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent("faithgram-media-" + UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FaithgramVault.write(Data(), to: temporary)
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? input.close(); try? output.close() }
        guard try input.read(upToCount: 4) == Data("FGM1".utf8) else { throw FaithgramVaultError.invalidFile }
        var index = 0
        var total = 0
        while true {
            guard let size = try input.read(upToCount: 4), size.count == 4 else { throw FaithgramVaultError.invalidFile }
            let count = size.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            if count == 0 {
                guard let footer = try input.read(upToCount: 28), footer.count == 28 else { throw FaithgramVaultError.invalidFile }
                guard try FaithgramVault.open(footer, key: key, context: context(name, index, final: true)).isEmpty,
                      (try input.read(upToCount: 1))?.isEmpty != false else { throw FaithgramVaultError.invalidFile }
                break
            }
            guard count > 28, count <= UInt32(chunkSize + 28), let sealed = try input.read(upToCount: Int(count)), sealed.count == Int(count) else { throw FaithgramVaultError.invalidFile }
            let data = try FaithgramVault.open(sealed, key: key, context: context(name, index))
            total += data.count
            guard total <= Self.maximumFileSize else { throw FaithgramVaultError.invalidFile }
            try output.write(contentsOf: data)
            index += 1
        }
        try output.synchronize()
        if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.moveItem(at: temporary, to: destination) }
        return true
    }
}
