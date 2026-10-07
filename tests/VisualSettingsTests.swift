import Foundation
import XCTest
import TelegramApi
@testable import PatchClientCore

final class VisualSettingsTests: XCTestCase {
    override func tearDown() {
        for option in PatchClientOption.allCases { PatchClientPolicy.setEnabled(option, false) }
        for field in FaithgramVisualPreferences.profileFields + FaithgramVisualPreferences.balanceFields + FaithgramVisualPreferences.regularGiftFields + FaithgramVisualPreferences.uniqueGiftFields + FaithgramVisualPreferences.hiddenGiftFields {
            UserDefaults.standard.removeObject(forKey: "faithgram.visual." + field.key)
        }
        super.tearDown()
    }
    func testMalformedGiftAndIdentityValuesAreRejected() throws {
        let fields = FaithgramVisualPreferences.profileFields + FaithgramVisualPreferences.uniqueGiftFields + FaithgramVisualPreferences.regularGiftFields
        for key in ["giftDate", "uniqueNumber", "ratingLevel"] {
            let field = try XCTUnwrap(fields.first { $0.key == key })
            XCTAssertThrowsError(try FaithgramVisualPreferences.validate(field, text: "999999999999"))
            XCTAssertNoThrow(try FaithgramVisualPreferences.validate(field, text: "123"))
        }
        XCTAssertThrowsError(try FaithgramVisualPreferences.validate(try XCTUnwrap(fields.first { $0.key == "uniqueModelRarity" }), text: "1001"))
        XCTAssertThrowsError(try FaithgramVisualPreferences.validate(try XCTUnwrap(fields.first { $0.key == "collectibleUrl" }), text: "javascript:alert(1)"))
        XCTAssertNoThrow(try FaithgramVisualPreferences.validate(try XCTUnwrap(fields.first { $0.key == "giftSenderId" }), text: "-100123456789"))
    }
    func testBalanceDisplayDoesNotChangeTheActualValue() throws {
        let field = try XCTUnwrap(FaithgramVisualPreferences.balanceFields.first { $0.key == "displayStars" })
        try FaithgramVisualPreferences.save(field, text: "100000")
        let actual: Int64 = 42
        XCTAssertEqual(FaithgramVisualPreferences.displayedBalance(actual, ton: false), actual)
        PatchClientPolicy.setEnabled(.customBalances, true)
        XCTAssertEqual(FaithgramVisualPreferences.displayedBalance(actual, ton: false), 100000)
        XCTAssertEqual(actual, 42)
        PatchClientPolicy.setEnabled(.customBalances, false)
        XCTAssertEqual(FaithgramVisualPreferences.displayedBalance(actual, ton: false), actual)
    }
    func testDecodedLoggerUsesActualNestedTLFields() throws {
        let request = Api.functions.contacts.addContact(flags: 1, id: .inputUserSelf, firstName: "Alice", lastName: "", phone: "", note: nil)
        let decoded = try XCTUnwrap(FaithgramProtocolLog.decoded(request.0) as? [String: Any])
        XCTAssertEqual(decoded["_"] as? String, "contacts.addContact")
        XCTAssertEqual(decoded["firstName"] as? String, "Alice")
        let peer = try XCTUnwrap(decoded["id"] as? [String: Any])
        XCTAssertEqual(peer["_"] as? String, "inputUserSelf")
        let response = try XCTUnwrap(FaithgramProtocolLog.decoded(Api.Bool.boolTrue) as? [String: Any])
        XCTAssertEqual(response["_"] as? String, "boolTrue")
        PatchClientPolicy.setEnabled(.protocolLogger, false)
        XCTAssertNil(FaithgramProtocolLog.begin(request.0, original: request.1))
    }
    func testMonetizationPoliciesLeaveOrdinaryMessagesAvailable() {
        for option in [PatchClientOption.hideStories, .hideGifts, .hideCurrencies, .hideBoosts, .disablePaidReactions, .hideEmojiStatus, .fakeGiftTransfer] {
            PatchClientPolicy.setEnabled(option, true)
        }
        for method in ["stories.getAllStories", "stories.readStories", "payments.transferStarGift", "payments.getStarsStatus", "premium.getBoostsStatus", "messages.sendPaidReaction", "account.updateEmojiStatus"] {
            XCTAssertTrue(PatchClientPolicy.shouldCompleteLocally(method), method)
        }
        for method in ["messages.sendMessage", "messages.sendMedia", "messages.getHistory", "auth.sendCode", "contacts.getBlocked"] {
            XCTAssertFalse(PatchClientPolicy.shouldCompleteLocally(method), method)
        }
    }
}
