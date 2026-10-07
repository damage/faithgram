import Foundation
import TelegramApi

public enum PatchClientOption: String, CaseIterable {
    case alwaysOffline
    case blockTyping
    case blockCloudReads
    case localDrafts
    case noPhoneException
    case hideAds
    case hideProxyPromo
    case lowercaseInterface
    case unlimitedAccounts
    case hideStories
    case disableStoryCamera
    case hidePinnedNotifications
    case hideMentionNotifications
    case localTranscription
    case saveDeletedMessages
    case saveEditHistory
    case localPremium
    case rememberFolder
    case hideAllChats
    case foldersAtBottom
    case regexFilters
    case formattingPanel
    case localTranslation
    case dynamicIsland
    case archiveDownloadedMedia
    case hideSelfPhone
    case customProfile
    case customBalances
    case customFactCheck
    case copyProtectedContent
    case disableTTL
    case showCallbackData
    case disableSensitiveBlur
    case moreRecentStickers
    case openLinksWithoutWarning
    case disableMediaSpoilers
    case hideBlockedMessages
    case disablePremiumEffects
    case disableMonetizationConfig
    case hidePremiumUI
    case hideGifts
    case disablePaidReactions
    case hideEmojiStatus
    case hideCurrencies
    case hideBoosts
    case spoofGifts
    case spoofUniqueGifts
    case fakeGiftTransfer
    case showHiddenGifts
    case protocolLogger

    public var title: String {
        switch self {
        case .alwaysOffline: return "Stay offline"
        case .blockTyping: return "Hide typing activity"
        case .blockCloudReads: return "Disable read receipts"
        case .localDrafts: return "Keep drafts on this device"
        case .noPhoneException: return "Keep phone privacy when adding contacts"
        case .hideAds: return "Hide channel ads"
        case .hideProxyPromo: return "Hide proxy promotions"
        case .lowercaseInterface: return "Lowercase interface"
        case .unlimitedAccounts: return "Unlimited accounts"
        case .hideStories: return "Hide stories"
        case .disableStoryCamera: return "Disable swipe to record"
        case .hidePinnedNotifications: return "Silence pinned messages"
        case .hideMentionNotifications: return "Silence mentions"
        case .localTranscription: return "On-device voice to text"
        case .saveDeletedMessages: return "Save deleted messages"
        case .saveEditHistory: return "Save edit history"
        case .localPremium: return "Local premium appearance"
        case .rememberFolder: return "Remember the last folder"
        case .hideAllChats: return "Hide All Chats"
        case .foldersAtBottom: return "Folders at the bottom"
        case .regexFilters: return "Message filters"
        case .formattingPanel: return "Formatting panel"
        case .archiveDownloadedMedia: return "Archive downloaded media"
        case .dynamicIsland: return "Faithgram Live Activity"
        case .localTranslation: return "On-device translation"
        case .hideSelfPhone: return "Hide my phone"
        case .customProfile: return "Custom profile display"
        case .customBalances: return "Custom balances"
        case .customFactCheck: return "Custom fact check"
        case .copyProtectedContent: return "Copy and save protected content"
        case .disableTTL: return "Disable local expiry"
        case .showCallbackData: return "Show bot callback data"
        case .disableSensitiveBlur: return "Disable sensitive-content blur"
        case .moreRecentStickers: return "200 recent stickers"
        case .openLinksWithoutWarning: return "Open links without confirmation"
        case .disableMediaSpoilers: return "Disable media spoilers"
        case .hideBlockedMessages: return "Hide blocked users' messages"
        case .disablePremiumEffects: return "Disable premium effects"
        case .disableMonetizationConfig: return "Disable monetization config"
        case .hidePremiumUI: return "Hide premium entry points"
        case .hideGifts: return "Hide gifts"
        case .disablePaidReactions: return "Disable paid reactions"
        case .hideEmojiStatus: return "Hide emoji status and effects"
        case .hideCurrencies: return "Hide Stars, TON and collectibles"
        case .hideBoosts: return "Hide boosts"
        case .spoofGifts: return "Custom profile gifts"
        case .spoofUniqueGifts: return "Custom unique gifts"
        case .fakeGiftTransfer: return "Local gift transfers"
        case .showHiddenGifts: return "Extra gifts in catalog"
        case .protocolLogger: return "Decoded MTProto log"

        }
    }

