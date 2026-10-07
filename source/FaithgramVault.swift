import Foundation
import CryptoKit
import Security
import CommonCrypto

public enum FaithgramVaultError: Error {
    case invalidFile, invalidPassword, keyUnavailable, invalidKey
}

public enum FaithgramVault {
    private struct Envelope: Codable {
        let format: String
        let version: Int
        let salt: Data
        let rounds: UInt32
        let sealed: Data
    }
    private static let rounds: UInt32 = 600_000

    public static func accountKey(_ account: String) throws -> Data {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "faithgram.history", kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 { return data }
        guard status == errSecItemNotFound else { throw FaithgramVaultError.keyUnavailable }
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        var insert = query
        insert.removeValue(forKey: kSecReturnData as String)
        insert.removeValue(forKey: kSecMatchLimit as String)
        insert[kSecValueData as String] = key
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(insert as CFDictionary, nil)
        if added == errSecDuplicateItem { return try accountKey(account) }
        guard added == errSecSuccess else { throw FaithgramVaultError.keyUnavailable }
        return key
    }

    public static func seal(_ data: Data, key: Data, context: String) throws -> Data {
        guard key.count == 32 else { throw FaithgramVaultError.invalidKey }
        guard let sealed = try AES.GCM.seal(data, using: SymmetricKey(data: key), authenticating: Data(context.utf8)).combined else { throw FaithgramVaultError.invalidFile }
        return sealed
    }
    public static func open(_ data: Data, key: Data, context: String) throws -> Data {
        guard key.count == 32 else { throw FaithgramVaultError.invalidKey }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: SymmetricKey(data: key), authenticating: Data(context.utf8))
    }

    private static func passwordKey(_ password: String, salt: Data) throws -> Data {
        let password = Array(password.precomposedStringWithCanonicalMapping.utf8)
        guard password.count >= 12, password.count <= 1024, salt.count == 32 else { throw FaithgramVaultError.invalidPassword }
        var derived = [UInt8](repeating: 0, count: 32)
        defer { _ = derived.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        let status = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes.baseAddress!.assumingMemoryBound(to: Int8.self), password.count, saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, &derived, 32)
            }
        }
        guard status == kCCSuccess else { throw FaithgramVaultError.invalidKey }
        return Data(derived)
    }
    public static func encryptBackup(_ data: Data, password: String, format: String = "faithgram.sessions") throws -> Data {
        guard ["faithgram.sessions", "faithgram.settings"].contains(format) else { throw FaithgramVaultError.invalidFile }
        guard data.count <= 10 * 1024 * 1024 else { throw FaithgramVaultError.invalidFile }
        let salt = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let key = try passwordKey(password, salt: salt)
        let sealed = try seal(data, key: key, context: format + ".v1")
        return try JSONEncoder().encode(Envelope(format: format, version: 1, salt: salt, rounds: rounds, sealed: sealed))
    }
    public static func decryptBackup(_ data: Data, password: String, format: String = "faithgram.sessions") throws -> Data {
        guard data.count <= 16 * 1024 * 1024 else { throw FaithgramVaultError.invalidFile }
        let file = try JSONDecoder().decode(Envelope.self, from: data)
        guard ["faithgram.sessions", "faithgram.settings"].contains(format), file.format == format, file.version == 1, file.rounds == rounds, file.salt.count == 32 else { throw FaithgramVaultError.invalidFile }
        return try open(file.sealed, key: passwordKey(password, salt: file.salt), context: format + ".v1")
    }

    public static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.deletingLastPathComponent().path)
        #endif
        try data.write(to: url, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try target.setResourceValues(values)
    }
}
