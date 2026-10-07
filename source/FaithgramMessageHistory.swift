import Foundation
import Postbox

public final class FaithgramDeletedMessageAttribute: MessageAttribute {
    public let date: Int32
    public init(date: Int32) { self.date = date }
    public required init(decoder: PostboxDecoder) { self.date = decoder.decodeInt32ForKey("d", orElse: 0) }
    public func encode(_ encoder: PostboxEncoder) { encoder.encodeInt32(date, forKey: "d") }
}

public enum FaithgramMessageHistory {
    public static func store(mediaBox: MediaBox, accountPeerId: PeerId) throws -> FaithgramHistoryStore {
        let directory = URL(fileURLWithPath: mediaBox.basePath).deletingLastPathComponent().appendingPathComponent("faithgram-history", isDirectory: true)
        return try FaithgramHistoryStore(directory: directory, encryptionKey: FaithgramVault.accountKey(String(accountPeerId.toInt64())))
    }
    private static func revision(_ message: Message) -> FaithgramHistoryRevision {
        let media = PostboxEncoder()
        media.encodeGenericObjectArray(message.media, forKey: "media")
        let attributes = PostboxEncoder()
        attributes.encodeGenericObjectArray(message.attributes.filter { $0 is TextEntitiesMessageAttribute || $0 is RichTextMessageAttribute }, forKey: "attributes")
        return FaithgramHistoryRevision(text: message.text, messageDate: message.timestamp, authorId: message.author?.id.toInt64(), media: media.makeData(), attributes: attributes.makeData())
    }
    static func capture(_ message: Message, mediaBox: MediaBox, accountPeerId: PeerId, deleted: Bool) {
        guard message.id.namespace == Namespaces.Message.Cloud, message.id.peerId.namespace != Namespaces.Peer.SecretChat else { return }
        FaithgramArchivedMedia.capture(message, mediaBox: mediaBox)
        do {
            try store(mediaBox: mediaBox, accountPeerId: accountPeerId).capture(peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, messageId: message.id.id, revision: revision(message), deleted: deleted)
        } catch {
            FaithgramPreferences.setText("historyError", "Message history could not be saved. Check available storage and device access.")
        }
    }
    static func recordEdit(previous: Message, updated: StoreMessage, mediaBox: MediaBox, accountPeerId: PeerId) {
        guard PatchClientPolicy.isEnabled(.saveEditHistory), previous.id.namespace == Namespaces.Message.Cloud else { return }
        let previousEntities = previous.textEntitiesAttribute?.entities ?? []
        let updatedEntities = (updated.attributes.first { $0 is TextEntitiesMessageAttribute } as? TextEntitiesMessageAttribute)?.entities ?? []
        let previousRich = PostboxEncoder()
        previousRich.encodeGenericObjectArray(previous.attributes.filter { $0 is RichTextMessageAttribute }, forKey: "rich")
        let updatedRich = PostboxEncoder()
        updatedRich.encodeGenericObjectArray(updated.attributes.filter { $0 is RichTextMessageAttribute }, forKey: "rich")
        let richChanged = previousRich.makeData() != updatedRich.makeData()
        guard previous.text != updated.text || previousEntities != updatedEntities || previous.media.map({ $0.id }) != updated.media.map({ $0.id }) || richChanged else { return }
        capture(previous, mediaBox: mediaBox, accountPeerId: accountPeerId, deleted: false)
    }
    static func retainDeleted(_ ids: [MessageId], transaction: Transaction, mediaBox: MediaBox, accountPeerId: PeerId) -> [MessageId] {
        guard PatchClientPolicy.isEnabled(.saveDeletedMessages) else { return ids }
        return ids.filter { id in
            guard id.namespace == Namespaces.Message.Cloud, id.peerId.namespace != Namespaces.Peer.SecretChat, let message = transaction.getMessage(id) else { return true }
            capture(message, mediaBox: mediaBox, accountPeerId: accountPeerId, deleted: true)
            transaction.updateMessage(id) { message in
                var attributes = message.attributes.filter { !($0 is FaithgramDeletedMessageAttribute) }
                attributes.append(FaithgramDeletedMessageAttribute(date: Int32(clamping: Int(Date().timeIntervalSince1970))))
                var flags = StoreMessageFlags(message.flags)
                flags.remove(.CountedAsIncoming)
                var tags = message.tags
                tags.remove(.unseenPersonalMessage)
                return .update(StoreMessage(id: message.id, customStableId: nil, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: message.timestamp, flags: flags, tags: tags, globalTags: message.globalTags, localTags: message.localTags, forwardInfo: message.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: message.author?.id, text: message.text, attributes: attributes, media: message.media))
            }
            return false
        }
    }
}
