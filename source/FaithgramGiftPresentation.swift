import Foundation
import Postbox
import SwiftSignalKit

public enum FaithgramGiftPresentation {
    struct Assets {
        var catalog: [StarGift]
        var files: [Int64: TelegramMediaFile]
        var peers: [PeerId: EnginePeer]
    }
    private static var resolvedFiles: [Int64: TelegramMediaFile] = [:]
    private static let lock = NSLock()

    static func changes() -> Signal<Void, NoError> {
        return Signal { subscriber in
            subscriber.putNext(())
            let observer = NotificationCenter.default.addObserver(forName: FaithgramPreferences.changed, object: nil, queue: nil) { _ in subscriber.putNext(()) }
            return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
        }
    }

    static func peerId(_ value: Int64) -> PeerId {
        if value <= -1000000000000 {
            return PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(-(value + 1000000000000)))
        } else if value < 0 {
            return PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id._internalFromInt64Value(-value))
        }
        return PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(value))
    }

    static func assets(account: Account) -> Signal<Assets, NoError> {
        let settings = changes() |> map { _ -> String in
            let keys = ["giftEmojiId", "uniqueModelEmojiId", "uniqueSymbolEmojiId", "hiddenGiftEmojiIds", "giftSenderId"]
            return keys.map { FaithgramVisualPreferences.value($0) }.joined(separator: "|") + [PatchClientOption.spoofGifts, .spoofUniqueGifts, .showHiddenGifts].map { PatchClientPolicy.isEnabled($0) ? "1" : "0" }.joined()
        } |> distinctUntilChanged
        return settings |> mapToSignal { _ -> Signal<Assets, NoError> in
            let active = PatchClientPolicy.isEnabled(.spoofGifts) || PatchClientPolicy.isEnabled(.spoofUniqueGifts) || PatchClientPolicy.isEnabled(.showHiddenGifts)
            guard active else { return .single(Assets(catalog: [], files: [:], peers: [:])) }
            let ids = Set(["giftEmojiId", "uniqueModelEmojiId", "uniqueSymbolEmojiId"].compactMap { FaithgramVisualPreferences.int($0) } + FaithgramVisualPreferences.ids("hiddenGiftEmojiIds"))
            let peers = account.postbox.transaction { transaction -> [PeerId: EnginePeer] in
                guard let raw = FaithgramVisualPreferences.int("giftSenderId") else { return [:] }
                let id = peerId(raw)
                if let peer = transaction.getPeer(id) { return [id: EnginePeer(peer)] }
                if id.namespace == Namespaces.Peer.CloudUser {
                    let placeholder = TelegramUser(id: id, accessHash: nil, firstName: String(raw), lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
                    return [id: EnginePeer(placeholder)]
                }
                return [:]
            }
            return combineLatest(_internal_cachedStarGifts(postbox: account.postbox), _internal_resolveInlineStickers(postbox: account.postbox, network: account.network, fileIds: Array(ids)), peers)
            |> map { list, files, peers -> Assets in
                lock.lock(); resolvedFiles.merge(files, uniquingKeysWith: { _, new in new }); lock.unlock()
                return Assets(catalog: list?.items ?? [], files: files, peers: peers)
            }
        }
    }

    private static func number(_ key: String, _ original: Int64) -> Int64 { FaithgramVisualPreferences.int(key) ?? original }
    private static func small(_ key: String, _ original: Int32) -> Int32 { Int32(clamping: number(key, Int64(original))) }
    private static func text(_ key: String, _ original: String) -> String {
        let value = FaithgramVisualPreferences.value(key)
        return value.isEmpty ? original : value
    }
    private static func color(_ key: String, _ original: Int32) -> Int32 {
        guard let value = UInt32(FaithgramVisualPreferences.value(key), radix: 16) else { return original }
        return Int32(bitPattern: value)
    }
    private static func file(_ key: String, _ original: TelegramMediaFile, _ files: [Int64: TelegramMediaFile]) -> TelegramMediaFile {
        return FaithgramVisualPreferences.int(key).flatMap { files[$0] } ?? original
    }

    static func regular(_ gift: StarGift.Gift, files: [Int64: TelegramMediaFile]) -> StarGift.Gift {
        let limited = FaithgramVisualPreferences.bool("giftLimited")
        let supply = (limited || FaithgramVisualPreferences.int("giftTotal") != nil) ? StarGift.Gift.Availability(remains: small("giftAvailable", gift.availability?.remains ?? 1), total: small("giftTotal", gift.availability?.total ?? 1), resale: gift.availability?.resale ?? 0, minResaleStars: gift.availability?.minResaleStars) : gift.availability
        var flags = gift.flags
        let auctionTitle = FaithgramVisualPreferences.value("giftAuctionTitle")
        if !auctionTitle.isEmpty { flags.insert(.isAuction) }
        return StarGift.Gift(id: number("giftId", gift.id), title: auctionTitle.isEmpty ? gift.title : auctionTitle, file: file("giftEmojiId", gift.file, files), price: number("giftPrice", gift.price), convertStars: number("giftConvertStars", gift.convertStars), availability: supply, soldOut: gift.soldOut, flags: flags, upgradeStars: FaithgramVisualPreferences.int("giftUpgradePrice") ?? gift.upgradeStars, releasedBy: gift.releasedBy, perUserLimit: gift.perUserLimit, lockedUntilDate: gift.lockedUntilDate, auctionSlug: gift.auctionSlug, auctionGiftsPerRound: gift.auctionGiftsPerRound, auctionStartDate: gift.auctionStartDate, upgradeVariantsCount: gift.upgradeVariantsCount, background: gift.background)
    }

    static func unique(_ source: StarGift, profilePeerId: PeerId, date: Int32, files: [Int64: TelegramMediaFile]) -> StarGift {
        let original: StarGift.UniqueGift?
        let baseFile: TelegramMediaFile
        let id: Int64
        let giftId: Int64
        let title: String
        switch source {
        case let .generic(gift): original = nil; baseFile = gift.file; id = gift.id; giftId = gift.id; title = gift.title ?? "Gift"
        case let .unique(gift):
            original = gift; id = gift.id; giftId = gift.giftId; title = gift.title
            guard let model = gift.attributes.compactMap({ attribute -> TelegramMediaFile? in if case let .model(_, file, _, _) = attribute { return file }; return nil }).first else { return source }
            baseFile = model
        }
        var attributes: [StarGift.UniqueGift.Attribute] = []
        var hasModel = false, hasPattern = false, hasBackdrop = false, hasInfo = false
        for attribute in original?.attributes ?? [] {
            switch attribute {
            case let .model(name, originalFile, rarity, crafted):
                attributes.append(.model(name: text("uniqueModel", name), file: file("uniqueModelEmojiId", originalFile, files), rarity: FaithgramVisualPreferences.int("uniqueModelRarity").map { StarGift.UniqueGift.Attribute.Rarity.permille(Int32(clamping: $0)) } ?? rarity, crafted: crafted)); hasModel = true
            case let .pattern(name, originalFile, rarity):
                attributes.append(.pattern(name: text("uniqueSymbol", name), file: file("uniqueSymbolEmojiId", originalFile, files), rarity: FaithgramVisualPreferences.int("uniqueSymbolRarity").map { StarGift.UniqueGift.Attribute.Rarity.permille(Int32(clamping: $0)) } ?? rarity)); hasPattern = true
            case let .backdrop(name, backdropId, inner, outer, pattern, foreground, rarity):
                attributes.append(.backdrop(name: text("uniqueBackdrop", name), id: small("uniqueBackdropId", backdropId), innerColor: color("uniqueCenterColor", inner), outerColor: color("uniqueEdgeColor", outer), patternColor: color("uniquePatternColor", pattern), textColor: color("uniqueTextColor", foreground), rarity: FaithgramVisualPreferences.int("uniqueBackdropRarity").map { StarGift.UniqueGift.Attribute.Rarity.permille(Int32(clamping: $0)) } ?? rarity)); hasBackdrop = true
            case let .originalInfo(sender, recipient, originalDate, caption, entities):
                attributes.append(.originalInfo(senderPeerId: FaithgramVisualPreferences.int("giftSenderId").map(peerId) ?? sender, recipientPeerId: recipient, date: small("giftDate", originalDate), text: text("giftCaption", caption ?? ""), entities: entities)); hasInfo = true
            }
        }
        if !hasModel { attributes.append(.model(name: text("uniqueModel", "Original"), file: file("uniqueModelEmojiId", baseFile, files), rarity: .permille(small("uniqueModelRarity", 10)), crafted: false)) }
        if !hasPattern { attributes.append(.pattern(name: text("uniqueSymbol", "Original"), file: file("uniqueSymbolEmojiId", baseFile, files), rarity: .permille(small("uniqueSymbolRarity", 10)))) }
        if !hasBackdrop { attributes.append(.backdrop(name: text("uniqueBackdrop", "Black"), id: small("uniqueBackdropId", 0), innerColor: color("uniqueCenterColor", 0x222222), outerColor: color("uniqueEdgeColor", 0), patternColor: color("uniquePatternColor", 0x555555), textColor: color("uniqueTextColor", 0xffffff), rarity: .permille(small("uniqueBackdropRarity", 10)))) }
        if !hasInfo { attributes.append(.originalInfo(senderPeerId: FaithgramVisualPreferences.int("giftSenderId").map(peerId), recipientPeerId: profilePeerId, date: date, text: text("giftCaption", ""), entities: [])) }
        var owner: StarGift.UniqueGift.Owner? = original?.owner ?? .peerId(profilePeerId)
        if let raw = FaithgramVisualPreferences.int("uniqueOwnerId") { owner = .peerId(peerId(raw)) }
        if !FaithgramVisualPreferences.value("uniqueOwnerName").isEmpty { owner = .name(FaithgramVisualPreferences.value("uniqueOwnerName")) }
        if !FaithgramVisualPreferences.value("uniqueOwnerAddress").isEmpty { owner = .address(FaithgramVisualPreferences.value("uniqueOwnerAddress")) }
        let numberValue = small("uniqueNumber", original?.number ?? 1)
        let resale = FaithgramVisualPreferences.int("uniqueLastResale").map { [CurrencyAmount(amount: StarsAmount(value: $0, nanos: 0), currency: .stars)] } ?? original?.resellAmounts
        return .unique(StarGift.UniqueGift(id: id, giftId: giftId, title: text("uniqueTitle", title), number: numberValue, slug: text("uniqueSlug", original?.slug ?? "Faithgram-\(numberValue)"), owner: owner, attributes: attributes, availability: StarGift.UniqueGift.Availability(issued: small("uniqueIssued", original?.availability.issued ?? 1), total: small("uniqueTotal", original?.availability.total ?? 1)), giftAddress: text("uniqueOwnerAddress", original?.giftAddress ?? ""), resellAmounts: resale, resellForTonOnly: original?.resellForTonOnly ?? false, releasedBy: original?.releasedBy, valueAmount: FaithgramVisualPreferences.int("uniqueValue") ?? original?.valueAmount, valueCurrency: original?.valueCurrency ?? "XTR", valueUsdAmount: original?.valueUsdAmount, flags: original?.flags ?? [], themePeerId: original?.themePeerId, peerColor: original?.peerColor, hostPeerId: FaithgramVisualPreferences.int("uniqueHostId").map(peerId) ?? original?.hostPeerId, minOfferStars: original?.minOfferStars, craftChancePermille: original?.craftChancePermille))
    }

    private static func profileGift(_ item: ProfileGiftsContext.State.StarGift, peerId: PeerId, assets: Assets) -> ProfileGiftsContext.State.StarGift {
        var gift = item.gift
        if PatchClientPolicy.isEnabled(.spoofGifts), case let .generic(original) = gift { gift = .generic(regular(original, files: assets.files)) }
        let date = small("giftDate", item.date)
        if PatchClientPolicy.isEnabled(.spoofUniqueGifts) { gift = unique(gift, profilePeerId: peerId, date: date, files: assets.files) }
        let sender = FaithgramVisualPreferences.int("giftSenderId").flatMap { assets.peers[Self.peerId($0)] } ?? item.fromPeer
        return ProfileGiftsContext.State.StarGift(gift: gift, reference: item.reference, fromPeer: sender, date: date, text: text("giftCaption", item.text ?? ""), entities: FaithgramVisualPreferences.value("giftCaption").isEmpty ? item.entities : [], nameHidden: item.nameHidden, savedToProfile: item.savedToProfile, pinnedToTop: item.pinnedToTop, convertStars: FaithgramVisualPreferences.int("giftConvertStars") ?? item.convertStars, canUpgrade: item.canUpgrade, canExportDate: item.canExportDate, upgradeStars: FaithgramVisualPreferences.int("giftUpgradePrice") ?? item.upgradeStars, transferStars: PatchClientPolicy.isEnabled(.fakeGiftTransfer) ? 0 : item.transferStars, canTransferDate: PatchClientPolicy.isEnabled(.fakeGiftTransfer) ? 0 : item.canTransferDate, canResaleDate: item.canResaleDate, collectionIds: item.collectionIds, prepaidUpgradeHash: item.prepaidUpgradeHash, upgradeSeparate: item.upgradeSeparate, dropOriginalDetailsStars: item.dropOriginalDetailsStars, number: FaithgramVisualPreferences.int("giftNumber").map { Int32(clamping: $0) } ?? item.number, isRefunded: FaithgramVisualPreferences.value("giftRefunded").isEmpty ? item.isRefunded : FaithgramVisualPreferences.bool("giftRefunded"), canCraftAt: item.canCraftAt)
    }

    static func profile(_ original: ProfileGiftsContext.State, peerId: PeerId, ownPeerId: PeerId, assets: Assets) -> ProfileGiftsContext.State {
        if PatchClientPolicy.isEnabled(.hideGifts) { var result = original; result.gifts = []; result.filteredGifts = []; result.count = 0; return result }
        guard FaithgramVisualPreferences.giftTargets(peerId.id._internalGetInt64Value(), ownPeerId: ownPeerId.id._internalGetInt64Value()), PatchClientPolicy.isEnabled(.spoofGifts) || PatchClientPolicy.isEnabled(.spoofUniqueGifts) else { return original }
        var result = original
        result.gifts = original.gifts.map { profileGift($0, peerId: peerId, assets: assets) }
        result.filteredGifts = original.filteredGifts.map { profileGift($0, peerId: peerId, assets: assets) }
        if result.gifts.isEmpty {
            let emojiFile = FaithgramVisualPreferences.int("giftEmojiId").flatMap { assets.files[$0] }
            let template = assets.catalog.compactMap { gift -> StarGift.Gift? in if case let .generic(gift) = gift { return gift }; return nil }.first
            if let originalFile = emojiFile ?? template?.file {
                let gift = StarGift.Gift(id: FaithgramVisualPreferences.int("giftId") ?? template?.id ?? 1, title: nil, file: originalFile, price: 50, convertStars: 0, availability: nil, soldOut: nil, flags: [], upgradeStars: nil, releasedBy: nil, perUserLimit: nil, lockedUntilDate: nil, auctionSlug: nil, auctionGiftsPerRound: nil, auctionStartDate: nil, upgradeVariantsCount: nil, background: nil)
                let item = ProfileGiftsContext.State.StarGift(gift: .generic(gift), reference: .peer(peerId: peerId, id: -1), fromPeer: nil, date: Int32(clamping: Int64(Date().timeIntervalSince1970)), text: nil, entities: nil, nameHidden: false, savedToProfile: true, pinnedToTop: false, convertStars: nil, canUpgrade: false, canExportDate: nil, upgradeStars: nil, transferStars: 0, canTransferDate: 0, canResaleDate: nil, collectionIds: nil, prepaidUpgradeHash: nil, upgradeSeparate: false, dropOriginalDetailsStars: nil, number: nil, isRefunded: false, canCraftAt: nil)
                result.gifts = [profileGift(item, peerId: peerId, assets: assets)]; result.filteredGifts = result.gifts; result.count = 1
            }
        }
        return result
    }

    static func currentAssets() -> Assets {
        lock.lock(); defer { lock.unlock() }; return Assets(catalog: [], files: resolvedFiles, peers: [:])
    }
    static func catalog(_ original: [StarGift]?, assets: Assets) -> [StarGift]? {
        guard PatchClientPolicy.isEnabled(.showHiddenGifts) else { return original }
        let ids = FaithgramVisualPreferences.ids("hiddenGiftIds"), emojiIds = FaithgramVisualPreferences.ids("hiddenGiftEmojiIds")
        var extra: [StarGift] = []
        for (index, id) in ids.enumerated() {
            guard index < emojiIds.count, let file = assets.files[emojiIds[index]] else { continue }
            extra.append(.generic(StarGift.Gift(id: id, title: "Local gift", file: file, price: 0, convertStars: 0, availability: nil, soldOut: nil, flags: [], upgradeStars: nil, releasedBy: nil, perUserLimit: nil, lockedUntilDate: nil, auctionSlug: nil, auctionGiftsPerRound: nil, auctionStartDate: nil, upgradeVariantsCount: nil, background: nil)))
        }
        return extra + (original ?? []).filter { item in if case let .generic(gift) = item { return !ids.contains(gift.id) }; return true }
    }

    static func valueInfo(slug: String) -> StarGift.UniqueGift.ValueInfo? {
        let fallbackSlug = "Faithgram-" + String(small("uniqueNumber", 1))
        guard PatchClientPolicy.isEnabled(.spoofUniqueGifts), slug == text("uniqueSlug", fallbackSlug) else { return nil }
        return StarGift.UniqueGift.ValueInfo(isLastSaleOnFragment: false, valueIsAverage: false, value: number("uniqueValueAmount", number("uniqueValue", 0)), currency: text("uniqueValueCurrency", "USD"), initialSaleDate: small("giftDate", 0), initialSaleStars: number("giftPrice", 0), initialSalePrice: number("giftPrice", 0), lastSaleDate: nil, lastSalePrice: FaithgramVisualPreferences.int("uniqueLastResale"), floorPrice: FaithgramVisualPreferences.int("uniqueFloorPrice"), averagePrice: FaithgramVisualPreferences.int("uniqueAveragePrice"), listedCount: nil, fragmentListedCount: nil, fragmentListedUrl: nil)
    }
}
