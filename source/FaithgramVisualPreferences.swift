import Foundation

public enum FaithgramVisualPreferences {
    public struct Field {
        public let key: String
        public let title: String
        public let fallback: String
        public let choices: [String]
        public init(_ key: String, _ title: String, _ fallback: String = "", choices: [String] = []) {
            self.key = key; self.title = title; self.fallback = fallback; self.choices = choices
        }
    }
    public static let profileFields: [Field] = [
        Field("displayPhone", "Phone number"), Field("displayUserId", "User id"),
        Field("displayUsernames", "Usernames (comma-separated)"),
        Field("collectibleUsernames", "Collectible usernames (comma-separated)"),
        Field("attachedChannelId", "Attached channel id"),
        Field("fragmentPhone", "Collectible phone", "off", choices: ["off", "on"]),
        Field("collectiblePurchaseDate", "Collectible purchase date (Unix)"),
        Field("collectibleCurrency", "Collectible currency", "TON"),
        Field("collectibleAmount", "Collectible purchase amount"),
        Field("collectibleCryptoAmount", "Collectible crypto amount"),
        Field("collectibleUrl", "Collectible URL"),
        Field("visualPeerIds", "Target peer ids (comma-separated)"),
        Field("visualBadge", "Visual badge", "none", choices: ["none", "verified", "scam", "fake"]),
        Field("ratingLevel", "Stars rating level"), Field("ratingCurrent", "Stars rating current"),
        Field("ratingNext", "Stars rating next"), Field("botVerificationIcon", "Bot verification emoji id"),
        Field("botVerificationText", "Bot verification description"),
        Field("botVerificationPreset", "Bot verification preset", "custom", choices: ["custom", "verified", "official"]),
        Field("botVerificationPlacement", "Bot verification placement", "profile", choices: ["profile", "name", "both"]),
        Field("freezeSince", "Account frozen since (Unix)"), Field("freezeUntil", "Account frozen until (Unix)"),
        Field("freezeAppealUrl", "Account freeze appeal URL")
    ]
    public static let balanceFields = [Field("displayStars", "Stars balance"), Field("displayTon", "TON balance (nanoTON)")]
    public static let regularGiftFields: [Field] = [
        Field("giftTarget", "Profiles", "only me", choices: ["only me", "everyone", "except me"]),
        Field("giftSenderId", "Sender id (Bot API format)"), Field("giftDate", "Gift date (Unix)"),
        Field("giftId", "Gift id"), Field("giftPrice", "Stars price", "50"), Field("giftConvertStars", "Convert to Stars", "0"),
        Field("giftCaption", "Caption"), Field("giftAvailable", "Supply available"), Field("giftTotal", "Supply total"),
        Field("giftLimited", "Limited", "off", choices: ["off", "on"]),
        Field("giftUpgradePrice", "Upgrade price"), Field("giftAuctionTitle", "Auction title"),
        Field("giftNumber", "Auction gift number"), Field("giftRefunded", "Refunded", "off", choices: ["off", "on"]),
        Field("giftEmojiId", "Sticker custom emoji id")
    ]
    public static let uniqueGiftFields: [Field] = [
        Field("uniqueTitle", "Title"), Field("uniqueNumber", "Unique number", "1"),
        Field("uniqueSlug", "Gift slug"), Field("uniqueModel", "Model name"), Field("uniqueModelEmojiId", "Model custom emoji id"),
        Field("uniqueModelRarity", "Model rarity (per mille)", "10"),
        Field("uniqueSymbol", "Symbol name"), Field("uniqueSymbolEmojiId", "Symbol custom emoji id"),
        Field("uniqueSymbolRarity", "Symbol rarity (per mille)", "10"),
        Field("uniqueBackdrop", "Backdrop name"), Field("uniqueBackdropId", "Backdrop id", "0"),
        Field("uniqueCenterColor", "Center color (hex)", "222222"), Field("uniqueEdgeColor", "Edge color (hex)", "000000"),
        Field("uniquePatternColor", "Pattern color (hex)", "555555"), Field("uniqueTextColor", "Text color (hex)", "ffffff"),
        Field("uniqueBackdropRarity", "Backdrop rarity (per mille)", "10"),
        Field("uniqueIssued", "Issued count", "1"), Field("uniqueTotal", "Total count", "1"),
        Field("uniqueValue", "Value in Stars"), Field("uniqueLastResale", "Last resale in Stars"),
        Field("uniqueOwnerId", "Owner id (Bot API format)"), Field("uniqueOwnerName", "Owner name"),
        Field("uniqueOwnerAddress", "Owner address"), Field("uniqueHostId", "Host id (Bot API format)"),
        Field("uniqueValueCurrency", "Value currency", "USD"), Field("uniqueValueAmount", "Value amount"),
        Field("uniqueFloorPrice", "Floor price"), Field("uniqueAveragePrice", "Average price")
    ]
    public static let hiddenGiftFields = [Field("hiddenGiftIds", "Extra gift ids (comma-separated)"), Field("hiddenGiftEmojiIds", "Matching custom emoji ids")]
    private static let ownPeersLock = NSRecursiveLock()
    public static var ownPeerIds: Set<Int64> {
        ownPeersLock.lock(); defer { ownPeersLock.unlock() }
        return Set((UserDefaults.standard.array(forKey: "faithgram.ownPeerIds") as? [String] ?? []).compactMap(Int64.init))
    }
    public static func registerOwnPeer(_ peerId: Int64) {
        ownPeersLock.lock(); defer { ownPeersLock.unlock() }
        var ids = ownPeerIds
        if ids.insert(peerId).inserted { UserDefaults.standard.set(ids.sorted().map(String.init), forKey: "faithgram.ownPeerIds") }
    }
    public static func value(_ key: String, fallback: String = "") -> String {
        return FaithgramPreferences.text("visual." + key, fallback: fallback)
    }
    public static func int(_ key: String) -> Int64? { return Int64(value(key)) }
    public static func bool(_ key: String) -> Bool { return value(key) == "on" }
    public static func ids(_ key: String) -> [Int64] {
        return value(key).split(separator: ",").compactMap { Int64($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
    public static func targets(_ id: Int64) -> Bool {
        return PatchClientPolicy.isEnabled(.customProfile) && ids("visualPeerIds").contains(id)
    }
    public static func giftTargets(_ peerId: Int64, ownPeerId: Int64) -> Bool {
        switch value("giftTarget", fallback: "only me") {
        case "everyone": return true
        case "except me": return peerId != ownPeerId
        default: return peerId == ownPeerId
        }
    }
    public static func validate(_ field: Field, text: String) throws {
        struct Invalid: LocalizedError { var errorDescription: String? { return "Enter a valid value for this field." } }
        guard text.utf8.count <= 8192 else { throw Invalid() }
        if text.isEmpty { return }
        if !field.choices.isEmpty { guard field.choices.contains(text) else { throw Invalid() }; return }
        let numeric = ["displayUserId", "attachedChannelId", "collectiblePurchaseDate", "collectibleAmount", "collectibleCryptoAmount", "displayStars", "displayTon", "ratingLevel", "ratingCurrent", "ratingNext", "botVerificationIcon", "freezeSince", "freezeUntil", "giftSenderId", "giftDate", "giftId", "giftPrice", "giftConvertStars", "giftAvailable", "giftTotal", "giftUpgradePrice", "giftNumber", "giftEmojiId", "uniqueNumber", "uniqueModelEmojiId", "uniqueSymbolEmojiId", "uniqueBackdropId", "uniqueModelRarity", "uniqueSymbolRarity", "uniqueBackdropRarity", "uniqueIssued", "uniqueTotal", "uniqueValue", "uniqueLastResale", "uniqueOwnerId", "uniqueHostId", "uniqueValueAmount", "uniqueFloorPrice", "uniqueAveragePrice"]
        if numeric.contains(field.key) {
            guard let number = Int64(text) else { throw Invalid() }
            if !["giftSenderId", "uniqueOwnerId", "uniqueHostId"].contains(field.key), number < 0 { throw Invalid() }
            if ["giftDate", "collectiblePurchaseDate", "freezeSince", "freezeUntil", "uniqueNumber", "uniqueBackdropId", "giftAvailable", "giftTotal", "giftNumber", "ratingLevel", "uniqueIssued", "uniqueTotal"].contains(field.key), number > Int64(Int32.max) { throw Invalid() }
            if field.key.hasSuffix("Rarity"), number > 1000 { throw Invalid() }
        }
        if ["visualPeerIds", "hiddenGiftIds", "hiddenGiftEmojiIds"].contains(field.key) {
            let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count <= 200, parts.allSatisfy({ Int64($0.trimmingCharacters(in: .whitespacesAndNewlines)) != nil }) else { throw Invalid() }
        }
        if field.key.hasSuffix("Color"), UInt32(text, radix: 16) == nil || text.count != 6 { throw Invalid() }
        if field.key.hasSuffix("Url"), !(URL(string: text)?.scheme == "https") { throw Invalid() }
        if field.key.lowercased().contains("usernames") {
            let expression = try NSRegularExpression(pattern: "^@?[A-Za-z0-9_]{1,32}$")
            guard text.split(separator: ",").allSatisfy({ part in
                let item = part.trimmingCharacters(in: .whitespacesAndNewlines)
                return expression.firstMatch(in: item, range: NSRange(item.startIndex..., in: item)) != nil
            }) else { throw Invalid() }
        }
    }
    public static func save(_ field: Field, text: String) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        try validate(field, text: text)
        FaithgramPreferences.setText("visual." + field.key, text)
    }
    public static func displayedBalance(_ actual: Int64, ton: Bool) -> Int64 {
        guard PatchClientPolicy.isEnabled(.customBalances), let local = int(ton ? "displayTon" : "displayStars"), local >= 0 else { return actual }
        return local
    }
}
