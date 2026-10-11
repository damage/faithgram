import Foundation
import XCTest
@testable import PatchClientCore

final class ChoicesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        for option in PatchClientOption.allCases { UserDefaults.standard.removeObject(forKey: "patchclient.option." + option.rawValue) }
        for choice in FaithgramChoices.all { UserDefaults.standard.removeObject(forKey: choice.storageKey) }
        UserDefaults.standard.removeObject(forKey: FaithgramSettingsProfiles.storageKey)
    }
    override func tearDown() {
        setUp()
        super.tearDown()
    }

    func testDefaultsOnOptionsReadTrueUntilStoredAndBackupKeepsTheStoredValue() {
        XCTAssertTrue(PatchClientPolicy.isEnabled(.secondsInMessages))
        XCTAssertFalse(PatchClientPolicy.isEnabled(.alwaysOffline))
        PatchClientPolicy.setEnabled(.secondsInMessages, false)
        XCTAssertFalse(PatchClientPolicy.isEnabled(.secondsInMessages))
        let backup = FaithgramSettingsBackup.capture()
        if case let .flag(value)? = backup.values["patchclient.option.secondsInMessages"] { XCTAssertFalse(value) } else { XCTFail("missing flag") }
    }

    func testMultiValueChoicesHonourExclusiveValuesAndNeverBecomeEmpty() {
        let choice = FaithgramChoices.otherPhone
        XCTAssertEqual(FaithgramChoices.value(choice), "disable")
        FaithgramChoices.select(choice, "spoiler")
        XCTAssertEqual(FaithgramChoices.values(choice), ["spoiler"])
        FaithgramChoices.select(choice, "screenSharing")
        XCTAssertEqual(FaithgramChoices.values(choice), ["spoiler", "screenSharing"])
        XCTAssertEqual(FaithgramChoices.label(choice), "Spoiler, Screen sharing")
        FaithgramChoices.select(choice, "full")
        XCTAssertEqual(FaithgramChoices.values(choice), ["full"])
        FaithgramChoices.select(choice, "spoiler")
        FaithgramChoices.select(choice, "spoiler")
        XCTAssertEqual(FaithgramChoices.values(choice), ["disable"])
        XCTAssertFalse(choice.isValid("full,spoiler"))
        XCTAssertFalse(choice.isValid("nonsense"))
        XCTAssertFalse(FaithgramChoices.set(choice, "spoiler,spoiler"))
        UserDefaults.standard.set("broken", forKey: choice.storageKey)
        XCTAssertEqual(FaithgramChoices.value(choice), "disable")
    }

    func testOwnPhoneCoverKeepsTheLegacySwitchInSync() {
        FaithgramProfileCover.select(.phone, ownProfile: true, option: "full")
        XCTAssertTrue(PatchClientPolicy.isEnabled(.hideSelfPhone))
        XCTAssertTrue(FaithgramProfileCover.hidesRow(.phone, ownProfile: true))
        FaithgramProfileCover.select(.phone, ownProfile: true, option: "spoiler")
        XCTAssertFalse(PatchClientPolicy.isEnabled(.hideSelfPhone))
        XCTAssertTrue(FaithgramProfileCover.spoilers(.phone, ownProfile: true))
        XCTAssertFalse(FaithgramProfileCover.hidesRow(.phone, ownProfile: true))
        PatchClientPolicy.setEnabled(.hideSelfPhone, true)
        XCTAssertEqual(FaithgramProfileCover.label(.phone, ownProfile: true), "Full")
        XCTAssertFalse(FaithgramProfileCover.hidesRow(.phone, ownProfile: false))
    }

    func testSettingsProfilesRoundTripThroughLinksAndSkipProtectedKeys() throws {
        PatchClientPolicy.setEnabled(.cleanLinks, true)
        PatchClientPolicy.setEnabled(.callConfirmation, true)
        FaithgramChoices.set(FaithgramChoices.downloadBoost, "x4")
        let profile = try XCTUnwrap(FaithgramSettingsProfiles.saveCurrent(name: "  Night  "))
        XCTAssertEqual(profile.name, "Night")
        XCTAssertNil(profile.values["patchclient.option.callConfirmation"])
        let link = try XCTUnwrap(FaithgramSettingsProfiles.link(for: profile))
        XCTAssertTrue(link.hasPrefix("faithgram://profile?data="))
        let imported = try FaithgramSettingsProfiles.profile(fromLink: link)
        XCTAssertEqual(imported.values["patchclient.option.cleanLinks"].map { if case .flag(true) = $0 { return true } else { return false } }, true)

        PatchClientPolicy.setEnabled(.cleanLinks, false)
        PatchClientPolicy.setEnabled(.callConfirmation, false)
        FaithgramChoices.set(FaithgramChoices.downloadBoost, "disabled")
        try FaithgramSettingsProfiles.apply(imported)
        XCTAssertTrue(PatchClientPolicy.isEnabled(.cleanLinks))
        XCTAssertFalse(PatchClientPolicy.isEnabled(.callConfirmation), "protected keys stay untouched when a profile is applied")
        XCTAssertEqual(FaithgramChoices.value(FaithgramChoices.downloadBoost), "x4")

        XCTAssertThrowsError(try FaithgramSettingsProfiles.profile(fromLink: "faithgram://profile?data=bm9wZQ"))
        XCTAssertThrowsError(try FaithgramSettingsProfiles.profile(fromLink: "https://example.com"))
        XCTAssertNil(FaithgramSettingsProfiles.saveCurrent(name: "   "))
    }

    func testBackupRejectsInvalidChoiceAndSizeValues() throws {
        let valid = FaithgramSettingsBackup(version: 1, createdAt: Date(), values: ["faithgram.choice.downloadBoost": .text("x2"), "faithgram.stickerSize": .text("150")])
        XCTAssertNoThrow(try valid.validate())
        XCTAssertThrowsError(try FaithgramSettingsBackup(version: 1, createdAt: Date(), values: ["faithgram.choice.downloadBoost": .text("x3")]).validate())
        XCTAssertThrowsError(try FaithgramSettingsBackup(version: 1, createdAt: Date(), values: ["faithgram.stickerSize": .text("5")]).validate())
        XCTAssertThrowsError(try FaithgramSettingsBackup(version: 1, createdAt: Date(), values: ["faithgram.choice.profile.other.phone": .text("full,spoiler")]).validate())
    }
}
