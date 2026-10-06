import Foundation
import XCTest
@testable import PatchClientCore

final class StorageTests: XCTestCase {
    private var temporary: URL!

    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporary)
    }

    func testFirstLaunchWithoutAnAppGroupCanPersistTheDatabaseKey() throws {
        let container = try PatchClientStorage.containerURL(sharedContainer: nil, applicationSupport: temporary)
        XCTAssertTrue(container.path.hasPrefix(temporary.path + "/"))
        let keyURL = container.appendingPathComponent("telegram-data/.tempkey")
        let key = Data(repeating: 0x42, count: 48)
        try key.write(to: keyURL)

        let relaunchedContainer = try PatchClientStorage.containerURL(sharedContainer: nil, applicationSupport: temporary)
        XCTAssertEqual(relaunchedContainer, container)
        XCTAssertEqual(try Data(contentsOf: keyURL), key)
        XCTAssertEqual(try keyURL.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testExistingAppGroupKeepsItsAccountData() throws {
        let shared = temporary.appendingPathComponent("shared", isDirectory: true)
        let data = shared.appendingPathComponent("telegram-data", isDirectory: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let marker = data.appendingPathComponent("existing-account")
        try Data([1, 2, 3]).write(to: marker)

        let container = try PatchClientStorage.containerURL(sharedContainer: shared, applicationSupport: temporary)
        XCTAssertEqual(container, shared)
        XCTAssertEqual(try Data(contentsOf: marker), Data([1, 2, 3]))
    }

    func testUnwritableStorageFailsBeforeCreatingAnAccount() throws {
        let blocked = temporary.appendingPathComponent("file-instead-of-directory")
        try Data([0]).write(to: blocked)
        XCTAssertThrowsError(try PatchClientStorage.containerURL(sharedContainer: nil, applicationSupport: blocked))
        XCTAssertEqual(try Data(contentsOf: blocked), Data([0]))
    }
}
