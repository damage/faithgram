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

    public var title: String {
        switch self {
        case .alwaysOffline: return "Stay offline"
        case .blockTyping: return "Hide typing activity"
        case .blockCloudReads: return "Disable cloud read receipts"
        case .localDrafts: return "Keep drafts on this device"
        case .noPhoneException: return "Keep phone privacy when adding contacts"
        case .hideAds: return "Hide channel ads"
        case .hideProxyPromo: return "Hide proxy promotions"
        }
    }

    public var explanation: String {
        switch self {
        case .alwaysOffline:
            return "Sends offline status updates. Sending messages can still reveal activity."
        case .blockTyping:
            return "Suppresses typing, recording and media upload indicators."
        case .blockCloudReads:
            return "Messages may remain unread on other devices. Secret chats use standard read receipts."
        case .localDrafts:
            return "Keeps new drafts on this device. Existing server drafts are not deleted."
        case .noPhoneException:
            return "Adds contacts without granting an exception to your phone number privacy settings."
        case .hideAds:
            return "Skips sponsored messages in channels."
        case .hideProxyPromo:
            return "Skips the proxy operator's promoted channel."
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
        UserDefaults.standard.set(value, forKey: prefix + option.rawValue)
    }

    /// Completion consumes the local operation without inventing server PTS
    /// values or leaving an unresolved request in MTProto's pending queue.
    static func shouldCompleteLocally(_ method: String) -> Bool {
        switch method {
        case "messages.setTyping", "messages.setEncryptedTyping":
            return isEnabled(.blockTyping)
        case "messages.readHistory", "channels.readHistory",
             "messages.readMessageContents", "channels.readMessageContents",
             "messages.readDiscussion", "messages.readMentions",
             "messages.readReactions", "messages.readPollVotes":
            return isEnabled(.blockCloudReads)
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
