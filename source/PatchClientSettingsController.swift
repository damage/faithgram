import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramApi
import TelegramPresentationData
import AccountContext

private enum FaithgramCategory: String, CaseIterable {
    case accounts, messages, privacy, gestures, settings, appearance, media, chats, notifications, badges, profile, balances, gifts, uniqueGifts, extraGifts, optimizations, diagnostics
    var title: String {
        switch self { case .uniqueGifts: return "Unique gifts"; case .extraGifts: return "Extra gifts"; default: return self.rawValue.capitalized }
    }
    var symbol: String {
        switch self {
        case .accounts: return "person.crop.circle"
        case .messages: return "bubble.left.and.bubble.right"
        case .privacy: return "lock.shield"
        case .gestures: return "hand.draw"
        case .settings: return "gearshape"
        case .appearance: return "paintbrush"
        case .media: return "waveform"
        case .chats: return "folder"
        case .notifications: return "bell.badge"
        case .badges: return "checkmark.seal"
        case .profile: return "person.text.rectangle"
        case .balances: return "star.circle"
        case .gifts, .uniqueGifts, .extraGifts: return "gift"
        case .optimizations: return "slider.horizontal.3"
        case .diagnostics: return "doc.text.magnifyingglass"
        }
    }
    var options: [PatchClientOption] {
        switch self {
        case .accounts: return [.unlimitedAccounts, .noPhoneException, .hideSelfPhone]
        case .messages: return [.saveDeletedMessages, .saveEditHistory, .regexFilters, .formattingPanel, .customFactCheck, .copyProtectedContent, .disableTTL, .showCallbackData, .disableSensitiveBlur, .moreRecentStickers, .openLinksWithoutWarning, .disableMediaSpoilers, .hideBlockedMessages]
        case .privacy: return [.alwaysOffline, .blockTyping, .blockCloudReads, .localDrafts, .hideAds, .hideProxyPromo, .cleanLinks, .hideAppPreview]
        case .gestures: return [.customGestures]
        case .settings: return []
        case .appearance: return [.lowercaseInterface, .localPremium, .hideStories, .disableStoryCamera, .dynamicIsland]
        case .media: return [.localTranscription, .localTranslation, .archiveDownloadedMedia]
        case .chats: return [.hideAllChats, .foldersAtBottom, .rememberFolder]
        case .notifications: return [.hidePinnedNotifications, .hideMentionNotifications]
        case .badges: return []
        case .profile: return [.customProfile]
        case .balances: return [.customBalances]
        case .gifts: return [.spoofGifts]
        case .uniqueGifts: return [.spoofUniqueGifts, .fakeGiftTransfer]
        case .extraGifts: return [.showHiddenGifts]
        case .optimizations: return [.disableMonetizationConfig, .hidePremiumUI, .hideGifts, .disablePaidReactions, .hideEmojiStatus, .hideCurrencies, .hideBoosts, .disablePremiumEffects]
        case .diagnostics: return [.protocolLogger]
        }
    }
}

private enum FaithgramRow {
    case category(FaithgramCategory)
    case visualField(FaithgramVisualPreferences.Field)
    case toggle(PatchClientOption)
    case ghost
    case text(title: String, key: String, fallback: String)
    case action(FaithgramAction)
}

private enum FaithgramAction: String {
    case exportSessions = "Export sessions backup"
    case restoreSessions = "Restore sessions backup"
    case history = "Message history"
    case protocolLog = "View protocol log"
    case giftCatalog = "Gift catalog ids"
    case lockNow = "Lock now"
    case passcode = "Passcode and Face ID"
    case theme = "Theme, text size and chat appearance"
    case stickers = "Stickers and emoji"
    case downloads = "Downloads and media quality"
    case privateMedia = "Save media from private chats"
    case groupMedia = "Save media from groups"
    case channelMedia = "Save media from channels"
    case notifications = "Sounds and notification settings"
    case activityStatus = "Live Activity status"
    case privacyProfiles = "Privacy profiles"
    case savePrivacyProfile = "Save current controls as custom profile"
    case undoPrivacyProfile = "Restore previous privacy controls"
    case ghostChats = "Ghost mode in selected chats"
    case gestureUp = "Three-finger swipe up"
    case gestureDown = "Three-finger swipe down"
    case exportSettings = "Export encrypted settings"
    case restoreSettings = "Restore encrypted settings"
}

