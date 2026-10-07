import Foundation
import TelegramApi

public enum FaithgramPrivacySettings {
    public static let options: [PatchClientOption] = [.alwaysOffline, .blockCloudReads, .blockTyping, .localDrafts, .hideSelfPhone, .hideAds, .hideProxyPromo, .hidePinnedNotifications, .hideMentionNotifications, .cleanLinks, .hideAppPreview]
    public static let profiles = ["standard", "quiet", "ghost", "custom"]
    private static let defaults = UserDefaults.standard

    private static func values(_ profile: String) -> [String: Bool]? {
        if profile == "custom", let data = defaults.data(forKey: "faithgram.privacy.custom") { return try? JSONDecoder().decode([String: Bool].self, from: data) }
        guard profiles.prefix(3).contains(profile) else { return nil }
        let quiet: Set<PatchClientOption> = [.hideSelfPhone, .hideAds, .hideProxyPromo, .hidePinnedNotifications, .hideMentionNotifications, .cleanLinks, .hideAppPreview]
        return Dictionary(uniqueKeysWithValues: options.map { option in
            (option.rawValue, profile == "ghost" || (profile == "quiet" && quiet.contains(option)))
        })
    }
    public static var currentProfile: String {
        for name in profiles {
            if let values = values(name), options.allSatisfy({ values[$0.rawValue] == PatchClientPolicy.isEnabled($0) }) { return name }
        }
        return "modified"
    }
    public static func saveCustomProfile() {
        let value = Dictionary(uniqueKeysWithValues: options.map { ($0.rawValue, PatchClientPolicy.isEnabled($0)) })
        defaults.set(try? JSONEncoder().encode(value), forKey: "faithgram.privacy.custom")
        NotificationCenter.default.post(name: FaithgramPreferences.changed, object: nil)
    }
    @discardableResult public static func applyProfile(_ name: String) -> Bool {
        guard let value = values(name), Set(value.keys) == Set(options.map { $0.rawValue }) else { return false }
        let previous = Dictionary(uniqueKeysWithValues: options.map { ($0.rawValue, PatchClientPolicy.isEnabled($0)) })
        defaults.set(try? JSONEncoder().encode(previous), forKey: "faithgram.privacy.previous")
        for option in options { PatchClientPolicy.setEnabled(option, value[option.rawValue] == true) }
        return true
    }
    public static func restorePreviousProfile() -> Bool {
        guard let data = defaults.data(forKey: "faithgram.privacy.previous"), let values = try? JSONDecoder().decode([String: Bool].self, from: data), Set(values.keys) == Set(options.map { $0.rawValue }) else { return false }
        for option in options { if let value = values[option.rawValue] { PatchClientPolicy.setEnabled(option, value) } }
        defaults.removeObject(forKey: "faithgram.privacy.previous")
        return true
    }

    public static func peerKey(namespace: Int32, id: Int64) -> String { return "\(namespace):\(id)" }
    public static var ghostChats: Set<String> {
        return Set(defaults.stringArray(forKey: "faithgram.privacy.ghostChats") ?? [])
    }
    public static func isGhostChat(namespace: Int32, id: Int64) -> Bool { return ghostChats.contains(peerKey(namespace: namespace, id: id)) }
    public static func setGhostChat(namespace: Int32, id: Int64, enabled: Bool) {
        guard (0...3).contains(namespace), id > 0 || (namespace == 3 && id != 0 && Int32(exactly: id) != nil) else { return }
        var values = ghostChats
        let key = peerKey(namespace: namespace, id: id)
        if enabled { values.insert(key) } else { values.remove(key) }
        defaults.set(values.sorted(), forKey: "faithgram.privacy.ghostChats")
        NotificationCenter.default.post(name: FaithgramPreferences.changed, object: nil)
    }
    public static func suppressesRead(namespace: Int32, id: Int64) -> Bool {
        return PatchClientPolicy.isEnabled(.blockCloudReads) || isGhostChat(namespace: namespace, id: id)
    }
    static func suppresses(_ description: FunctionDescription) -> Bool {
        let methods: Set<String> = ["messages.setTyping", "messages.setEncryptedTyping", "messages.readHistory", "channels.readHistory", "messages.readMessageContents", "channels.readMessageContents", "messages.readDiscussion", "messages.readMentions", "messages.readReactions", "messages.readPollVotes", "messages.readEncryptedHistory", "stories.readStories", "stories.incrementStoryViews"]
        guard methods.contains(description.name) else { return false }
        for (name, parameter) in description.parameters where name == "peer" || name == "channel" {
            guard let constructor = parameter.value as? TypeConstructorDescription else { continue }
            let (type, fields) = constructor.descriptionFields()
            let namespace: Int32
            let field: String
            if type.contains("User") { namespace = 0; field = "userId" }
            else if type.contains("Channel") { namespace = 2; field = "channelId" }
            else if type.contains("EncryptedChat") { namespace = 3; field = "chatId" }
            else if type.contains("Chat") { namespace = 1; field = "chatId" }
            else { continue }
            if let value = fields.first(where: { $0.0 == field })?.1.value {
                let id = (value as? Int64) ?? (value as? Int32).map(Int64.init)
                if let id, isGhostChat(namespace: namespace, id: id) { return true }
            }
        }
        return false
    }
}