    public var explanation: String {
        switch self {
        case .hideSelfPhone: return "Hide the phone row in your own profile."
        case .customProfile: return "Apply local profile values from Profile settings."
        case .customBalances: return "Display custom Stars and TON balances. Payments use the actual server balance."
        case .customFactCheck: return "Show your own fact-check text under channel posts."
        case .copyProtectedContent: return "Allow local copying and media saving. Telegram can still reject forwarding."
        case .disableTTL: return "Keep timed messages and media on this device. Server deletions require Save deleted messages."
        case .showCallbackData: return "Show and copy callback data from the long-press menu on a bot button."
        case .disableSensitiveBlur: return "Show sensitive media without the local blur."
        case .moreRecentStickers: return "Keep up to 200 recently used stickers."
        case .openLinksWithoutWarning: return "Skip Telegram link confirmation dialogs."
        case .disableMediaSpoilers: return "Show spoiler photos and videos immediately."
        case .hideBlockedMessages: return "Filter messages by blocked authors; unblock to show them again."
        case .disablePremiumEffects: return "Stop premium sticker animations and message effects."
        case .disableMonetizationConfig: return "Remove monetization keys from the local app configuration."
        case .hidePremiumUI: return "Hide premium offers and purchase entry points."
        case .hideGifts: return "Hide gift panels and block gift requests."
        case .disablePaidReactions: return "Hide and block Stars reactions."
        case .hideEmojiStatus: return "Hide custom emoji statuses and suppress their request paths."
        case .hideCurrencies: return "Hide currency and collectible entry points and block their request paths."
        case .hideBoosts: return "Hide and block channel boost actions."
        case .spoofGifts: return "Apply regular gift display values locally."
        case .spoofUniqueGifts: return "Apply unique gift display values locally."
        case .fakeGiftTransfer: return "Create a local transfer preview. Nothing is sent; previews disappear on restart."
        case .showHiddenGifts: return "Add configured gift ids to the local purchase catalog."
        case .protocolLogger: return "Keep an encrypted request and response log on this device. Includes sensitive message and account data."
        case .alwaysOffline:
            return "Sends offline status updates. Sending messages can still reveal activity."
        case .blockTyping:
            return "Suppresses typing, recording and media upload indicators."
        case .blockCloudReads:
            return "Suppress cloud and secret-chat read receipts. Messages may remain unread on other devices."
        case .localDrafts:
            return "Keeps new drafts on this device. Existing server drafts are not deleted."
        case .noPhoneException:
            return "Adds contacts without granting an exception to your phone number privacy settings."
        case .hideAds:
            return "Skips sponsored messages in channels."
        case .hideProxyPromo:
            return "Skips the proxy operator's promoted channel."
        case .lowercaseInterface:
            return "Use lowercase interface labels. Messages and names keep their original case."
        case .unlimitedAccounts:
            return "Remove the local account-count limit. Telegram may still limit sign-in attempts."
        case .hideStories:
            return "Hide the stories strip in the chat list."
        case .disableStoryCamera:
            return "Disable the story camera swipe gesture."
        case .hidePinnedNotifications:
            return "Suppress notifications for pinned-message service events."
        case .hideMentionNotifications:
            return "Suppress notifications for messages that mention you."
        case .localTranscription:
            return "Use speech recognition on this device when the language is supported."
        case .saveDeletedMessages:
            return "Keep a local archive of received cloud messages removed by server updates."
        case .saveEditHistory:
            return "Keep the previous versions of received cloud messages on this device."
        case .localPremium:
            return "Show a premium star for your profile locally. Server subscriptions stay unchanged."
        case .rememberFolder:
            return "Open the last selected chat folder on the next launch."
        case .hideAllChats:
            return "Hide the All Chats tab when other folders are available."
        case .foldersAtBottom:
            return "Place the folder tab bar near the bottom of the chat list."
        case .regexFilters:
            return "Hide matching messages using local regular expressions. Turn the filter off to view them again."
        case .formattingPanel:
            return "Keep bold, italic and link controls close to the message composer."
        case .archiveDownloadedMedia:
            return "Keep downloaded media with deleted messages and past edits, up to 256 MB per file. Per-chat rules are available in the message menu."
        case .dynamicIsland:
            return "Show the app icon in Dynamic Island and on the Lock Screen. iOS controls visibility and duration."
        case .localTranslation:
            return "Translate supported languages on this device using installed language models."
        }
    }
}

