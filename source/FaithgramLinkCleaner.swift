import Foundation

public enum FaithgramLinkCleaner {
    public struct Edit {
        public let range: NSRange
        public let replacement: String
    }
    public static func edits(in text: String, excluding: [NSRange] = []) -> [Edit] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let value = text as NSString
        return detector.matches(in: text, range: NSRange(location: 0, length: value.length)).compactMap { match in
            guard !excluding.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { return nil }
            let original = value.substring(with: match.range)
            let replacement = cleanURL(original)
            return replacement == original ? nil : Edit(range: match.range, replacement: replacement)
        }
    }
    public static func remap(_ range: NSRange, through edits: [Edit]) -> NSRange {
        func boundary(_ offset: Int) -> Int {
            var delta = 0
            for edit in edits {
                if offset < edit.range.location { break }
                let end = NSMaxRange(edit.range)
                let length = (edit.replacement as NSString).length
                if offset < end { return edit.range.location + delta + min(offset - edit.range.location, length) }
                delta += length - edit.range.length
            }
            return offset + delta
        }
        let start = boundary(range.location)
        return NSRange(location: start, length: max(0, boundary(NSMaxRange(range)) - start))
    }
    private static let tracking: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid", "yclid", "_ga", "_gl", "vero_id", "wickedid", "oly_anon_id", "oly_enc_id"]
    public static func cleanURL(_ text: String) -> String {
        guard var url = URLComponents(string: text), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme), url.host != nil, let items = url.queryItems else { return text }
        // Signed download and payment URLs depend on their original query string.
        let signed = Set(items.map { $0.name.lowercased() })
        if !signed.isDisjoint(with: ["sig", "signature", "x-amz-signature", "x-goog-signature", "token", "auth", "hmac"]) { return text }
        let kept = items.filter { !tracking.contains($0.name.lowercased()) && !$0.name.lowercased().hasPrefix("utm_") }
        guard kept.count != items.count else { return text }
        url.queryItems = kept.isEmpty ? nil : kept
        return url.string ?? text
    }
    public static func clean(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        for edit in edits(in: text.string).reversed() { result.replaceCharacters(in: edit.range, with: edit.replacement) }
        return result
    }
}
