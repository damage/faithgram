import Foundation
import XCTest
@testable import PatchClientCore

final class PreferencesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        FaithgramPreferences.ownerIdOverride = 1000
    }
    override func tearDown() {
        FaithgramPreferences.ownerIdOverride = nil
        for option in PatchClientOption.allCases { UserDefaults.standard.removeObject(forKey: "patchclient.option." + option.rawValue) }
        for key in ["regexRules", "badgeGrants", "badgeRecords", "deletedMark", "editedMark", "mediaRules"] { UserDefaults.standard.removeObject(forKey: "faithgram." + key) }
        super.tearDown()
    }
    func testGhostModeRequiresAllPoliciesAndDoesNotChangeSessionSending() {
        FaithgramPreferences.setGhostMode(true)
        XCTAssertTrue(FaithgramPreferences.ghostMode)
        PatchClientPolicy.setEnabled(.blockTyping, false)
        XCTAssertFalse(FaithgramPreferences.ghostMode)
        FaithgramPreferences.setGhostMode(false)
        XCTAssertFalse(PatchClientPolicy.shouldCompleteLocally("messages.sendEncryptedService"))
        XCTAssertFalse(PatchClientPolicy.shouldCompleteLocally("messages.sendMessage"))
    }
    func testBadgeOwnerAndSeparateGrantsUseTheRequestedIDs() {
        XCTAssertEqual(FaithgramPreferences.badge(for: 1000), .developer)
        XCTAssertEqual(FaithgramPreferences.Badge.developer.fileId, 5988023995125993550)
        XCTAssertEqual(FaithgramPreferences.Badge.verified.fileId, 5951665890079544884)
        XCTAssertNil(FaithgramPreferences.Badge.betaTester.fileId)
        XCTAssertTrue(FaithgramPreferences.grantBadge(.verified, peerId: 98765, accountPeerId: 1000))
        XCTAssertEqual(FaithgramPreferences.badge(for: 98765), .verified)
        XCTAssertEqual(FaithgramPreferences.badge(for: 1000), .developer)
        let grant = FaithgramPreferences.badges(for: 98765).first!
        XCTAssertTrue(FaithgramPreferences.revokeBadge(id: grant.id, accountPeerId: 1000))
        XCTAssertNil(FaithgramPreferences.badge(for: 98765))
    }
    func testOnlyOwnerCanIssueAndRevokeBadges() {
        XCTAssertFalse(FaithgramPreferences.canManageBadges(accountPeerId: 999))
        XCTAssertFalse(FaithgramPreferences.grantBadge(.developer, peerId: 98765, accountPeerId: 999))
        XCTAssertTrue(FaithgramPreferences.grantBadge(.betaTester, peerId: 98765, accountPeerId: 1000))
        let grant = FaithgramPreferences.badges(for: 98765).first!
        XCTAssertFalse(FaithgramPreferences.revokeBadge(id: grant.id, accountPeerId: 999))
        XCTAssertEqual(FaithgramPreferences.badge(for: 98765), .betaTester)
    }
    func testMultipleBadgesKeepIssueDatesAndRevocationHistory() {
        let now = Date(timeIntervalSince1970: 1700000000)
        XCTAssertTrue(FaithgramPreferences.grantBadge(.developer, peerId: 98765, accountPeerId: 1000, note: "first", now: now))
        XCTAssertTrue(FaithgramPreferences.grantBadge(.paidSubscriber, peerId: 98765, accountPeerId: 1000, now: now))
        XCTAssertEqual(FaithgramPreferences.badges(for: 98765, at: now).count, 2)
        XCTAssertTrue(FaithgramPreferences.grantBadge(.developer, peerId: 98765, accountPeerId: 1000, note: "updated", now: now.addingTimeInterval(50)))
        let grant = FaithgramPreferences.badges(for: 98765, at: now).first!
        XCTAssertEqual(grant.issuedAt, now)
        XCTAssertEqual(grant.note, "updated")
        XCTAssertTrue(FaithgramPreferences.revokeBadge(id: grant.id, accountPeerId: 1000, now: now.addingTimeInterval(100)))
        XCTAssertEqual(FaithgramPreferences.badges(for: 98765, at: now.addingTimeInterval(101)).map { $0.role }, [.paidSubscriber])
        XCTAssertEqual(FaithgramPreferences.localBadgeRecords.first { $0.id == grant.id }?.revokedAt, now.addingTimeInterval(100))
    }
    func testLegacyGrantsMigrateWithoutInventingDatesAndExpiryWorks() throws {
        UserDefaults.standard.set(try JSONEncoder().encode(["98765": FaithgramPreferences.Badge.verified]), forKey: "faithgram.badgeGrants")
        XCTAssertNil(FaithgramPreferences.badges(for: 98765).first?.issuedAt)
        let now = Date(timeIntervalSince1970: 1700000000)
        XCTAssertTrue(FaithgramPreferences.grantBadge(.betaTester, peerId: 98765, accountPeerId: 1000, expiresAt: now.addingTimeInterval(60), now: now))
        XCTAssertEqual(FaithgramPreferences.badges(for: 98765, at: now.addingTimeInterval(30)).count, 2)
        XCTAssertEqual(FaithgramPreferences.badges(for: 98765, at: now.addingTimeInterval(60)).count, 1)
        XCTAssertFalse(FaithgramPreferences.grantBadge(.developer, peerId: 0, accountPeerId: 1000))
    }
    func testRegexValidationUnicodeAndWorstCaseBudget() throws {
        let expressions = try FaithgramMessageFilter.compile("(?i)\\bpromotion\\b\n^спам")
        XCTAssertTrue(FaithgramMessageFilter.matches("PROMOTION today", expressions: expressions))
        XCTAssertTrue(FaithgramMessageFilter.matches("спам 🧹", expressions: expressions))
        XCTAssertFalse(FaithgramMessageFilter.matches("hello", expressions: expressions))
        XCTAssertThrowsError(try FaithgramMessageFilter.compile("["))
        XCTAssertThrowsError(try FaithgramMessageFilter.compile(Array(repeating: "x", count: 33).joined(separator: "\n")))
        XCTAssertThrowsError(try FaithgramMessageFilter.compile(String(repeating: "x", count: 513)))
        let difficult = try FaithgramMessageFilter.compile("(a+)+$")
        let start = Date()
        XCTAssertFalse(FaithgramMessageFilter.matches(String(repeating: "a", count: 4000) + "!", expressions: difficult))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }
    func testDeviceOnlyModesBlockCloudFallbackAndLeaveUnrelatedRPCsAlone() {
        PatchClientPolicy.setEnabled(.localTranslation, true)
        PatchClientPolicy.setEnabled(.localTranscription, true)
        for name in ["messages.translateText", "messages.translateRichMessage", "messages.composeMessageWithAI", "messages.composeRichMessageWithAI", "messages.transcribeAudio"] { XCTAssertTrue(PatchClientPolicy.shouldCompleteLocally(name)) }
        XCTAssertFalse(PatchClientPolicy.shouldCompleteLocally("upload.getFile"))
        XCTAssertFalse(PatchClientPolicy.shouldCompleteLocally("messages.sendMedia"))
    }
}
