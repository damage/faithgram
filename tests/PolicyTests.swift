import Foundation
import XCTest
import TelegramApi
@testable import PatchClientCore

final class PolicyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        for option in PatchClientOption.allCases {
            PatchClientPolicy.setEnabled(option, false)
        }
    }

    override func tearDown() {
        for option in PatchClientOption.allCases {
            UserDefaults.standard.removeObject(forKey: "patchclient.option." + option.rawValue)
        }
        super.tearDown()
    }

    func testOfflineRewriteMatchesTheActualAPISerializerAndLeavesOriginalIntact() {
        let original = Api.functions.account.updateStatus(offline: .boolFalse)
        let originalBytes = original.1.makeData()
        PatchClientPolicy.setEnabled(.alwaysOffline, true)
        let rewritten = PatchClientPolicy.payload(for: original.0, original: original.1)
        XCTAssertEqual(rewritten, Api.functions.account.updateStatus(offline: .boolTrue).1.makeData())
        XCTAssertEqual(original.1.makeData(), originalBytes)
        PatchClientPolicy.setEnabled(.alwaysOffline, false)
        XCTAssertEqual(PatchClientPolicy.payload(for: original.0, original: original.1), originalBytes)
    }

    func testContactPrivacyRewritePreservesTheRestOfTheSerializedRequest() {
        let original = Api.functions.contacts.addContact(flags: 1,
            id: .inputUserSelf, firstName: "Zoë", lastName: "", phone: "", note: nil)
        let expected = Api.functions.contacts.addContact(flags: 0,
            id: .inputUserSelf, firstName: "Zoë", lastName: "", phone: "", note: nil)
        let originalBytes = original.1.makeData()
        PatchClientPolicy.setEnabled(.noPhoneException, true)
        XCTAssertEqual(PatchClientPolicy.payload(for: original.0, original: original.1), expected.1.makeData())
        XCTAssertEqual(original.1.makeData(), originalBytes)
    }

    func testCloudReadBlockingDoesNotSuppressSendingOrSecretChatDecryption() {
        PatchClientPolicy.setEnabled(.blockCloudReads, true)
        XCTAssertTrue(PatchClientPolicy.shouldCompleteLocally("messages.readHistory"))
        XCTAssertTrue(PatchClientPolicy.shouldCompleteLocally("channels.readMessageContents"))
        XCTAssertFalse(PatchClientPolicy.shouldCompleteLocally("messages.sendMessage"))
        XCTAssertFalse(PatchClientPolicy.shouldCompleteLocally("messages.readEncryptedHistory"))
        XCTAssertFalse(PatchClientPolicy.shouldCompleteLocally("messages.sendEncryptedService"))
    }

    func testIndependentFlagsAndRestoringDefaultBehavior() {
        PatchClientPolicy.setEnabled(.localDrafts, true)
        XCTAssertTrue(PatchClientPolicy.shouldCompleteLocally("messages.saveDraft"))
        XCTAssertFalse(PatchClientPolicy.shouldCompleteLocally("messages.setTyping"))
        PatchClientPolicy.setEnabled(.blockTyping, true)
        XCTAssertTrue(PatchClientPolicy.shouldCompleteLocally("messages.setEncryptedTyping"))
        PatchClientPolicy.setEnabled(.localDrafts, false)
        XCTAssertFalse(PatchClientPolicy.shouldCompleteLocally("messages.saveDraft"))
    }

    func testAdSuppressionProducesTheExpectedTypedEmptyResponse() {
        XCTAssertNil(PatchClientPolicy.localResponse(for: "messages.getSponsoredMessages"))
        PatchClientPolicy.setEnabled(.hideAds, true)
        let response = PatchClientPolicy.localResponse(for: "messages.getSponsoredMessages")
        guard let response = response as? Api.messages.SponsoredMessages else {
            return XCTFail("Wrong sponsored-message response type")
        }
        guard case .sponsoredMessagesEmpty = response else {
            return XCTFail("Unexpected sponsored-message content")
        }
    }
}
