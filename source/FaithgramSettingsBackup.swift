import Foundation

public struct FaithgramSettingsBackup: Codable {
    public enum Value: Codable { case flag(Bool), text(String), bytes(Data), strings([String]) }
    public let version: Int
    public let createdAt: Date
    public let values: [String: Value]
    private static var textKeys: Set<String> {
        let fields = FaithgramVisualPreferences.profileFields + FaithgramVisualPreferences.balanceFields + FaithgramVisualPreferences.regularGiftFields + FaithgramVisualPreferences.uniqueGiftFields + FaithgramVisualPreferences.hiddenGiftFields
        return Set(["deletedMark", "editedMark", "regexRules", "factCheckText", "translationTarget", "gesture.up", "gesture.down"].map { "faithgram." + $0 } + fields.map { "faithgram.visual." + $0.key })
    }
    private static let binaryKeys: Set<String> = ["faithgram.mediaRules", "faithgram.privacy.custom", "faithgram.privacy.previous"]
    private static var flagKeys: Set<String> { Set(PatchClientOption.allCases.map { "patchclient.option." + $0.rawValue }) }
    public static func capture(defaults: UserDefaults = .standard) -> Self {
        var values: [String: Value] = [:]
        for key in flagKeys { values[key] = .flag(defaults.bool(forKey: key)) }
        for key in textKeys { if let value = defaults.string(forKey: key) { values[key] = .text(value) } }
        for key in binaryKeys { if let value = defaults.data(forKey: key) { values[key] = .bytes(value) } }
        if let value = defaults.stringArray(forKey: "faithgram.privacy.ghostChats") { values["faithgram.privacy.ghostChats"] = .strings(value) }
        return Self(version: 1, createdAt: Date(), values: values)
    }
    public func validate() throws {
        guard version == 1, values.count <= 256 else { throw FaithgramVaultError.invalidFile }
        for (key, value) in values {
            switch value {
            case .flag: guard Self.flagKeys.contains(key) else { throw FaithgramVaultError.invalidFile }
            case let .text(text):
                guard Self.textKeys.contains(key), text.utf8.count <= 32768 else { throw FaithgramVaultError.invalidFile }
                if key == "faithgram.regexRules" { let _ = try FaithgramMessageFilter.compile(text) }
                if key.hasPrefix("faithgram.gesture.") { guard ["none", "profiles", "ghost", "lock", "cleanLinks"].contains(text) else { throw FaithgramVaultError.invalidFile } }
            case let .bytes(data):
                guard Self.binaryKeys.contains(key), data.count <= 512 * 1024 else { throw FaithgramVaultError.invalidFile }
                if key == "faithgram.mediaRules" { let _ = try JSONDecoder().decode([String: Bool].self, from: data) }
                else {
                    let profile = try JSONDecoder().decode([String: Bool].self, from: data)
                    guard Set(profile.keys) == Set(FaithgramPrivacySettings.options.map { $0.rawValue }) else { throw FaithgramVaultError.invalidFile }
                }
            case let .strings(strings):
                guard key == "faithgram.privacy.ghostChats", strings.count <= 10000 else { throw FaithgramVaultError.invalidFile }
                for text in strings {
                    let parts = text.split(separator: ":")
                    guard parts.count == 2, let ns = Int32(parts[0]), (0...3).contains(ns), let id = Int64(parts[1]), id > 0 || (ns == 3 && id != 0 && Int32(exactly: id) != nil) else { throw FaithgramVaultError.invalidFile }
                }
            }
        }
    }
    public func encrypted(password: String) throws -> Data {
        try validate()
        let data = try JSONEncoder().encode(self)
        guard data.count <= 1024 * 1024 else { throw FaithgramVaultError.invalidFile }
        return try FaithgramVault.encryptBackup(data, password: password, format: "faithgram.settings")
    }
    public static func decrypt(_ data: Data, password: String) throws -> Self {
        let plaintext = try FaithgramVault.decryptBackup(data, password: password, format: "faithgram.settings")
        guard plaintext.count <= 1024 * 1024 else { throw FaithgramVaultError.invalidFile }
        let backup = try JSONDecoder().decode(Self.self, from: plaintext)
        try backup.validate()
        return backup
    }
    public func apply(defaults: UserDefaults = .standard) throws {
        try validate()
        for key in Self.flagKeys.union(Self.textKeys).union(Self.binaryKeys).union(["faithgram.privacy.ghostChats"]) { defaults.removeObject(forKey: key) }
        for (key, value) in values {
            switch value {
            case let .flag(value): defaults.set(value, forKey: key)
            case let .text(value): defaults.set(value, forKey: key)
            case let .bytes(value): defaults.set(value, forKey: key)
            case let .strings(value): defaults.set(value, forKey: key)
            }
        }
        NotificationCenter.default.post(name: FaithgramPreferences.changed, object: nil)
    }
}
