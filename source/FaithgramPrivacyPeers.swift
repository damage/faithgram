import Postbox

public extension FaithgramPrivacySettings {
    static func suppressesRead(peerId: PeerId) -> Bool { return suppressesRead(namespace: peerId.namespace._internalGetInt32Value(), id: peerId.id._internalGetInt64Value()) }
    static func isGhostChat(peerId: PeerId) -> Bool { return isGhostChat(namespace: peerId.namespace._internalGetInt32Value(), id: peerId.id._internalGetInt64Value()) }
    static func setGhostChat(peerId: PeerId, enabled: Bool) { setGhostChat(namespace: peerId.namespace._internalGetInt32Value(), id: peerId.id._internalGetInt64Value(), enabled: enabled) }
}
