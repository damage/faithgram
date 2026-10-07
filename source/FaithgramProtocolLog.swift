import Foundation
import TelegramApi

public enum FaithgramProtocolLog {
    private static let queue = DispatchQueue(label: "faithgram.protocol-log", qos: .utility)
    private static let maximumBytes = 64 * 1024 * 1024
    private static var cachedKey: Data?
    public static var directory: URL {
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Faithgram/ProtocolLogs", isDirectory: true)
    }
    public static func decoded(_ value: Any?) -> Any {
        guard let value else { return NSNull() }
        if let value = value as? ConstructorParameterDescription { return decoded(value.value) }
        if let value = value as? TypeConstructorDescription {
            let fields = value.descriptionFields()
            var result: [String: Any] = ["_": fields.0]
            for (key, field) in fields.1 { result[key] = decoded(field.value) }
            return result
        }
        if let value = value as? FunctionDescription {
            var result: [String: Any] = ["_": value.name]
            for (key, field) in value.parameters { result[key] = decoded(field.value) }
            return result
        }
        if let value = value as? Buffer { return ["bytes_base64": value.makeData().base64EncodedString()] }
        if let value = value as? Data { return ["bytes_base64": value.base64EncodedString()] }
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional { return decoded(mirror.children.first?.value) }
        if mirror.displayStyle == .collection { return mirror.children.map { decoded($0.value) } }
        return String(describing: value)
    }
    @discardableResult
    public static func begin(_ description: FunctionDescription, original: Buffer, effectivePayload: Data? = nil) -> UUID? {
        guard PatchClientPolicy.isEnabled(.protocolLogger) else { return nil }
        let id = UUID()
        append(id: id, direction: "request", value: decoded(description), payload: effectivePayload ?? original.makeData())
        return id
    }
    public static func finish(_ id: UUID?, result: Any) {
        guard let id else { return }
        append(id: id, direction: "response", value: decoded(result), payload: nil)
    }
    public static func fail(_ id: UUID?, code: Int, description: String) {
        guard let id else { return }
        append(id: id, direction: "error", value: ["code": code, "description": description], payload: nil)
    }
    private static func key() throws -> Data {
        if let key = cachedKey { return key }
        let key = try FaithgramVault.accountKey("protocol-log")
        cachedKey = key
        return key
    }
    private static func append(id: UUID, direction: String, value: Any, payload: Data?) {
        let timestamp = Date().timeIntervalSince1970
        queue.async {
            do {
                var event: [String: Any] = ["id": id.uuidString, "timestamp": timestamp, "direction": direction, "tl": value]
                if let payload { event["wire_base64"] = payload.base64EncodedString() }
                let data = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
                let file = directory.appendingPathComponent(String(format: "%.6f", timestamp) + "-" + UUID().uuidString + ".fgl")
                let encrypted = try FaithgramVault.seal(data, key: key(), context: "faithgram.protocol." + file.lastPathComponent)
                try FaithgramVault.write(encrypted, to: file)
                let files = try logFiles()
                var total: Int = 0
                for existingFile in files { total += try existingFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 }
                for old in files where total > maximumBytes {
                    if old == file { break }
                    total -= try old.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    try FileManager.default.removeItem(at: old)
                }
            } catch { FaithgramPreferences.setText("protocolLogError", "The protocol log could not be written.") }
        }
    }
    private static func logFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.pathExtension == "fgl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    public static func read(completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            let result = Result<String, Error> {
                let encryptionKey = try Self.key()
                return try logFiles().map { file in
                    let data = try FaithgramVault.open(Data(contentsOf: file), key: encryptionKey, context: "faithgram.protocol." + file.lastPathComponent)
                    let object = try JSONSerialization.jsonObject(with: data)
                    let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
                    return String(decoding: pretty, as: UTF8.self)
                }.joined(separator: "\n\n")
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
