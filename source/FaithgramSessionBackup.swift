import Foundation

public struct FaithgramSavedSession: Codable {
    public let testingEnvironment: Bool
    public let data: AccountBackupData
    public init(testingEnvironment: Bool, data: AccountBackupData) {
        self.testingEnvironment = testingEnvironment
        self.data = data
    }
}

public struct FaithgramSessionBackup: Codable {
    public let version: Int
    public let createdAt: Date
    public let sessions: [FaithgramSavedSession]
    public init(sessions: [FaithgramSavedSession]) {
        self.version = 1
        self.createdAt = Date()
        self.sessions = sessions
    }
    public func validate() throws {
        guard version == 1, !sessions.isEmpty else { throw FaithgramVaultError.invalidFile }
        for session in sessions {
            let value = session.data
            guard value.peerId > 0, (1 ... 10).contains(value.masterDatacenterId), value.masterDatacenterKey.count == 256, value.masterDatacenterKeyId != 0, value.additionalDatacenterKeys.count <= 10 else { throw FaithgramVaultError.invalidFile }
            for (id, key) in value.additionalDatacenterKeys {
                guard (1 ... 10).contains(id), id == key.id, key.key.count == 256, key.keyId != 0 else { throw FaithgramVaultError.invalidFile }
            }
        }
    }
    public func encrypted(password: String) throws -> Data {
        try validate()
        return try FaithgramVault.encryptBackup(JSONEncoder().encode(self), password: password)
    }
    public static func decrypt(_ data: Data, password: String) throws -> FaithgramSessionBackup {
        let backup = try JSONDecoder().decode(Self.self, from: FaithgramVault.decryptBackup(data, password: password))
        try backup.validate()
        return backup
    }
}
