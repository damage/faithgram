import Foundation
import XCTest
@testable import PatchClientCore

final class SettingsBackupTests: XCTestCase {
    func testEncryptedSettingsRoundTripExcludesSessionsAndBadgeCredentials() throws {
        let name = "faithgram-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "patchclient.option.cleanLinks")
        defaults.set("ghost", forKey: "faithgram.gesture.down")
        defaults.set(Data([1, 2]), forKey: "faithgram.badgeRecords")
        defaults.set("synthetic-token", forKey: "faithgram.adminToken")
        defaults.set("synthetic-session", forKey: "telegram.session")
        let backup = FaithgramSettingsBackup.capture(defaults: defaults)
        XCTAssertNil(backup.values["faithgram.badgeRecords"])
        XCTAssertNil(backup.values["faithgram.adminToken"])
        XCTAssertNil(backup.values["telegram.session"])
        let encrypted = try backup.encrypted(password: "settings test password")
        let restored = try FaithgramSettingsBackup.decrypt(encrypted, password: "settings test password")
        defaults.set(false, forKey: "patchclient.option.cleanLinks")
        defaults.set("changed", forKey: "faithgram.deletedMark")
        try restored.apply(defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: "patchclient.option.cleanLinks"))
        XCTAssertEqual(defaults.string(forKey: "faithgram.gesture.down"), "ghost")
        XCTAssertNil(defaults.string(forKey: "faithgram.deletedMark"))
        XCTAssertEqual(defaults.string(forKey: "telegram.session"), "synthetic-session")
        XCTAssertThrowsError(try FaithgramSettingsBackup.decrypt(encrypted, password: "wrong settings password"))
        XCTAssertThrowsError(try FaithgramVault.decryptBackup(encrypted, password: "settings test password"))
    }
    func testInvalidImportsCannotMutateExistingSettings() throws {
        let name = "faithgram-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "patchclient.option.cleanLinks")
        let injected = FaithgramSettingsBackup(version: 1, createdAt: Date(), values: ["patchclient.option.cleanLinks": .flag(false), "faithgram.adminToken": .text("injected")])
        XCTAssertThrowsError(try injected.apply(defaults: defaults))
        XCTAssertTrue(defaults.bool(forKey: "patchclient.option.cleanLinks"))
        XCTAssertNil(defaults.string(forKey: "faithgram.adminToken"))
        let regex = FaithgramSettingsBackup(version: 1, createdAt: Date(), values: ["faithgram.regexRules": .text("[")])
        XCTAssertThrowsError(try regex.validate())
        let chat = FaithgramSettingsBackup(version: 1, createdAt: Date(), values: ["faithgram.privacy.ghostChats": .strings(["3:-123", "0:42"])])
        XCTAssertNoThrow(try chat.validate())
        let invalid = FaithgramSettingsBackup(version: 1, createdAt: Date(), values: ["faithgram.privacy.ghostChats": .strings(["0:-123"])])
        XCTAssertThrowsError(try invalid.validate())
    }
    func testTamperingAndSessionFilesAreRejected() throws {
        let backup = FaithgramSettingsBackup(version: 1, createdAt: Date(), values: [:])
        let encrypted = try backup.encrypted(password: "settings test password")
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encrypted) as? [String: Any])
        envelope["sealed"] = Data(repeating: 0, count: 100).base64EncodedString()
        XCTAssertThrowsError(try FaithgramSettingsBackup.decrypt(JSONSerialization.data(withJSONObject: envelope), password: "settings test password"))
        let sessionEnvelope = try FaithgramVault.encryptBackup(Data("{}".utf8), password: "settings test password")
        XCTAssertThrowsError(try FaithgramSettingsBackup.decrypt(sessionEnvelope, password: "settings test password"))
    }
}