/// Options are local to this installation. Session keys, peer IDs and server
/// account data are never replaced by this policy.
public enum PatchClientPolicy {
    private static let prefix = "patchclient.option."

    public static func isEnabled(_ option: PatchClientOption) -> Bool {
        return UserDefaults.standard.bool(forKey: prefix + option.rawValue)
    }

    public static func setEnabled(_ option: PatchClientOption, _ value: Bool) {
        if isEnabled(option) == value { return }
        UserDefaults.standard.set(value, forKey: prefix + option.rawValue)
        NotificationCenter.default.post(name: Notification.Name("faithgram.preferences.changed"), object: nil)
    }

    /// Completion consumes the local operation without inventing server PTS
    /// values or leaving an unresolved request in MTProto's pending queue.
    static func shouldCompleteLocally(_ method: String) -> Bool {
        if isEnabled(.hideStories), method.hasPrefix("stories.") { return true }
        if isEnabled(.hideGifts), method.hasPrefix("payments."), method.lowercased().contains("gift") { return true }
        if isEnabled(.hideBoosts), method.hasPrefix("premium."), method.lowercased().contains("boost") { return true }
        if isEnabled(.disablePaidReactions), method == "messages.sendPaidReaction" || method == "messages.togglePaidReactionPrivacy" { return true }
        if isEnabled(.hideEmojiStatus), method == "account.updateEmojiStatus" || method == "account.getDefaultEmojiStatuses" || method == "account.getRecentEmojiStatuses" || method == "messages.getAvailableEffects" { return true }
        if isEnabled(.hideCurrencies), method.hasPrefix("payments."), (method.lowercased().contains("stars") || method.lowercased().contains("ton")) { return true }
        if isEnabled(.hideCurrencies), method.hasPrefix("fragment.") { return true }
        if isEnabled(.fakeGiftTransfer), method == "payments.transferStarGift" { return true }
        switch method {
        case "messages.setTyping", "messages.setEncryptedTyping":
            return isEnabled(.blockTyping)
        case "messages.readHistory", "channels.readHistory",
             "messages.readMessageContents", "channels.readMessageContents",
             "messages.readDiscussion", "messages.readMentions",
             "messages.readReactions", "messages.readPollVotes", "messages.readEncryptedHistory":
            return isEnabled(.blockCloudReads)
        case "messages.translateText", "messages.translateRichMessage", "messages.composeMessageWithAI", "messages.composeRichMessageWithAI":
            return isEnabled(.localTranslation)
        case "messages.transcribeAudio":
            return isEnabled(.localTranscription)
        case "messages.saveDraft":
            return isEnabled(.localDrafts)
        default:
            return false
        }
    }

    static func payload(for description: FunctionDescription, original: Buffer) -> Data {
        if description.name == "account.updateStatus", isEnabled(.alwaysOffline) {
            return Api.functions.account.updateStatus(offline: .boolTrue).1.makeData()
        }
        var payload = original.makeData()
        if description.name == "contacts.addContact", isEnabled(.noPhoneException), payload.count >= 8 {
            // TL layout: constructor (4 bytes), flags (4 bytes, little endian).
            // add_phone_privacy_exception occupies bit 0 of those flags.
            payload[4] &= 0xfe
        }
        return payload
    }

    static func localResponse(for method: String) -> Any? {
        if method == "help.getAppConfig", isEnabled(.disableMonetizationConfig) { return Api.help.AppConfig.appConfigNotModified }
        if method == "messages.getSponsoredMessages", isEnabled(.hideAds) {
            return Api.messages.SponsoredMessages.sponsoredMessagesEmpty
        }
        if method == "help.getPromoData", isEnabled(.hideProxyPromo) {
            let expires = Int32(clamping: Int(Date().timeIntervalSince1970) + 3600)
            return Api.help.PromoData.promoDataEmpty(.init(expires: expires))
        }
        return nil
    }
}
