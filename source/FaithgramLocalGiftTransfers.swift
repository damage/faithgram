import Foundation
import Postbox
import SwiftSignalKit

enum FaithgramLocalGiftTransfers {
    private static let lock = NSLock()
    private static var cleanedAccounts: Set<Int64> = []
    private static var gifts: [String: StarGift] = [:]
    private static func key(_ accountId: PeerId, _ reference: StarGiftReference) -> String {
        return "\(accountId.toInt64()):\(String(describing: reference))"
    }
    static func register(accountId: PeerId, gifts: [ProfileGiftsContext.State.StarGift]) {
        lock.lock(); defer { lock.unlock() }
        for item in gifts {
            if let reference = item.reference { Self.gifts[key(accountId, reference)] = item.gift }
        }
    }
    static func cleanup(accountPeerId: PeerId, postbox: Postbox) -> Signal<Void, NoError> {
        return postbox.transaction { transaction in
            lock.lock(); defer { lock.unlock() }
            guard cleanedAccounts.insert(accountPeerId.toInt64()).inserted else { return }
            let storageKey = "faithgram.localGiftTransfers.\(accountPeerId.toInt64())"
            let stored = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
            let ids = stored.compactMap { value -> MessageId? in
                let parts = value.split(separator: ":")
                guard parts.count == 2, let peer = Int64(parts[0]), let id = Int32(parts[1]) else { return nil }
                return MessageId(peerId: PeerId(peer), namespace: Namespaces.Message.EphemeralLocal, id: id)
            }
            transaction.deleteMessages(ids, forEachMedia: nil)
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }
    static func transfer(account: Account, reference: StarGiftReference, peerId: PeerId) -> Signal<Never, TransferStarGiftError> {
        return cleanup(accountPeerId: account.peerId, postbox: account.postbox)
        |> mapToSignal { _ -> Signal<Bool, NoError> in
            return account.postbox.transaction { transaction -> Bool in
                lock.lock(); var gift = gifts[key(account.peerId, reference)]; lock.unlock()
                if gift == nil, case let .message(messageId) = reference, let message = transaction.getMessage(messageId) {
                    for media in message.media {
                        if let action = media as? TelegramMediaAction, case let .starGiftUnique(value, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _) = action.action { gift = value; break }
                    }
                }
                guard let gift, transaction.getPeer(peerId) != nil else { return false }
                let action = TelegramMediaAction(action: .starGiftUnique(gift: gift, isUpgrade: false, isTransferred: true, savedToProfile: false, canExportDate: nil, transferStars: nil, isRefunded: false, isPrepaidUpgrade: false, peerId: peerId, senderId: account.peerId, savedId: nil, resaleAmount: nil, canTransferDate: nil, canResaleDate: nil, dropOriginalDetailsStars: nil, assigned: false, fromOffer: false, canCraftAt: nil, isCrafted: false))
                let id = generateEphemeralLocalMessageId(peerId: peerId, transaction: transaction)
                let storageKey = "faithgram.localGiftTransfers.\(account.peerId.toInt64())"
                var stored = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
                stored.append("\(peerId.toInt64()):\(id.id)")
                // Keep only identifiers so an interrupted process can remove its local previews.
                UserDefaults.standard.set(stored, forKey: storageKey)
                let message = StoreMessage(id: id, customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil, timestamp: Int32(clamping: Int64(Date().timeIntervalSince1970)), flags: [], tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: account.peerId, text: "", attributes: [], media: [action])
                let _ = transaction.addMessages([message], location: .Random)
                return true
                }
        }
        |> castError(TransferStarGiftError.self)
        |> mapToSignal { success -> Signal<Never, TransferStarGiftError> in
            return success ? .complete() : .fail(.generic)
        }
    }
}
