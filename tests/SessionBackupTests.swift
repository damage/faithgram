import Foundation
import XCTest
@testable import PatchClientCore

final class SessionBackupTests: XCTestCase {
    private func session() -> FaithgramSavedSession {
        // Deliberately synthetic data; never use real Telegram auth keys in tests.
        let data = AccountBackupData(masterDatacenterId: 2, peerId: 12345, masterDatacenterKey: Data(repeating: 0x41, count: 256), masterDatacenterKeyId: 123, notificationEncryptionKeyId: nil, notificationEncryptionKey: nil, additionalDatacenterKeys: [4: .init(id: 4, keyId: 456, key: Data(repeating: 0x42, count: 256))])
        return FaithgramSavedSession(testingEnvironment: true, data: data)
    }
    func testEncryptedBackupUsesActualUpstreamSessionDTOAndRoundTrips() throws {
        let backup = FaithgramSessionBackup(sessions: [session()])
        let first = try backup.encrypted(password: "test password one")
        let second = try backup.encrypted(password: "test password one")
        XCTAssertNotEqual(first, second)
        let restored = try FaithgramSessionBackup.decrypt(first, password: "test password one")
        XCTAssertEqual(restored.sessions.count, 1)
        XCTAssertTrue(restored.sessions[0].testingEnvironment)
        XCTAssertEqual(restored.sessions[0].data, backup.sessions[0].data)
        XCTAssertNil(first.range(of: Data(repeating: 0x41, count: 256)))
        XCTAssertThrowsError(try FaithgramSessionBackup.decrypt(first, password: "wrong password here"))
    }
    func testBackupRejectsWeakPasswordsInvalidKeysAndModifiedEnvelope() throws {
        let backup = FaithgramSessionBackup(sessions: [session()])
        XCTAssertThrowsError(try backup.encrypted(password: "short"))
        var invalid = session().data
        invalid.masterDatacenterKey = Data(repeating: 1, count: 10)
        XCTAssertThrowsError(try FaithgramSessionBackup(sessions: [.init(testingEnvironment: false, data: invalid)]).validate())
        XCTAssertThrowsError(try FaithgramSessionBackup(sessions: []).validate())
        let encrypted = try backup.encrypted(password: "test password one")
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encrypted) as? [String: Any])
        envelope["rounds"] = 1
        XCTAssertThrowsError(try FaithgramSessionBackup.decrypt(JSONSerialization.data(withJSONObject: envelope), password: "test password one"))
        envelope["rounds"] = 600_000
        envelope["sealed"] = Data(repeating: 0, count: 100).base64EncodedString()
        XCTAssertThrowsError(try FaithgramSessionBackup.decrypt(JSONSerialization.data(withJSONObject: envelope), password: "test password one"))
    }
}
