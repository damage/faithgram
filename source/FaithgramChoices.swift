import Foundation

/// A setting with a fixed set of values. Values are stored as text under
/// `faithgram.choice.<key>`; multi-value choices join values with commas.
public struct FaithgramChoice: Equatable {
    public struct Option: Equatable {
        public let value: String
        public let title: String
        public init(_ value: String, _ title: String) { self.value = value; self.title = title }
    }
    public let key: String
    public let title: String
    public let options: [Option]
    public let fallback: String
    public let multiple: Bool
    /// Values that cannot be combined with any other value of a multi-value choice.
    public let exclusive: Set<String>
    public let footer: String?

    public init(key: String, title: String, options: [Option], fallback: String, multiple: Bool = false, exclusive: Set<String> = [], footer: String? = nil) {
        self.key = key; self.title = title; self.options = options; self.fallback = fallback
        self.multiple = multiple; self.exclusive = exclusive; self.footer = footer
    }

    public var storageKey: String { return "faithgram.choice." + key }

    public func isValid(_ text: String) -> Bool {
        let parts = text.split(separator: ",").map(String.init)
        guard !parts.isEmpty, Set(parts).count == parts.count, parts.allSatisfy({ part in options.contains { $0.value == part } }) else { return false }
        if !multiple { return parts.count == 1 }
        if parts.count > 1, parts.contains(where: { exclusive.contains($0) }) { return false }
        return true
    }
}

public enum FaithgramChoices {
    public static let coverOptions = [
        FaithgramChoice.Option("disable", "Disable"), FaithgramChoice.Option("full", "Full"),
        FaithgramChoice.Option("spoiler", "Spoiler"), FaithgramChoice.Option("screenSharing", "Screen sharing")
    ]
    private static func cover(_ key: String, _ title: String) -> FaithgramChoice {
        return FaithgramChoice(key: key, title: title, options: coverOptions, fallback: "disable", multiple: true, exclusive: ["disable", "full"])
    }
    public static let selfPhone = cover("profile.self.phone", "Hide Phone")
    public static let selfId = cover("profile.self.id", "Hide Profile ID")
    public static let selfUsernames = cover("profile.self.usernames", "Hide Usernames")
    public static let otherPhone = cover("profile.other.phone", "Hide Phone")
    public static let otherId = cover("profile.other.id", "Hide Profile ID")
    public static let otherUsernames = cover("profile.other.usernames", "Hide Usernames")

    public static let mediaOrigin = FaithgramChoice(key: "mediaOrigin", title: "Media origin", options: [
        .init("off", "Off"), .init("photos", "Photos"), .init("videos", "Videos"), .init("all", "Photos and videos")
    ], fallback: "off", footer: "Show where a photo or video came from: the camera, the gallery or a forward.")
    public static let recordingButton = FaithgramChoice(key: "recordingButton", title: "Recording Button", options: [
        .init("voice", "Voice Recording"), .init("round", "Round Videos")
    ], fallback: "voice,round", multiple: true, footer: "Choose what the record button next to the message field can create.")
    public static let tabsBadge = FaithgramChoice(key: "tabsBadge", title: "Notifications Badge", options: [
        .init("contacts", "Contacts"), .init("calls", "Calls"), .init("chats", "Chats"), .init("settings", "Settings")
    ], fallback: "chats,settings", multiple: true, footer: "Tabs that show an unread badge.")
    public static let recordingMicrophone = FaithgramChoice(key: "recordingMicrophone", title: "Recording microphone", options: [
        .init("automatic", "Automatic"), .init("builtIn", "Built-in"), .init("bluetooth", "Bluetooth"), .init("wired", "Wired headset")
    ], fallback: "automatic")
    public static let downloadType = FaithgramChoice(key: "downloadType", title: "Download type", options: [
        .init("video", "Download video"), .init("audio", "Download audio"), .init("both", "Video and audio")
    ], fallback: "video")
    public static let downloadBoost = FaithgramChoice(key: "downloadBoost", title: "Download Boost", options: [
        .init("disabled", "Disabled"), .init("x2", "2 connections"), .init("x4", "4 connections"), .init("x8", "8 connections")
    ], fallback: "disabled", footer: "Download large files over several connections at once. Telegram may limit the speed on its side.")
    public static let translateService = FaithgramChoice(key: "translateService", title: "Service", options: [
        .init("telegram", "Telegram"), .init("device", "On-device (Apple)")
    ], fallback: "telegram", footer: "On-device translation uses installed Apple language models and never sends text to Telegram.")
    public static let voiceService = FaithgramChoice(key: "voiceService", title: "Service", options: [
        .init("telegram", "Telegram"), .init("device", "On-device (Apple)")
    ], fallback: "telegram", footer: "On-device transcription uses Apple speech recognition when the language is supported.")
    public static let rankColorOptions = [
        FaithgramChoice.Option("default", "Default"), FaithgramChoice.Option("red", "Red"), FaithgramChoice.Option("orange", "Orange"),
        FaithgramChoice.Option("yellow", "Yellow"), FaithgramChoice.Option("green", "Green"), FaithgramChoice.Option("cyan", "Cyan"),
        FaithgramChoice.Option("blue", "Blue"), FaithgramChoice.Option("purple", "Purple"), FaithgramChoice.Option("pink", "Pink")
    ]
    public static let rankOwner = FaithgramChoice(key: "rankColor.owner", title: "Owner", options: rankColorOptions, fallback: "default")
    public static let rankAdmin = FaithgramChoice(key: "rankColor.admin", title: "Admin", options: rankColorOptions, fallback: "default")
    public static let rankMember = FaithgramChoice(key: "rankColor.member", title: "Member", options: rankColorOptions, fallback: "default")

