import Foundation
import XCTest
@testable import PatchClientCore

final class PreferencesTests: XCTestCase {
    override func tearDown() {
        for option in PatchClientOption.allCases { UserDefaults.standard.removeObject(forKey: "patchclient.option." + option.rawValue) }
        for key in ["regexRules", "badgeGrants", "deletedMark", "editedMark", "mediaRules"] { UserDefaults.standard.removeObject(forKey: "faithgram." + key) }
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
        FaithgramPreferences.setBadge(.verified, peerId: 98765)
        XCTAssertEqual(FaithgramPreferences.badge(for: 98765), .verified)
        XCTAssertEqual(FaithgramPreferences.badge(for: 1000), .developer)
        FaithgramPreferences.setBadge(nil, peerId: 98765)
        XCTAssertNil(FaithgramPreferences.badge(for: 98765))
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