private final class FaithgramToggle: UISwitch {
    var changed: ((Bool) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.addTarget(self, action: #selector(valueUpdated), for: .valueChanged)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func valueUpdated() { self.changed?(self.isOn) }
}

private final class FaithgramSettingsController: ViewController, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private let category: FaithgramCategory?
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var rows: [FaithgramRow] = []
    private var observer: NSObjectProtocol?
    private let actionDisposable = MetaDisposable()
    private lazy var sessionBackup = FaithgramSessionBackupController(context: self.context)
    private lazy var settingsBackup = FaithgramSettingsBackupController(context: self.context)

    init(context: AccountContext, category: FaithgramCategory? = nil) {
        self.context = context
        self.category = category
        let data = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: data, style: .glass))
        self.title = category.map { FaithgramPreferences.interfaceText($0.title) } ?? "faithgram"
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: FaithgramPreferences.interfaceText("Back"), style: .plain, target: nil, action: nil)
        self.statusBar.statusBarStyle = .White
        self.observer = NotificationCenter.default.addObserver(forName: FaithgramPreferences.changed, object: nil, queue: .main) { [weak self] _ in self?.reloadRows() }
        self.reloadRows()
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { actionDisposable.dispose(); if let observer = self.observer { NotificationCenter.default.removeObserver(observer) } }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = .black
        self.displayNodeDidLoad()
        self.table.backgroundColor = .black
        self.table.separatorColor = UIColor(white: 0.18, alpha: 1)
        self.table.rowHeight = UITableView.automaticDimension
        self.table.estimatedRowHeight = 64
        self.table.dataSource = self
        self.table.delegate = self
        self.table.contentInsetAdjustmentBehavior = .never
        self.view.addSubview(self.table)
        self.navigationBar?.updateBackgroundAlpha(0, transition: .immediate)
    }
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        transition.updateFrame(view: self.table, frame: CGRect(x: 0, y: top, width: layout.size.width, height: layout.size.height - top))
        self.table.contentInset.bottom = layout.intrinsicInsets.bottom + 16
        if self.category == nil { self.updateHeader(width: layout.size.width) }
    }
    private func updateHeader(width: CGFloat) {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 270))
        let icon = UIImageView(frame: CGRect(x: (width - 92) / 2, y: 38, width: 92, height: 92))
        if let path = Bundle.main.path(forResource: "FaithgramIcon", ofType: "png") { icon.image = UIImage(contentsOfFile: path) }
        else { icon.image = UIImage(systemName: "paperplane.fill"); icon.tintColor = .white }
        icon.contentMode = .scaleAspectFit
        icon.isAccessibilityElement = false
        header.addSubview(icon)
        let title = UILabel(frame: CGRect(x: 24, y: 153, width: width - 48, height: 42))
        title.text = "faithgram"
        title.font = .systemFont(ofSize: 30, weight: .semibold)
        title.textAlignment = .center
        title.textColor = .white
        header.addSubview(title)
        let version = UILabel(frame: CGRect(x: 24, y: 196, width: width - 48, height: 25))
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        version.text = "\(appVersion) (\(build))"
        version.font = .preferredFont(forTextStyle: .subheadline)
        version.textAlignment = .center
        version.textColor = .gray
        header.addSubview(version)
        self.table.tableHeaderView = header
    }
    private func reloadRows() {
        self.title = self.category.map { FaithgramPreferences.interfaceText($0.title) } ?? "faithgram"
        if let category = self.category {
            self.rows = category.options.map(FaithgramRow.toggle)
            let visualFields: [FaithgramVisualPreferences.Field]
            switch category {
            case .profile: visualFields = FaithgramVisualPreferences.profileFields
            case .balances: visualFields = FaithgramVisualPreferences.balanceFields
            case .gifts: visualFields = FaithgramVisualPreferences.regularGiftFields
            case .uniqueGifts: visualFields = FaithgramVisualPreferences.uniqueGiftFields
            case .extraGifts: visualFields = FaithgramVisualPreferences.hiddenGiftFields
            default: visualFields = []
            }
            self.rows += visualFields.map(FaithgramRow.visualField)
            if category == .diagnostics { self.rows.append(.action(.protocolLog)) }
            if category == .extraGifts { self.rows.append(.action(.giftCatalog)) }
            if category == .privacy {
                self.rows.insert(.ghost, at: 0)
                self.rows.insert(.action(.privacyProfiles), at: 0)
                self.rows += [.action(.savePrivacyProfile), .action(.undoPrivacyProfile), .action(.ghostChats), .action(.lockNow), .action(.passcode)]
            }
            if category == .gestures { self.rows += [.action(.gestureUp), .action(.gestureDown)] }
            if category == .settings { self.rows += [.action(.exportSettings), .action(.restoreSettings)] }
            if category == .accounts { self.rows += [.action(.exportSessions), .action(.restoreSessions)] }
            if category == .appearance { self.rows += [.action(.activityStatus), .action(.theme), .action(.stickers)] }
            if category == .notifications { self.rows.append(.action(.notifications)) }
            if category == .messages {
                self.rows += [.text(title: "Deleted mark", key: "deletedMark", fallback: "🧹"),
                              .text(title: "Edited mark", key: "editedMark", fallback: "🧹"),
                              .text(title: "Regex rules", key: "regexRules", fallback: ""), .text(title: "Fact-check text", key: "factCheckText", fallback: ""), .action(.history)]
            }
            if category == .media {
                self.rows.append(.text(title: "Translation language", key: "translationTarget", fallback: Locale.current.identifier.components(separatedBy: CharacterSet(charactersIn: "_-" )).first ?? "en"))
                self.rows += [.action(.privateMedia), .action(.groupMedia), .action(.channelMedia), .action(.downloads)]
            }
            if category == .badges { self.rows = [] }
        } else {
            self.rows = FaithgramCategory.allCases.filter {
                $0 != .badges || FaithgramPreferences.canManageBadges(accountPeerId: self.context.account.peerId.id._internalGetInt64Value())
            }.map(FaithgramRow.category)
        }
        if self.isNodeLoaded { self.table.reloadData() }
    }
    func numberOfSections(in tableView: UITableView) -> Int { return 1 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return self.rows.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { return self.category == nil ? "functions" : nil }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = UIColor(white: 0.105, alpha: 1)
        cell.textLabel?.textColor = .white
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.textColor = .gray
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .footnote)
        cell.detailTextLabel?.numberOfLines = 0
        cell.tintColor = .white
        switch self.rows[indexPath.row] {
        case let .category(category):
            cell.textLabel?.text = FaithgramPreferences.interfaceText(category.title)
            if let symbol = UIImage(systemName: category.symbol) {
                cell.imageView?.image = UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28)).image { _ in
                    let size = symbol.size.aspectFitted(CGSize(width: 24, height: 24))
                    symbol.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: CGRect(x: (28 - size.width) / 2, y: (28 - size.height) / 2, width: size.width, height: size.height))
                }
            }
            cell.accessoryType = .disclosureIndicator
        case let .visualField(field):
            cell.textLabel?.text = FaithgramPreferences.interfaceText(field.title)
            let value = FaithgramVisualPreferences.value(field.key, fallback: field.fallback)
            cell.detailTextLabel?.text = value.isEmpty ? FaithgramPreferences.interfaceText("Not set") : value
            cell.accessoryType = .disclosureIndicator
        case let .toggle(option):
            cell.textLabel?.text = FaithgramPreferences.interfaceText(option.title)
            cell.detailTextLabel?.text = FaithgramPreferences.interfaceText(option.explanation)
            let toggle = FaithgramToggle(frame: .zero)
            toggle.isOn = PatchClientPolicy.isEnabled(option)
            toggle.accessibilityLabel = cell.textLabel?.text
            toggle.changed = { value in PatchClientPolicy.setEnabled(option, value) }
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case .ghost:
            cell.textLabel?.text = FaithgramPreferences.interfaceText("Ghost mode")
            cell.detailTextLabel?.text = FaithgramPreferences.interfaceText("Offline status, no read receipts, no typing or upload indicators.")
            cell.imageView?.image = UIImage(systemName: "moon.fill")
            let toggle = FaithgramToggle(frame: .zero)
            toggle.isOn = FaithgramPreferences.ghostMode
            toggle.changed = { [weak self] value in
                FaithgramPreferences.setGhostMode(value)
                if value, let context = self?.context { let _ = context.account.network.request(Api.functions.account.updateStatus(offline: .boolTrue)).startStandalone() }
            }
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case let .text(title, key, fallback):
            cell.textLabel?.text = FaithgramPreferences.interfaceText(title)
            let value = FaithgramPreferences.text(key, fallback: fallback)
            cell.detailTextLabel?.text = value.isEmpty ? FaithgramPreferences.interfaceText("Not set") : value
            cell.accessoryType = .disclosureIndicator
        case let .action(action):
            cell.textLabel?.text = FaithgramPreferences.interfaceText(action.rawValue)
            cell.accessoryType = .disclosureIndicator
            if action == .exportSessions || action == .restoreSessions { cell.detailTextLabel?.text = FaithgramPreferences.interfaceText("Password-protected backup of active sessions") }
            if action == .activityStatus { cell.detailTextLabel?.text = FaithgramPreferences.text("activityStatus", fallback: "Check permissions and signing") }
            if action == .privacyProfiles { cell.detailTextLabel?.text = FaithgramPrivacySettings.currentProfile }
            if action == .ghostChats { cell.detailTextLabel?.text = FaithgramPreferences.interfaceText("Long-press a message to enable Ghost for that chat. Rules apply to matching chats in all local accounts. Online status is an account-wide control.") }
            if action == .gestureUp || action == .gestureDown { cell.detailTextLabel?.text = FaithgramPreferences.interfaceText(gestureTitle(FaithgramPreferences.text(action == .gestureUp ? "gesture.up" : "gesture.down", fallback: action == .gestureUp ? "profiles" : "ghost"))) }
            if action == .exportSettings || action == .restoreSettings { cell.detailTextLabel?.text = FaithgramPreferences.interfaceText("Password-protected Faithgram preferences and chat rules") }
        }
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch self.rows[indexPath.row] {
        case let .category(category):
            if category == .badges {
                guard FaithgramPreferences.canManageBadges(accountPeerId: context.account.peerId.id._internalGetInt64Value()) else { return }
                self.openSettingsPage(FaithgramBadgeAdminController(context: self.context))
            } else {
                self.openSettingsPage(FaithgramSettingsController(context: self.context, category: category))
            }
        case let .visualField(field):
            if field.choices.isEmpty {
                self.openSettingsPage(FaithgramTextController(context: context, title: FaithgramPreferences.interfaceText(field.title), text: FaithgramVisualPreferences.value(field.key, fallback: field.fallback), save: { text in try FaithgramVisualPreferences.save(field, text: text) }))
            } else {
                let alert = UIAlertController(title: FaithgramPreferences.interfaceText(field.title), message: nil, preferredStyle: .alert)
                for choice in field.choices {
                    alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText(choice), style: .default, handler: { _ in try? FaithgramVisualPreferences.save(field, text: choice) }))
                }
                alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Cancel"), style: .cancel))
                context.sharedContext.mainWindow?.presentNative(alert)
            }
        case let .action(action): self.perform(action)
        case let .text(title, key, fallback):
            if key == "regexRules" || key == "factCheckText" {
                self.openSettingsPage(FaithgramTextController(context: context, title: FaithgramPreferences.interfaceText(title), text: FaithgramPreferences.text(key), save: { text in
                    if key == "regexRules" { let _ = try FaithgramMessageFilter.compile(text) }
                    FaithgramPreferences.setText(key, text)
                }))
                return
            }
            let alert = UIAlertController(title: FaithgramPreferences.interfaceText(title), message: key == "translationTarget" ? FaithgramPreferences.interfaceText("Language code, for example en, ru, de or es. iOS may ask to download a language model.") : nil, preferredStyle: .alert)
            alert.addTextField { field in
                field.text = FaithgramPreferences.text(key, fallback: fallback)
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
            }
            alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Cancel"), style: .cancel))
            alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Save"), style: .default, handler: { _ in FaithgramPreferences.setText(key, alert.textFields?.first?.text ?? "") }))
            self.context.sharedContext.mainWindow?.presentNative(alert)
        default: break
        }
    }
    private func openSettingsPage(_ controller: ViewController) {
        (self.navigationController as? NavigationController)?.pushViewController(controller)
    }
    private func perform(_ action: FaithgramAction) {
        switch action {
        case .exportSettings: settingsBackup.exportSettings()
        case .restoreSettings: settingsBackup.importSettings()
        case .privacyProfiles:
            let alert = UIAlertController(title: FaithgramPreferences.interfaceText("Privacy profiles"), message: FaithgramPreferences.interfaceText("Standard turns these privacy controls off. Quiet hides your phone, ads, pinned and mention notifications, cleans links and conceals the app preview. Ghost also suppresses online status, reads, typing, upload indicators and cloud drafts. Chat-specific Ghost rules remain active."), preferredStyle: .alert)
            for name in FaithgramPrivacySettings.profiles where name != "custom" || UserDefaults.standard.data(forKey: "faithgram.privacy.custom") != nil {
                alert.addAction(UIAlertAction(title: name, style: .default) { _ in let _ = FaithgramPrivacySettings.applyProfile(name) })
            }
            alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Cancel"), style: .cancel))
            context.sharedContext.mainWindow?.presentNative(alert)
        case .savePrivacyProfile: FaithgramPrivacySettings.saveCustomProfile(); showInfo("Custom privacy profile saved.")
        case .undoPrivacyProfile: showInfo(FaithgramPrivacySettings.restorePreviousProfile() ? "Previous privacy controls restored." : "No previous profile to restore.")
        case .ghostChats: showInfo("Long-press a message and choose Ghost mode for this chat. The rule suppresses reads, typing and upload indicators for that peer across local accounts. Turning it off keeps global Ghost controls active. Telegram online status applies to the whole account.")
        case .gestureUp, .gestureDown:
            let key = action == .gestureUp ? "gesture.up" : "gesture.down"
            let alert = UIAlertController(title: FaithgramPreferences.interfaceText(action.rawValue), message: FaithgramPreferences.interfaceText("Use three fingers outside text editors. Home Screen quick actions wait for the app to unlock."), preferredStyle: .alert)
            for value in ["none", "profiles", "ghost", "lock", "cleanLinks"] {
                alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText(gestureTitle(value)), style: .default) { _ in FaithgramPreferences.setText(key, value) })
            }
            alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Cancel"), style: .cancel))
            context.sharedContext.mainWindow?.presentNative(alert)
        case .exportSessions: sessionBackup.exportSessions()
        case .restoreSessions: sessionBackup.importSessions()
        case .history: openSettingsPage(FaithgramHistoryController(context: context))
        case .giftCatalog:
            actionDisposable.set((context.engine.payments.cachedStarGifts() |> take(1) |> deliverOnMainQueue).start(next: { [weak self] gifts in
                guard let self else { return }
                let text = (gifts ?? []).map { gift -> String in
                    switch gift {
                    case let .generic(gift): return "\(gift.title ?? "Gift")\nid: \(gift.id)\ncustom emoji: \(gift.file.fileId.id)"
                    case let .unique(gift): return "\(gift.title) #\(gift.number)\nid: \(gift.id)\nslug: \(gift.slug)"
                    }
                }.joined(separator: "\n\n")
                self.openSettingsPage(FaithgramTextController(context: self.context, title: FaithgramPreferences.interfaceText("Gift catalog ids"), text: text.isEmpty ? "No cached gifts yet. Open the gift catalog first." : text, save: nil))
            }))
        case .protocolLog:
            FaithgramProtocolLog.read { [weak self] result in
                guard let self else { return }
                let text: String
                switch result { case let .success(value): text = value.isEmpty ? "The protocol log is empty." : value; case .failure: text = "The protocol log could not be decrypted." }
                self.openSettingsPage(FaithgramTextController(context: self.context, title: FaithgramPreferences.interfaceText("Protocol log"), text: text, save: nil))
            }
        case .lockNow:
            actionDisposable.set((context.sharedContext.accountManager.transaction { $0.getAccessChallengeData() } |> deliverOnMainQueue).start(next: { [weak self] challenge in
                guard let self else { return }
                if case .none = challenge { self.perform(.passcode) }
                else { self.context.sharedContext.appLockContext.lock() }
            }))
        case .passcode:
            actionDisposable.set((passcodeOptionsAccessController(context: context, pushController: { [weak self] in self?.openSettingsPage($0) }, completion: { [weak self] success in
                if success, let self { self.openSettingsPage(passcodeOptionsController(context: self.context)) }
            }) |> deliverOnMainQueue).start(next: { [weak self] controller in if let controller { self?.openSettingsPage(controller) } }))
        case .theme: openSettingsPage(themeSettingsController(context: context))
        case .stickers: openSettingsPage(installedStickerPacksController(context: context, mode: .general))
        case .downloads: openSettingsPage(dataAndStorageController(context: context))
        case .privateMedia: openSettingsPage(saveIncomingMediaController(context: context, scope: .peerType(.privateChats)))
        case .groupMedia: openSettingsPage(saveIncomingMediaController(context: context, scope: .peerType(.groups)))
        case .channelMedia: openSettingsPage(saveIncomingMediaController(context: context, scope: .peerType(.channels)))
        case .notifications: openSettingsPage(notificationsAndSoundsController(context: context, exceptionsList: nil))
        case .activityStatus:
            let status = FaithgramPreferences.text("activityStatus", fallback: "Live Activities require iOS 16.2 or later.")
            let error = FaithgramPreferences.text("activityError")
            let alert = UIAlertController(title: "faithgram live activity", message: status + (error.isEmpty ? "" : "\n\n" + error), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "start or restart", style: .default, handler: { _ in
                PatchClientPolicy.setEnabled(.dynamicIsland, true)
                NotificationCenter.default.post(name: FaithgramPreferences.restartLiveActivity, object: nil)
            }))
            alert.addAction(UIAlertAction(title: "iOS settings", style: .default, handler: { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }))
            alert.addAction(UIAlertAction(title: "close", style: .cancel))
            context.sharedContext.mainWindow?.presentNative(alert)
        }
    }

    private func gestureTitle(_ value: String) -> String {
        switch value { case "profiles": return "Choose privacy profile"; case "ghost": return "Toggle Ghost mode"; case "lock": return "Lock app"; case "cleanLinks": return "Toggle link cleaning"; default: return "No action" }
    }
    private func showInfo(_ message: String) {
        let alert = UIAlertController(title: "faithgram", message: FaithgramPreferences.interfaceText(message), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("OK"), style: .default))
        context.sharedContext.mainWindow?.presentNative(alert)
    }

}

public func patchClientSettingsController(context: AccountContext) -> ViewController {
    return FaithgramSettingsController(context: context)
}