    public static let all: [FaithgramChoice] = [
        selfPhone, selfId, selfUsernames, otherPhone, otherId, otherUsernames,
        mediaOrigin, recordingButton, tabsBadge, recordingMicrophone, downloadType, downloadBoost,
        translateService, voiceService, rankOwner, rankAdmin, rankMember
    ]

    public static func choice(forStorageKey key: String) -> FaithgramChoice? {
        return all.first { $0.storageKey == key }
    }

    public static func value(_ choice: FaithgramChoice) -> String {
        let stored = UserDefaults.standard.string(forKey: choice.storageKey) ?? choice.fallback
        return choice.isValid(stored) ? stored : choice.fallback
    }
    public static func values(_ choice: FaithgramChoice) -> [String] {
        return value(choice).split(separator: ",").map(String.init)
    }
    public static func contains(_ choice: FaithgramChoice, _ option: String) -> Bool {
        return values(choice).contains(option)
    }
    public static func label(_ choice: FaithgramChoice) -> String {
        let selected = values(choice)
        return choice.options.filter { selected.contains($0.value) }.map { $0.title }.joined(separator: ", ")
    }
    @discardableResult
    public static func set(_ choice: FaithgramChoice, _ text: String) -> Bool {
        guard choice.isValid(text) else { return false }
        if UserDefaults.standard.string(forKey: choice.storageKey) == text { return true }
        UserDefaults.standard.set(text, forKey: choice.storageKey)
        NotificationCenter.default.post(name: FaithgramPreferences.changed, object: nil)
        return true
    }
    /// Selects an option. Single-value choices replace the value; multi-value
    /// choices toggle it, honouring exclusive values and never leaving the set empty.
    @discardableResult
    public static func select(_ choice: FaithgramChoice, _ option: String) -> Bool {
        guard choice.options.contains(where: { $0.value == option }) else { return false }
        if !choice.multiple { return set(choice, option) }
        var current = values(choice)
        if choice.exclusive.contains(option) { return set(choice, option) }
        current.removeAll { choice.exclusive.contains($0) }
        if let index = current.firstIndex(of: option) {
            current.remove(at: index)
            if current.isEmpty { current = [choice.fallback.split(separator: ",").map(String.init).first ?? option] }
        } else {
            current.append(option)
        }
        let ordered = choice.options.map { $0.value }.filter { current.contains($0) }
        return set(choice, ordered.joined(separator: ","))
    }
}

/// Which parts of a profile are covered, for the user's own profile and for other people.
public enum FaithgramProfileCover {
    public enum Field { case phone, id, usernames }

    public static func choice(_ field: Field, ownProfile: Bool) -> FaithgramChoice {
        switch (field, ownProfile) {
        case (.phone, true): return FaithgramChoices.selfPhone
        case (.id, true): return FaithgramChoices.selfId
        case (.usernames, true): return FaithgramChoices.selfUsernames
        case (.phone, false): return FaithgramChoices.otherPhone
        case (.id, false): return FaithgramChoices.otherId
        case (.usernames, false): return FaithgramChoices.otherUsernames
        }
    }
    /// The own phone keeps its legacy switch so privacy profiles keep working.
    public static func modes(_ field: Field, ownProfile: Bool) -> Set<String> {
        if field == .phone, ownProfile, PatchClientPolicy.isEnabled(.hideSelfPhone) { return ["full"] }
        return Set(FaithgramChoices.values(choice(field, ownProfile: ownProfile)))
    }
    public static func hidesRow(_ field: Field, ownProfile: Bool) -> Bool { return modes(field, ownProfile: ownProfile).contains("full") }
    public static func spoilers(_ field: Field, ownProfile: Bool) -> Bool { return modes(field, ownProfile: ownProfile).contains("spoiler") }
    public static func hidesFromCapture(_ field: Field, ownProfile: Bool) -> Bool { return modes(field, ownProfile: ownProfile).contains("screenSharing") }
    public static func label(_ field: Field, ownProfile: Bool) -> String {
        let selected = modes(field, ownProfile: ownProfile)
        return FaithgramChoices.coverOptions.filter { selected.contains($0.value) }.map { $0.title }.joined(separator: ", ")
    }
    public static func select(_ field: Field, ownProfile: Bool, option: String) {
        let target = choice(field, ownProfile: ownProfile)
        if field == .phone, ownProfile {
            if option == "full" { FaithgramChoices.set(target, "full"); PatchClientPolicy.setEnabled(.hideSelfPhone, true); return }
            if PatchClientPolicy.isEnabled(.hideSelfPhone) {
                PatchClientPolicy.setEnabled(.hideSelfPhone, false)
                FaithgramChoices.set(target, option == "disable" ? "disable" : option)
                return
            }
        }
        FaithgramChoices.select(target, option)
    }
}

