import Foundation
import XCTest
@testable import PatchClientCore

final class HistoryTests: XCTestCase {
    private var directory: URL!
    private let key = Data(repeating: 0x27, count: 32)
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("faithgram-test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func testHistorySurvivesRelaunchAndPreservesAllPastVersions() throws {
        let original = FaithgramHistoryRevision(text: "Original CASE 🧹", messageDate: 1, authorId: 123, media: Data([1]), attributes: Data([2]))
        let edited = FaithgramHistoryRevision(text: "changed", messageDate: 1, authorId: 123, media: Data([1]), attributes: Data([2]))
        let store = try FaithgramHistoryStore(directory: directory, encryptionKey: key)
        try store.capture(peerId: 123, namespace: 0, messageId: 456, revision: original, deleted: false)
        try store.capture(peerId: 123, namespace: 0, messageId: 456, revision: original, deleted: false)
        try store.capture(peerId: 123, namespace: 0, messageId: 456, revision: edited, deleted: true)
        let reopened = try FaithgramHistoryStore(directory: directory, encryptionKey: key)
        let record = try XCTUnwrap(reopened.record(peerId: 123, namespace: 0, messageId: 456))
        XCTAssertEqual(record.revisions, [original, edited])
        XCTAssertNotNil(record.deletedAt)
        XCTAssertEqual(try reopened.records().count, 1)
        let ciphertext = try Data(contentsOf: directory.appendingPathComponent(record.key + ".fgh"))
        XCTAssertNil(ciphertext.range(of: Data(original.text.utf8)))
    }
    func testTamperedOrMisidentifiedHistoryFailsAuthentication() throws {
        let store = try FaithgramHistoryStore(directory: directory, encryptionKey: key)
        try store.capture(peerId: 1, namespace: 0, messageId: 2, revision: FaithgramHistoryRevision(text: "private", messageDate: 1, authorId: nil, media: Data(), attributes: Data()), deleted: true)
        let file = directory.appendingPathComponent("1_0_2.fgh")
        let destination = directory.appendingPathComponent("1_0_3.fgh")
        try FileManager.default.copyItem(at: file, to: destination)
        XCTAssertThrowsError(try store.record(peerId: 1, namespace: 0, messageId: 3))
        var data = try Data(contentsOf: file)
        data[data.count / 2] ^= 1
        try data.write(to: file)
        XCTAssertThrowsError(try store.record(peerId: 1, namespace: 0, messageId: 2))
        let wrong = try FaithgramHistoryStore(directory: directory, encryptionKey: Data(repeating: 0x29, count: 32))
        XCTAssertThrowsError(try wrong.records())
    }
    func testMediaStreamsAcrossChunksAndRejectsTruncationAndIdentityChanges() throws {
        let input = directory.appendingPathComponent("input.dat")
        let output = directory.appendingPathComponent("output.dat")
        let archiveDirectory = directory.appendingPathComponent("media")
        let data = Data((0..<1_100_000).map { UInt8(truncatingIfNeeded: $0) })
        try data.write(to: input)
        let archive = try FaithgramMediaArchive(directory: archiveDirectory, key: key)
        try archive.save(resource: "resource-1", source: input)
        XCTAssertTrue(try archive.restore(resource: "resource-1", destination: output))
        XCTAssertEqual(try Data(contentsOf: output), data)
        try FileManager.default.removeItem(at: output)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: archiveDirectory, includingPropertiesForKeys: nil).first)
        var ciphertext = try Data(contentsOf: file)
        ciphertext.removeLast(8)
        try ciphertext.write(to: file)
        XCTAssertThrowsError(try archive.restore(resource: "resource-1", destination: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(try archive.restore(resource: "unknown", destination: output))
    }
}
