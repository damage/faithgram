import Foundation
import XCTest
@testable import PatchClientCore

final class BadgeSignatureTests: XCTestCase {
    private let publicKey = "vdb9HM99ehd0YNB1YNFThaasPNSoW4GpsexOpXvHPb4="
    private var fixture: Data { Data(base64Encoded: "eyJwYXlsb2FkIjoiZXlKMlpYSnphVzl1SWpveExDSnlaWFpwYzJsdmJpSTZOU3dpWjJWdVpYSmhkR1ZrUVhRaU9qRTNNREF3TURBd01EQXNJbWR5WVc1MGN5STZXM3NpYVdRaU9pSjBaWE4wTFc5M2JtVnlJaXdpY0dWbGNrbGtJam94TURBd0xDSnliMnhsSWpvaVpHVjJaV3h2Y0dWeUlpd2lhWE56ZFdWa1FYUWlPbTUxYkd3c0ltbHpjM1ZsWkVKNUlqb3hNREF3TENKbGVIQnBjbVZ6UVhRaU9tNTFiR3dzSW5KbGRtOXJaV1JCZENJNmJuVnNiQ3dpYm05MFpTSTZJaUo5WFgwPSIsInNpZ25hdHVyZSI6IlVFS3dVRm9qUXdWeFVZXC9TMWcwd2twUDZTc3BRMkJYVVQ5SlJNMHhkYmtWMVhUY0l5VW5NSTRFZGx6cDc3aXFab3hVRE44MGplYXNLMGJVRkszMGxEdz09In0=")! }
    private let now = Date(timeIntervalSince1970: 1700000010)
    override func setUp() {
        super.setUp()
        FaithgramPreferences.ownerIdOverride = 1000
    }
    override func tearDown() {
        FaithgramPreferences.ownerIdOverride = nil
        super.tearDown()
    }
    func testSignedServerFixtureDecodesTheOwnerAndRevision() throws {
        let snapshot = try FaithgramBadgeService.verify(fixture, publicKey: publicKey, now: now)
        XCTAssertEqual(snapshot.revision, 5)
        XCTAssertEqual(snapshot.grants.first?.peerId, 1000)
        XCTAssertEqual(snapshot.grants.first?.role, .developer)
        XCTAssertNil(snapshot.grants.first?.issuedAt)
    }
    func testTamperingWrongKeyAndRollbackAreRejected() throws {
        var envelope = try JSONSerialization.jsonObject(with: fixture) as! [String: String]
        var payload = Data(base64Encoded: envelope["payload"]!)!
        payload.append(32)
        envelope["payload"] = payload.base64EncodedString()
        let corrupted = try JSONSerialization.data(withJSONObject: envelope)
        XCTAssertThrowsError(try FaithgramBadgeService.verify(corrupted, publicKey: publicKey, now: now))
        XCTAssertThrowsError(try FaithgramBadgeService.verify(fixture, publicKey: Data(repeating: 1, count: 32).base64EncodedString(), now: now))
        XCTAssertThrowsError(try FaithgramBadgeService.verify(fixture, publicKey: publicKey, now: now, minimumRevision: 6))
    }
    func testOldOnlineSnapshotAndExpiredOfflineCacheAreRejected() throws {
        let later = now.addingTimeInterval(2 * 86400)
        XCTAssertThrowsError(try FaithgramBadgeService.verify(fixture, publicKey: publicKey, now: later))
        XCTAssertNoThrow(try FaithgramBadgeService.verify(fixture, publicKey: publicKey, now: later, allowCached: true))
        XCTAssertThrowsError(try FaithgramBadgeService.verify(fixture, publicKey: publicKey, now: now.addingTimeInterval(8 * 86400), allowCached: true))
    }
}
