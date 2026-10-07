import Foundation

public enum FaithgramPreferences {
    public static let changed = Notification.Name("faithgram.preferences.changed")
    private static let defaults = UserDefaults.standard

    public static func text(_ key: String, fallback: String = "") -> String {
        return defaults.string(forKey: "faithgram." + key) ?? fallback
    }

    public static func setText(_ key: String, _ value: String) {
        if defaults.string(forKey: "faithgram." + key) == value { return }
        defaults.set(value, forKey: "faithgram." + key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    public static func interfaceText(_ text: String) -> String {
        return PatchClientPolicy.isEnabled(.lowercaseInterface) ? text.lowercased() : text
    }

    public static var ghostMode: Bool {
        let options: [PatchClientOption] = [.blockCloudReads, .alwaysOffline, .blockTyping]
        return options.allSatisfy(PatchClientPolicy.isEnabled)
    }

    public static func setGhostMode(_ enabled: Bool) {
        for option: PatchClientOption in [.blockCloudReads, .alwaysOffline, .blockTyping] {
            PatchClientPolicy.setEnabled(option, enabled)
        }
    }

    public static var deletedMark: String { return text("deletedMark", fallback: "🧹") }
    public static var editedMark: String { return text("editedMark", fallback: "🧹") }

    public static var mediaRules: [String: Bool] {
        guard let data = defaults.data(forKey: "faithgram.mediaRules") else { return [:] }
        return (try? JSONDecoder().decode([String: Bool].self, from: data)) ?? [:]
    }
    public static func setMediaRules(_ rules: [String: Bool]) {
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: "faithgram.mediaRules")
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
    public static func setMediaRule(peerId: Int64, save: Bool) {
        var rules = mediaRules
        rules[String(peerId)] = save
        setMediaRules(rules)
    }

    public enum Badge: String, Codable, CaseIterable {
        case developer
        case betaTester
        case verified

        public var fileId: Int64? {
            switch self {
            case .developer: return 5988023995125993550
            case .verified: return 5951665890079544884
            case .betaTester: return nil
            }
        }

        public var title: String {
            switch self {
            case .developer: return "developer"
            case .betaTester: return "beta tester"
            case .verified: return "verified user"
            }
        }
    }

    public static let badgeOwnerId: Int64 = 1000

    public static var badgeGrants: [String: Badge] {
        guard let data = defaults.data(forKey: "faithgram.badgeGrants"),
              let grants = try? JSONDecoder().decode([String: Badge].self, from: data) else {
            return [String(badgeOwnerId): .developer]
        }
        return grants
    }

    public static func badge(for peerId: Int64) -> Badge? {
        return badgeGrants[String(peerId)]
    }

    public static func setBadge(_ badge: Badge?, peerId: Int64) {
        var grants = badgeGrants
        grants[String(peerId)] = badge
        if let data = try? JSONEncoder().encode(grants) {
            defaults.set(data, forKey: "faithgram.badgeGrants")
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
}