/// Named snapshots of the Faithgram switches that can be swapped in one tap or shared as a link.
public struct FaithgramSettingsProfile: Codable {
    public let id: String
    public var name: String
    public let createdAt: Date
    public let values: [String: FaithgramSettingsBackup.Value]

    public init(id: String = UUID().uuidString, name: String, createdAt: Date = Date(), values: [String: FaithgramSettingsBackup.Value]) {
        self.id = id; self.name = name; self.createdAt = createdAt; self.values = values
    }
}

public enum FaithgramSettingsProfiles {
    public static let storageKey = "faithgram.settingsProfiles"
    public static let linkPrefix = "faithgram://profile?data="
    /// Never part of a saved or shared profile.
    public static let excludedKeys: Set<String> = [
        "patchclient.option.giftActions2FA", "patchclient.option.callConfirmation", "patchclient.option.protocolLogger",
        "faithgram.privacy.ghostChats", "faithgram.privacy.previous"
    ]
    public static let maximumCount = 64

    public static var all: [FaithgramSettingsProfile] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([FaithgramSettingsProfile].self, from: data)) ?? []
    }
    private static func store(_ profiles: [FaithgramSettingsProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: storageKey)
            NotificationCenter.default.post(name: FaithgramPreferences.changed, object: nil)
        }
    }
    public static func sanitizedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 48 else { return nil }
        return trimmed
    }
    @discardableResult
    public static func saveCurrent(name: String, defaults: UserDefaults = .standard) -> FaithgramSettingsProfile? {
        guard let name = sanitizedName(name) else { return nil }
        var profiles = all
        guard profiles.count < maximumCount else { return nil }
        let values = FaithgramSettingsBackup.capture(defaults: defaults).values.filter { !excludedKeys.contains($0.key) }
        let profile = FaithgramSettingsProfile(name: name, values: values)
        profiles.append(profile)
        store(profiles)
        return profile
    }
    public static func apply(id: String, defaults: UserDefaults = .standard) throws {
        guard let profile = all.first(where: { $0.id == id }) else { throw FaithgramVaultError.invalidFile }
        try apply(profile, defaults: defaults)
    }
    public static func apply(_ profile: FaithgramSettingsProfile, defaults: UserDefaults = .standard) throws {
        let backup = FaithgramSettingsBackup(version: 1, createdAt: profile.createdAt, values: profile.values.filter { !excludedKeys.contains($0.key) })
        try backup.validate()
        // Keep the keys a profile never carries exactly as they are now.
        let preserved = Dictionary(uniqueKeysWithValues: excludedKeys.compactMap { key -> (String, Any)? in defaults.object(forKey: key).map { (key, $0) } })
        try backup.apply(defaults: defaults)
        for (key, value) in preserved { defaults.set(value, forKey: key) }
        NotificationCenter.default.post(name: FaithgramPreferences.changed, object: nil)
    }
    public static func delete(id: String) { store(all.filter { $0.id != id }) }
    public static func rename(id: String, name: String) {
        guard let name = sanitizedName(name) else { return }
        store(all.map { profile in var copy = profile; if copy.id == id { copy.name = name }; return copy })
    }
    public static func importProfile(_ profile: FaithgramSettingsProfile) -> Bool {
        var profiles = all
        guard profiles.count < maximumCount, profiles.first(where: { $0.id == profile.id }) == nil else { return false }
        profiles.append(profile)
        store(profiles)
        return true
    }

    private struct SharedProfile: Codable { let name: String; let values: [String: FaithgramSettingsBackup.Value] }
    public static func link(for profile: FaithgramSettingsProfile) -> String? {
        guard let data = try? JSONEncoder().encode(SharedProfile(name: profile.name, values: profile.values.filter { !excludedKeys.contains($0.key) })) else { return nil }
        let encoded = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return linkPrefix + encoded
    }
    public static func profile(fromLink text: String) throws -> FaithgramSettingsProfile {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(linkPrefix), trimmed.count <= 256 * 1024 else { throw FaithgramVaultError.invalidFile }
        var encoded = String(trimmed.dropFirst(linkPrefix.count)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 { encoded += "=" }
        guard let data = Data(base64Encoded: encoded), let shared = try? JSONDecoder().decode(SharedProfile.self, from: data), let name = sanitizedName(shared.name) else { throw FaithgramVaultError.invalidFile }
        let values = shared.values.filter { !excludedKeys.contains($0.key) }
        try FaithgramSettingsBackup(version: 1, createdAt: Date(), values: values).validate()
        return FaithgramSettingsProfile(name: name, values: values)
    }
}
