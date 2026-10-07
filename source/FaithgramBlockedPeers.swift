import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi

public enum FaithgramBlockedPeers {
    private static let lock = NSLock()
    private static var cache: [Int64: Set<Int64>] = [:]
    public static func contains(accountId: Int64, peerId: Int64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if cache[accountId] == nil { cache[accountId] = Set((UserDefaults.standard.array(forKey: "faithgram.blocked.\(accountId)") as? [String] ?? []).compactMap(Int64.init)) }
        return cache[accountId]?.contains(peerId) == true
    }
    static func replace(accountId: Int64, peers: Set<Int64>) {
        lock.lock()
        let changed = cache[accountId] != peers
        cache[accountId] = peers
        UserDefaults.standard.set(peers.sorted().map(String.init), forKey: "faithgram.blocked.\(accountId)")
        lock.unlock()
        if changed { NotificationCenter.default.post(name: FaithgramPreferences.changed, object: nil) }
    }
    static func set(accountId: Int64, peerId: Int64, blocked: Bool) {
        let _ = contains(accountId: accountId, peerId: peerId)
        lock.lock()
        var peers = cache[accountId] ?? []
        if blocked { peers.insert(peerId) } else { peers.remove(peerId) }
        let changed = cache[accountId] != peers
        cache[accountId] = peers
        UserDefaults.standard.set(peers.sorted().map(String.init), forKey: "faithgram.blocked.\(accountId)")
        lock.unlock()
        if changed { NotificationCenter.default.post(name: FaithgramPreferences.changed, object: nil) }
    }
}

func managedFaithgramBlockedPeers(accountPeerId: PeerId, network: Network) -> Signal<Void, NoError> {
    func fetch(offset: Int32, accumulated: Set<Int64>) -> Signal<Set<Int64>, NoError> {
        return network.request(Api.functions.contacts.getBlocked(flags: 0, offset: offset, limit: 200))
        |> map(Optional.init)
        |> `catch` { _ in .single(nil) }
        |> mapToSignal { result -> Signal<Set<Int64>, NoError> in
            guard let result else { return .complete() }
            let entries: [Api.PeerBlocked]
            let total: Int32?
            switch result {
            case let .blocked(data): entries = data.blocked; total = nil
            case let .blockedSlice(data): entries = data.blocked; total = data.count
            }
            var peers = accumulated
            for entry in entries {
                if case let .peerBlocked(data) = entry { peers.insert(data.peerId.peerId.toInt64()) }
            }
            let next = offset + Int32(entries.count)
            if let total, next < total, !entries.isEmpty { return fetch(offset: next, accumulated: peers) }
            return .single(peers)
        }
    }
    let enabled = Signal<Bool, NoError> { subscriber in
        subscriber.putNext(PatchClientPolicy.isEnabled(.hideBlockedMessages))
        let observer = NotificationCenter.default.addObserver(forName: FaithgramPreferences.changed, object: nil, queue: nil) { _ in
            subscriber.putNext(PatchClientPolicy.isEnabled(.hideBlockedMessages))
        }
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    }
    return enabled
    |> distinctUntilChanged
    |> map { enabled -> Signal<Void, NoError> in
        guard enabled else { return .complete() }
        return (fetch(offset: 0, accumulated: [])
        |> map { ids -> Void in FaithgramBlockedPeers.replace(accountId: accountPeerId.toInt64(), peers: ids) }
        |> then(.complete() |> suspendAwareDelay(300, queue: Queue.concurrentDefaultQueue())))
        |> restart
    }
    |> switchToLatest
}
