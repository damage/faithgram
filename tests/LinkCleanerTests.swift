import Foundation
import XCTest
@testable import PatchClientCore

final class LinkCleanerTests: XCTestCase {
    func testTrackingParametersAreRemovedAndUsefulParametersAndFragmentStay() {
        XCTAssertEqual(FaithgramLinkCleaner.cleanURL("https://example.com/page?id=42&utm_source=mail&fbclid=abc#part"), "https://example.com/page?id=42#part")
        XCTAssertEqual(FaithgramLinkCleaner.cleanURL("https://example.com/?UTM_medium=x"), "https://example.com/")
        XCTAssertEqual(FaithgramLinkCleaner.cleanURL("tg://resolve?domain=faithgram&utm_source=x"), "tg://resolve?domain=faithgram&utm_source=x")
        XCTAssertEqual(FaithgramLinkCleaner.cleanURL("https://example.com/?q=a%2Fb"), "https://example.com/?q=a%2Fb")
    }
    func testSignedURLsAndExcludedCodeAreUntouched() {
        let signed = "https://example.com/file?utm_source=x&sig=abcdef"
        XCTAssertEqual(FaithgramLinkCleaner.cleanURL(signed), signed)
        let code = "https://example.com/?utm_source=x"
        XCTAssertTrue(FaithgramLinkCleaner.edits(in: code, excluding: [NSRange(location: 0, length: (code as NSString).length)]).isEmpty)
    }
    func testUnicodeOffsetsAndFormattingSurviveMultipleShortenedLinks() {
        let text = "🧹 https://example.com/?utm_source=x конец https://example.org/?fbclid=y done"
        let edits = FaithgramLinkCleaner.edits(in: text)
        XCTAssertEqual(edits.count, 2)
        let cleaned = FaithgramLinkCleaner.clean(NSAttributedString(string: text)).string
        XCTAssertEqual(cleaned, "🧹 https://example.com/ конец https://example.org/ done")
        let oldRange = (text as NSString).range(of: "done")
        let newRange = FaithgramLinkCleaner.remap(oldRange, through: edits)
        XCTAssertEqual((cleaned as NSString).substring(with: newRange), "done")
        let entire = FaithgramLinkCleaner.remap(NSRange(location: 0, length: (text as NSString).length), through: edits)
        XCTAssertEqual(entire.length, (cleaned as NSString).length)
    }
}
