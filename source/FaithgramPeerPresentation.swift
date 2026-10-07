import Foundation
import Postbox

public enum FaithgramPeerPresentation {
    public static func verification(_ original: PeerVerification?, peerId: PeerId) -> PeerVerification? {
        guard FaithgramVisualPreferences.targets(peerId.id._internalGetInt64Value()), ["profile", "both"].contains(FaithgramVisualPreferences.value("botVerificationPlacement", fallback: "profile")) else { return original }
        let preset = FaithgramVisualPreferences.value("botVerificationPreset")
        var text = FaithgramVisualPreferences.value("botVerificationText")
        if text.isEmpty {
            switch preset { case "verified": text = "Verified locally"; case "official": text = "Official account"; default: return original }
        }
        return PeerVerification(botId: peerId, iconFileId: FaithgramVisualPreferences.int("botVerificationIcon") ?? FaithgramPreferences.Badge.verified.fileId ?? 0, description: text)
    }

    public static func collectible(_ subject: TelegramCollectibleItemInfo.Subject) -> TelegramCollectibleItemInfo? {
        guard PatchClientPolicy.isEnabled(.customProfile) else { return nil }
        switch subject {
        case let .phoneNumber(phone):
            guard FaithgramVisualPreferences.bool("fragmentPhone"), phone == FaithgramVisualPreferences.value("displayPhone") else { return nil }
        case let .username(username):
            let names = FaithgramVisualPreferences.value("collectibleUsernames").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "") }
            guard names.contains(username) else { return nil }
        }
        let purchaseDate = Int32(clamping: FaithgramVisualPreferences.int("collectiblePurchaseDate") ?? 0)
        let currency = FaithgramVisualPreferences.value("collectibleCurrency", fallback: "TON")
        let link = FaithgramVisualPreferences.value("collectibleUrl")
        return TelegramCollectibleItemInfo(subject: subject, purchaseDate: purchaseDate, currency: currency, currencyAmount: FaithgramVisualPreferences.int("collectibleAmount") ?? 0, cryptoCurrency: "TON", cryptoCurrencyAmount: FaithgramVisualPreferences.int("collectibleCryptoAmount") ?? 0, url: link.isEmpty ? "https://fragment.com" : link)
    }
}
