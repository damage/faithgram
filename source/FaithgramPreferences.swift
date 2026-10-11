import Foundation

public enum FaithgramPreferences {
    public static let changed = Notification.Name("faithgram.preferences.changed")
    public static let restartLiveActivity = Notification.Name("faithgram.activity.restart")
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
        case paidSubscriber
        case verified

        public var fileId: Int64? {
            switch self {
            case .developer: return 5988023995125993550
            case .verified: return 5951665890079544884
            case .betaTester, .paidSubscriber: return nil
            }
        }

        public var title: String {
            switch self {
            case .developer: return "developer"
            case .betaTester: return "beta tester"
            case .paidSubscriber: return "paid subscriber"
            case .verified: return "verified user"
            }
        }

        public var explanation: String {
            switch self {
            case .developer: return "contributed to the development of faithgram and received a unique developer badge"
            case .betaTester, .paidSubscriber: return "supported the development of faithgram and received a unique badge"
            case .verified: return "verified by the developers of faithgram and received a unique badge"
            }
        }

        public var symbol: String {
            switch self {
            case .developer: return "hammer.fill"
            case .betaTester: return "ladybug.fill"
            case .paidSubscriber: return "heart.fill"
            case .verified: return "checkmark.seal.fill"
            }
        }
    }

    /// Comes from the badge service configuration (FAITHGRAM_OWNER_ID at build time). Tests override it.
    static var ownerIdOverride: Int64?
    public static var badgeOwnerId: Int64 { return ownerIdOverride ?? FaithgramBadgeService.shared.ownerId }

    public struct BadgeGrant: Codable, Equatable {
        public let id: String
        public let peerId: Int64
        public let role: Badge
        public let issuedAt: Date?
        public let issuedBy: Int64
        public var expiresAt: Date?
        public var note: String
        public var revokedAt: Date?

        public func isActive(at date: Date = Date()) -> Bool {
            return revokedAt == nil && (expiresAt == nil || expiresAt! > date)
        }
    }

    public static func canManageBadges(accountPeerId: Int64) -> Bool {
        return badgeOwnerId > 0 && accountPeerId == badgeOwnerId
    }

    private static let badgeLock = NSLock()
    private static var remoteBadgeRecords: [BadgeGrant]?

    public static func setRemoteBadgeRecords(_ records: [BadgeGrant]) {
        badgeLock.lock()
        let changedValue = remoteBadgeRecords != records
        remoteBadgeRecords = records
        badgeLock.unlock()
        if changedValue { NotificationCenter.default.post(name: changed, object: nil) }
    }

    public static var allBadgeGrants: [BadgeGrant] {
        badgeLock.lock()
        let records = remoteBadgeRecords
        badgeLock.unlock()
        return records ?? localBadgeRecords
    }

    public static var localBadgeRecords: [BadgeGrant] {
        if let data = defaults.data(forKey: "faithgram.badgeRecords"),
           let records = try? JSONDecoder().decode([BadgeGrant].self, from: data) {
            return records
        }
        let legacy: [String: Badge]
        if let data = defaults.data(forKey: "faithgram.badgeGrants"),
           let grants = try? JSONDecoder().decode([String: Badge].self, from: data) {
            legacy = grants
        } else {
            legacy = [String(badgeOwnerId): .developer]
        }
        return legacy.compactMap { key, role in
            guard let peerId = Int64(key), peerId > 0 else { return nil }
            return BadgeGrant(id: "legacy-\(peerId)-\(role.rawValue)", peerId: peerId, role: role, issuedAt: nil, issuedBy: badgeOwnerId, expiresAt: nil, note: "", revokedAt: nil)
        }
    }

    public static var badgeGrants: [String: Badge] {
        var result: [String: Badge] = [:]
        for record in allBadgeGrants where record.isActive() {
            if result[String(record.peerId)] == nil { result[String(record.peerId)] = record.role }
        }
        return result
    }

    public static func badge(for peerId: Int64) -> Badge? {
        return badges(for: peerId).first?.role
    }

    public static func badges(for peerId: Int64, at date: Date = Date()) -> [BadgeGrant] {
        return allBadgeGrants.filter { $0.peerId == peerId && $0.isActive(at: date) }.sorted {
            (Badge.allCases.firstIndex(of: $0.role) ?? 0) < (Badge.allCases.firstIndex(of: $1.role) ?? 0)
        }
    }

    @discardableResult
    public static func grantBadge(_ role: Badge, peerId: Int64, accountPeerId: Int64, note: String = "", expiresAt: Date? = nil, now: Date = Date()) -> Bool {
        guard canManageBadges(accountPeerId: accountPeerId), peerId > 0,
              note.utf8.count <= 1024, expiresAt == nil || expiresAt! > now else { return false }
        var records = localBadgeRecords
        if let index = records.firstIndex(where: { $0.peerId == peerId && $0.role == role && $0.isActive(at: now) }) {
            records[index].note = note
            records[index].expiresAt = expiresAt
        } else {
            guard records.count < 20000 else { return false }
            records.append(BadgeGrant(id: UUID().uuidString, peerId: peerId, role: role, issuedAt: now, issuedBy: accountPeerId, expiresAt: expiresAt, note: note, revokedAt: nil))
        }
        return saveBadgeRecords(records)
    }

    @discardableResult
    public static func revokeBadge(id: String, accountPeerId: Int64, now: Date = Date()) -> Bool {
        guard canManageBadges(accountPeerId: accountPeerId) else { return false }
        var records = localBadgeRecords
        guard let index = records.firstIndex(where: { $0.id == id && $0.revokedAt == nil }) else { return false }
        records[index].revokedAt = now
        return saveBadgeRecords(records)
    }

    private static func saveBadgeRecords(_ records: [BadgeGrant]) -> Bool {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: "faithgram.badgeRecords")
            NotificationCenter.default.post(name: changed, object: nil)
            return true
        }
        return false
    }
}
