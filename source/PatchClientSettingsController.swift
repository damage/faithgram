import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

private final class PatchClientSettingsArguments {
    let update: (PatchClientOption, Bool) -> Void

    init(update: @escaping (PatchClientOption, Bool) -> Void) {
        self.update = update
    }
}

private struct PatchClientSettingsEntry: ItemListNodeEntry {
    let stableId: Int32
    let section: ItemListSectionId
    let theme: PresentationTheme
    let option: PatchClientOption?
    let text: String
    let value: Bool

    static func ==(lhs: PatchClientSettingsEntry, rhs: PatchClientSettingsEntry) -> Bool {
        return lhs.stableId == rhs.stableId && lhs.section == rhs.section
            && lhs.theme === rhs.theme && lhs.option == rhs.option
            && lhs.text == rhs.text && lhs.value == rhs.value
    }

    static func <(lhs: PatchClientSettingsEntry, rhs: PatchClientSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        if let option = self.option {
            let arguments = arguments as! PatchClientSettingsArguments
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass,
                title: option.title, value: self.value, sectionId: self.section, style: .blocks,
                updated: { value in arguments.update(option, value) })
        }
        return ItemListTextItem(presentationData: presentationData, text: .plain(self.text), sectionId: self.section)
    }
}

public func patchClientSettingsController(context: AccountContext) -> ViewController {
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    let arguments = PatchClientSettingsArguments(update: { option, value in
        PatchClientPolicy.setEnabled(option, value)
        revision.set(0)
    })
    let signal = combineLatest(context.sharedContext.presentationData, revision.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [PatchClientSettingsEntry] = []
        entries.append(PatchClientSettingsEntry(stableId: 0, section: 0, theme: presentationData.theme,
            option: nil,
            text: "Settings apply to all accounts on this installation. All options are off by default.",
            value: false))
        for (index, option) in PatchClientOption.allCases.enumerated() {
            let section = Int32(index + 1)
            let stableId = Int32(index * 2 + 1)
            entries.append(PatchClientSettingsEntry(stableId: stableId, section: section,
                theme: presentationData.theme, option: option, text: "", value: PatchClientPolicy.isEnabled(option)))
            entries.append(PatchClientSettingsEntry(stableId: stableId + 1, section: section,
                theme: presentationData.theme, option: nil, text: option.explanation, value: false))
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData),
            title: .text("Faithgram"), leftNavigationButton: nil, rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData),
            entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    return ItemListController(context: context, state: signal)
}
