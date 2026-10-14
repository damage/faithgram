import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class FaithgramGiftManagerArguments {
    let context: AccountContext
    let gifts: ProfileGiftsContext
    weak var controller: ViewController?
    var latestGifts: [ProfileGiftsContext.State.StarGift] = []

    init(context: AccountContext, gifts: ProfileGiftsContext) {
        self.context = context
        self.gifts = gifts
    }

    func present(_ alert: UIAlertController) {
        if let popover = alert.popoverPresentationController, let view = self.controller?.view {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
        }
        self.context.sharedContext.mainWindow?.presentNative(alert)
    }

    func openActions(_ gift: ProfileGiftsContext.State.StarGift) {
        guard let reference = gift.reference else { return }
        let alert = UIAlertController(title: faithgramGiftTitle(gift), message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText(gift.savedToProfile ? "Hide from profile" : "Show on profile"), style: .default, handler: { [gifts] _ in
            gifts.updateStarGiftAddedToProfile(reference: reference, added: !gift.savedToProfile)
        }))
        if case .unique = gift.gift {
            alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText(gift.pinnedToTop ? "Unpin" : "Pin to top"), style: .default, handler: { [gifts] _ in
                gifts.updateStarGiftPinnedToTop(reference: reference, pinnedToTop: !gift.pinnedToTop)
            }))
        }
        if case let .unique(unique) = gift.gift {
            alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Copy link"), style: .default, handler: { _ in
                UIPasteboard.general.string = "https://t.me/nft/\(unique.slug)"
            }))
        }
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Cancel"), style: .cancel))
        self.present(alert)
    }

    func bulk(_ kind: FaithgramGiftManagerEntry.Bulk, gifts list: [ProfileGiftsContext.State.StarGift]) {
        switch kind {
        case .hideAll:
            for gift in list where gift.savedToProfile { if let reference = gift.reference { self.gifts.updateStarGiftAddedToProfile(reference: reference, added: false) } }
        case .showAll:
            for gift in list where !gift.savedToProfile { if let reference = gift.reference { self.gifts.updateStarGiftAddedToProfile(reference: reference, added: true) } }
        case .unpinAll:
            self.gifts.updatePinnedToTopStarGifts(references: [])
        case .loadMore:
            self.gifts.loadMore()
        }
    }
}

private func faithgramGiftTitle(_ gift: ProfileGiftsContext.State.StarGift) -> String {
    switch gift.gift {
    case let .generic(generic): return generic.title ?? "Gift"
    case let .unique(unique): return "\(unique.title) #\(unique.number)"
    }
}

private enum FaithgramGiftManagerEntry: ItemListNodeEntry {
    enum Bulk: Int32 { case hideAll, showAll, unpinAll, loadMore }

    case header(Int32, String)
    case footer(Int32, String)
    case bulk(Int32, Bulk, String)
    case gift(Int32, ProfileGiftsContext.State.StarGift, String, String)

    var section: ItemListSectionId {
        switch self {
        case .header, .footer, .bulk: return 0
        case .gift: return 1
        }
    }
    var stableId: Int32 {
        switch self {
        case let .header(index, _), let .footer(index, _), let .bulk(index, _, _), let .gift(index, _, _, _): return index
        }
    }
    static func ==(lhs: FaithgramGiftManagerEntry, rhs: FaithgramGiftManagerEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(a, b), .header(c, d)): return a == c && b == d
        case let (.footer(a, b), .footer(c, d)): return a == c && b == d
        case let (.bulk(a, b, c), .bulk(d, e, f)): return a == d && b == e && c == f
        case let (.gift(a, b, c, d), .gift(e, f, g, h)): return a == e && b == f && c == g && d == h
        default: return false
        }
    }
    static func <(lhs: FaithgramGiftManagerEntry, rhs: FaithgramGiftManagerEntry) -> Bool { return lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! FaithgramGiftManagerArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .bulk(_, kind, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: kind == .hideAll ? .destructive : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.bulk(kind, gifts: arguments.latestGifts)
            })
        case let .gift(_, gift, title, detail):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: detail, labelStyle: .multilineDetailText, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: {
                arguments.openActions(gift)
            })
        }
    }
}

func faithgramGiftManagerController(context: AccountContext) -> ViewController {
    let giftsContext = ProfileGiftsContext(account: context.account, peerId: context.account.peerId, collectionId: nil, sorting: .date, filter: .All, limit: 100)
    let arguments = FaithgramGiftManagerArguments(context: context, gifts: giftsContext)
    let text = FaithgramPreferences.interfaceText
    let signal = combineLatest(context.sharedContext.presentationData, giftsContext.state)
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        arguments.latestGifts = state.gifts
        var entries: [FaithgramGiftManagerEntry] = []
        var index: Int32 = 0
        func add(_ entry: FaithgramGiftManagerEntry) { entries.append(entry); index += 1 }
        let shown = state.gifts.filter { $0.savedToProfile }.count
        let pinned = state.gifts.filter { $0.pinnedToTop }.count
        add(.header(index, text("Gifts")))
        add(.bulk(index, .showAll, text("Show all on profile")))
        add(.bulk(index, .hideAll, text("Hide all from profile")))
        add(.bulk(index, .unpinAll, text("Unpin all")))
        add(.footer(index, text("\(state.gifts.count) gifts loaded · \(shown) shown on profile · \(pinned) pinned. Tap a gift for actions.")))
        for gift in state.gifts {
            var parts: [String] = []
            parts.append(text(gift.savedToProfile ? "shown on profile" : "hidden"))
            if gift.pinnedToTop { parts.append(text("pinned")) }
            if case .unique = gift.gift { parts.append(text("unique")) }
            if let from = gift.fromPeer { parts.append(text("from ") + from.compactDisplayTitle) }
            add(.gift(index, gift, faithgramGiftTitle(gift), parts.joined(separator: " · ")))
        }
        if case let .ready(canLoadMore, _) = state.dataState, canLoadMore {
            add(.bulk(index, .loadMore, text("Load more")))
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(text("Gift Manager")), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    arguments.controller = controller
    return controller
}
