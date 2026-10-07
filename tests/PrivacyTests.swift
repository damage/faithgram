import Foundation
import XCTest
import TelegramApi
@testable import PatchClientCore

final class PrivacyTests: XCTestCase {
    override func setUp() {
        for option in PatchClientOption.allCases { PatchClientPolicy.setEnabled(option, false) }
        for key in ["ghostChats", "custom", "previous"] { UserDefaults.standard.removeObject(forKey: "faithgram.privacy." + key) }
    }
    override func tearDown() {
        for option in PatchClientOption.allCases { UserDefaults.standard.removeObject(forKey: "patchclient.option." + option.rawValue) }
        for key in ["ghostChats", "custom", "previous"] { UserDefaults.standard.removeObject(forKey: "faithgram.privacy." + key) }
    }
    func testProfilesPreserveAppearanceAndChatRulesAndCanBeUndone() {
        PatchClientPolicy.setEnabled(.lowercaseInterface, true)
        FaithgramPrivacySettings.setGhostChat(namespace: 0, id: 42, enabled: true)
        XCTAssertTrue(FaithgramPrivacySettings.applyProfile("quiet"))
        XCTAssertTrue(PatchClientPolicy.isEnabled(.hideAppPreview))
        XCTAssertTrue(PatchClientPolicy.isEnabled(.cleanLinks))
        XCTAssertFalse(PatchClientPolicy.isEnabled(.blockCloudReads))
        XCTAssertEqual(FaithgramPrivacySettings.currentProfile, "quiet")
        XCTAssertTrue(FaithgramPrivacySettings.applyProfile("ghost"))
        XCTAssertTrue(FaithgramPreferences.ghostMode)
        XCTAssertTrue(FaithgramPrivacySettings.restorePreviousProfile())
        XCTAssertEqual(FaithgramPrivacySettings.currentProfile, "quiet")
        XCTAssertTrue(PatchClientPolicy.isEnabled(.lowercaseInterface))
        XCTAssertTrue(FaithgramPrivacySettings.isGhostChat(namespace: 0, id: 42))
        XCTAssertFalse(FaithgramPrivacySettings.restorePreviousProfile())
    }
    func testCustomProfileAndInvalidProfiles() {
        XCTAssertFalse(FaithgramPrivacySettings.applyProfile("custom"))
        XCTAssertFalse(FaithgramPrivacySettings.applyProfile("unknown"))
        PatchClientPolicy.setEnabled(.blockTyping, true)
        FaithgramPrivacySettings.saveCustomProfile()
        XCTAssertTrue(FaithgramPrivacySettings.applyProfile("standard"))
        XCTAssertFalse(PatchClientPolicy.isEnabled(.blockTyping))
        XCTAssertTrue(FaithgramPrivacySettings.applyProfile("custom"))
        XCTAssertTrue(PatchClientPolicy.isEnabled(.blockTyping))
    }
    func testTypedRequestsMatchOnlySelectedPeerAndLeaveStatusAndSendingAlone() {
        let peer = Api.InputPeer.inputPeerUser(.init(userId: 42, accessHash: 1))
        let other = Api.InputPeer.inputPeerUser(.init(userId: 43, accessHash: 1))
        FaithgramPrivacySettings.setGhostChat(namespace: 0, id: 42, enabled: true)
        XCTAssertTrue(PatchClientPolicy.shouldCompleteLocally(Api.functions.messages.readHistory(peer: peer, maxId: 1).0))
        XCTAssertTrue(PatchClientPolicy.shouldCompleteLocally(Api.functions.messages.setTyping(flags: 0, peer: peer, topMsgId: nil, action: .sendMessageTypingAction).0))
        XCTAssertFalse(PatchClientPolicy.shouldCompleteLocally(Api.functions.messages.readHistory(peer: other, maxId: 1).0))
        XCTAssertFalse(PatchClientPolicy.shouldCompleteLocally(Api.functions.account.updateStatus(offline: .boolFalse).0))
        XCTAssertFalse(PatchClientPolicy.shouldCompleteLocally("messages.sendMessage"))
        FaithgramPrivacySettings.setGhostChat(namespace: 0, id: 42, enabled: false)
        XCTAssertFalse(PatchClientPolicy.shouldCompleteLocally(Api.functions.messages.readHistory(peer: peer, maxId: 1).0))
        PatchClientPolicy.setEnabled(.blockCloudReads, true)
        XCTAssertTrue(PatchClientPolicy.shouldCompleteLocally(Api.functions.messages.readHistory(peer: peer, maxId: 1).0))
    }
    func testChannelGroupAndNegativeSecretChatIdsKeepNamespacesSeparate() {
        FaithgramPrivacySettings.setGhostChat(namespace: 2, id: 42, enabled: true)
        XCTAssertTrue(PatchClientPolicy.shouldCompleteLocally(Api.functions.channels.readHistory(channel: .inputChannel(.init(channelId: 42, accessHash: 1)), maxId: 1).0))
        XCTAssertFalse(FaithgramPrivacySettings.suppressesRead(namespace: 0, id: 42))
        FaithgramPrivacySettings.setGhostChat(namespace: 1, id: 42, enabled: true)
        XCTAssertTrue(PatchClientPolicy.shouldCompleteLocally(Api.functions.messages.readHistory(peer: .inputPeerChat(.init(chatId: 42)), maxId: 1).0))
        FaithgramPrivacySettings.setGhostChat(namespace: 3, id: -123, enabled: true)
        let peer = Api.InputEncryptedChat.inputEncryptedChat(.init(chatId: -123, accessHash: 1))
        XCTAssertTrue(PatchClientPolicy.shouldCompleteLocally(Api.functions.messages.readEncryptedHistory(peer: peer, maxDate: 1).0))
        XCTAssertTrue(PatchClientPolicy.shouldCompleteLocally(Api.functions.messages.setEncryptedTyping(peer: peer, typing: .boolTrue).0))
        XCTAssertFalse(PatchClientPolicy.shouldCompleteLocally("messages.sendEncryptedService"))
        FaithgramPrivacySettings.setGhostChat(namespace: 0, id: -123, enabled: true)
        XCTAssertFalse(FaithgramPrivacySettings.isGhostChat(namespace: 0, id: -123))
    }
    func testStoryViewsRespectGlobalAndSelectedPeerReadControls() {
        let peer = Api.InputPeer.inputPeerUser(.init(userId: 42, accessHash: 1))
        let other = Api.InputPeer.inputPeerUser(.init(userId: 43, accessHash: 1))
        FaithgramPrivacySettings.setGhostChat(namespace: 0, id: 42, enabled: true)
        XCTAssertTrue(PatchClientPolicy.shouldCompleteLocally(Api.functions.stories.readStories(peer: peer, maxId: 1).0))
        XCTAssertTrue(PatchClientPolicy.shouldCompleteLocally(Api.functions.stories.incrementStoryViews(peer: peer, id: [1]).0))
        XCTAssertFalse(PatchClientPolicy.shouldCompleteLocally(Api.functions.stories.readStories(peer: other, maxId: 1).0))
        PatchClientPolicy.setEnabled(.blockCloudReads, true)
        XCTAssertTrue(PatchClientPolicy.shouldCompleteLocally(Api.functions.stories.incrementStoryViews(peer: other, id: [1]).0))
    }
}
