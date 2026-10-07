import Foundation

public enum FaithgramMessageFilterError: Error {
    case tooManyRules, ruleTooLong, invalidExpression
}
public enum FaithgramMessageFilter {
    private static let lock = NSLock()
    private static var cachedText = ""
    private static var cachedRules: [NSRegularExpression] = []

    public static func compile(_ text: String) throws -> [NSRegularExpression] {
        let rules = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard rules.count <= 32 else { throw FaithgramMessageFilterError.tooManyRules }
        return try rules.map { pattern in
            guard pattern.utf16.count <= 512 else { throw FaithgramMessageFilterError.ruleTooLong }
            guard let regex = try? NSRegularExpression(pattern: pattern) else { throw FaithgramMessageFilterError.invalidExpression }
            return regex
        }
    }
    public static func matches(_ text: String, expressions: [NSRegularExpression], budget: TimeInterval = 0.006) -> Bool {
        let input = String(text.prefix(4096))
        let deadline = Date().addingTimeInterval(budget)
        for expression in expressions {
            if Date() >= deadline { break }
            var found = false
            expression.enumerateMatches(in: input, options: [.reportProgress], range: NSRange(location: 0, length: (input as NSString).length)) { result, _, stop in
                if result != nil { found = true; stop.pointee = true }
                else if Date() >= deadline { stop.pointee = true }
            }
            if found { return true }
        }
        return false
    }
    public static func matches(_ text: String) -> Bool {
        guard PatchClientPolicy.isEnabled(.regexFilters) else { return false }
        let source = FaithgramPreferences.text("regexRules")
        lock.lock()
        if cachedText != source {
            cachedText = source
            cachedRules = (try? compile(source)) ?? []
        }
        let expressions = cachedRules
        lock.unlock()
        return matches(text, expressions: expressions)
    }
}
