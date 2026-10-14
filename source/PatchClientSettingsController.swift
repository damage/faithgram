import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramApi
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// MARK: - Screens

enum FaithgramScreen: Equatable {
    case root
    case accounts, messages, contextMenu, gifts, appearance, newDesign, settingsMenu, rankColors, misc, stories, calls, profiles
    case privacy, gestures, messageTools, profileDisplay, balances, giftDisplay, uniqueGifts, extraGifts, diagnostics, backup
    case choice(FaithgramChoice)
    case cover(FaithgramProfileCover.Field, Bool)

    var title: String {
        switch self {
        case .root: return "faithgram"
        case .accounts: return "Accounts"
        case .messages: return "Messages"
        case .contextMenu: return "Context Menu"
        case .gifts: return "Gifts"
        case .appearance: return "Appearance"
        case .newDesign: return "New Design"
        case .settingsMenu: return "Settings menu"
        case .rankColors: return "Rank Colors"
        case .misc: return "Misc"
        case .stories: return "Stories"
        case .calls: return "Calls"
        case .profiles: return "Profiles"
        case .privacy: return "Privacy"
        case .gestures: return "Gestures"
        case .messageTools: return "Message tools"
        case .profileDisplay: return "Profile display"
        case .balances: return "Balances"
        case .giftDisplay: return "Gift display"
        case .uniqueGifts: return "Unique gifts"
        case .extraGifts: return "Extra gifts"
        case .diagnostics: return "Diagnostics"
        case .backup: return "Backup"
        case let .choice(choice): return choice.title
        case let .cover(field, own): return FaithgramProfileCover.choice(field, ownProfile: own).title
        }
    }
}

// MARK: - Rows

final class FaithgramSettingsEnvironment {
    let context: AccountContext
    weak var controller: ViewController?
    let disposable = MetaDisposable()
    lazy var sessionBackup = FaithgramSessionBackupController(context: self.context)
    lazy var settingsBackup = FaithgramSettingsBackupController(context: self.context)

    init(context: AccountContext) { self.context = context }
    deinit { self.disposable.dispose() }

    func push(_ controller: ViewController) {
        (self.controller?.navigationController as? NavigationController)?.pushViewController(controller)
    }
    func open(_ screen: FaithgramScreen) {
        self.push(faithgramScreenController(context: self.context, screen: screen))
    }
    func present(_ alert: UIAlertController) {
        self.context.sharedContext.mainWindow?.presentNative(alert)
    }
    func info(_ message: String, title: String = "faithgram") {
        let alert = UIAlertController(title: title, message: FaithgramPreferences.interfaceText(message), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("OK"), style: .default))
        self.present(alert)
    }
    func prompt(title: String, message: String? = nil, placeholder: String? = nil, initial: String = "", confirm: String = "Save", handler: @escaping (String) -> Void) {
        let alert = UIAlertController(title: FaithgramPreferences.interfaceText(title), message: message.map(FaithgramPreferences.interfaceText), preferredStyle: .alert)
        alert.addTextField { field in
            field.text = initial
            field.placeholder = placeholder.map(FaithgramPreferences.interfaceText)
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText(confirm), style: .default, handler: { _ in handler(alert.textFields?.first?.text ?? "") }))
        self.present(alert)
    }
    func choose(title: String, message: String? = nil, options: [(String, () -> Void)]) {
        let alert = UIAlertController(title: FaithgramPreferences.interfaceText(title), message: message.map(FaithgramPreferences.interfaceText), preferredStyle: .alert)
        for (name, action) in options {
            alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText(name), style: .default, handler: { _ in action() }))
        }
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Cancel"), style: .cancel))
        self.present(alert)
    }
    func editText(title: String, key: String, fallback: String, multiline: Bool, message: String?) {
        if multiline {
            self.push(FaithgramTextController(context: self.context, title: FaithgramPreferences.interfaceText(title), text: FaithgramPreferences.text(key), save: { text in
                if key == "regexRules" { let _ = try FaithgramMessageFilter.compile(text) }
                FaithgramPreferences.setText(key, text)
            }))
        } else {
            self.prompt(title: title, message: message, initial: FaithgramPreferences.text(key, fallback: fallback)) { text in FaithgramPreferences.setText(key, text) }
        }
    }
    func editVisualField(_ field: FaithgramVisualPreferences.Field) {
        if field.choices.isEmpty {
            self.push(FaithgramTextController(context: self.context, title: FaithgramPreferences.interfaceText(field.title), text: FaithgramVisualPreferences.value(field.key, fallback: field.fallback), save: { text in try FaithgramVisualPreferences.save(field, text: text) }))
        } else {
            self.choose(title: field.title, options: field.choices.map { choice in (choice, { try? FaithgramVisualPreferences.save(field, text: choice) }) })
        }
    }
}

enum FaithgramRowKind {
    case toggle(PatchClientOption)
    case ghost
    case screen(FaithgramScreen)
    case disclosure(label: String?, detail: String?, accent: Bool, action: (FaithgramSettingsEnvironment) -> Void)
    case button(destructive: Bool, action: (FaithgramSettingsEnvironment) -> Void)
    case slider(key: String, fallback: Int, range: ClosedRange<Int>)
    case text(key: String, fallback: String, multiline: Bool, message: String?)
    case visualField(FaithgramVisualPreferences.Field)
    case check(checked: Bool, action: (FaithgramSettingsEnvironment) -> Void)
}

struct FaithgramRow {
    let title: String
    let icon: String?
    let subtitle: String?
    let enabled: Bool
    let kind: FaithgramRowKind

    init(_ title: String, icon: String? = nil, subtitle: String? = nil, enabled: Bool = true, _ kind: FaithgramRowKind) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.enabled = enabled
        self.kind = kind
    }
}

struct FaithgramSection {
    let header: String?
    let rows: [FaithgramRow]
    let footer: String?
    init(_ rows: [FaithgramRow], footer: String? = nil) {
        self.header = nil
        self.rows = rows
        self.footer = footer
    }
    init(_ header: String, _ rows: [FaithgramRow], footer: String? = nil) {
        self.header = header
        self.rows = rows
        self.footer = footer
    }
}

private func toggle(_ title: String, _ icon: String?, _ option: PatchClientOption, enabled: Bool = true, explain: Bool = false) -> FaithgramRow {
    return FaithgramRow(title, icon: icon, subtitle: explain && !option.explanation.isEmpty ? option.explanation : nil, enabled: enabled, .toggle(option))
}
private func option(_ option: PatchClientOption, _ icon: String? = nil) -> FaithgramRow {
    return FaithgramRow(option.title, icon: icon, subtitle: option.explanation.isEmpty ? nil : option.explanation, .toggle(option))
}
private func page(_ title: String, _ icon: String?, _ target: FaithgramScreen) -> FaithgramRow {
    return FaithgramRow(title, icon: icon, .screen(target))
}
private func link(_ title: String, _ icon: String? = nil, label: String? = nil, detail: String? = nil, accent: Bool = false, _ action: @escaping (FaithgramSettingsEnvironment) -> Void) -> FaithgramRow {
    return FaithgramRow(title, icon: icon, .disclosure(label: label, detail: detail, accent: accent, action: action))
}
private func field(_ title: String, _ key: String, fallback: String = "", multiline: Bool = false, message: String? = nil) -> FaithgramRow {
    return FaithgramRow(title, .text(key: key, fallback: fallback, multiline: multiline, message: message))
}
private func gestureTitle(_ value: String) -> String {
    switch value {
    case "profiles": return "Choose privacy profile"
    case "ghost": return "Toggle Ghost mode"
    case "lock": return "Lock app"
    case "cleanLinks": return "Toggle link cleaning"
    default: return "No action"
    }
}

// MARK: - Screen definitions

func faithgramSections(for screen: FaithgramScreen, env: FaithgramSettingsEnvironment) -> [FaithgramSection] {
    let on = PatchClientPolicy.isEnabled
    switch screen {
    case .root:
        var tools: [FaithgramRow] = [
            page("Privacy", "lock.shield", .privacy),
            page("Gestures", "hand.draw", .gestures),
            page("Message tools", "text.magnifyingglass", .messageTools),
            page("Profile display", "person.text.rectangle", .profileDisplay),
            page("Balances", "star.circle", .balances),
            page("Gift display", "gift", .giftDisplay),
            page("Unique gifts", "sparkles", .uniqueGifts),
            page("Extra gifts", "gift.circle", .extraGifts),
            page("Diagnostics", "doc.text.magnifyingglass", .diagnostics),
            page("Backup", "externaldrive", .backup)
        ]
        if FaithgramPreferences.canManageBadges(accountPeerId: env.context.account.peerId.id._internalGetInt64Value()) {
            tools.append(link("Badges", "checkmark.seal") { env in env.push(FaithgramBadgeAdminController(context: env.context)) })
        }
        return [
            FaithgramSection([
                page("Accounts", "person.crop.circle", .accounts),
                page("Messages", "bubble.left.and.bubble.right", .messages),
                page("Gifts", "gift", .gifts),
                page("Appearance", "paintbrush", .appearance),
                page("Misc", "ellipsis.circle", .misc),
                page("Profiles", "square.stack", .profiles)
            ]),
            FaithgramSection("Faithgram tools", tools)
        ]

    case .accounts:
        return [
            FaithgramSection([link("Notifications", "bell") { env in env.push(notificationsAndSoundsController(context: env.context, exceptionsList: nil)) }]),
            FaithgramSection([toggle("Unlimited accounts", "infinity", .unlimitedAccounts)]),
            FaithgramSection("Profile info", [
                toggle("Show Profile ID", "person.text.rectangle", .showProfileId),
                toggle("Show Data Center", "server.rack", .showDataCenter),
                toggle("Show Mutual Contact", "person", .showMutualContact),
                toggle("Show Joined Date", "clock", .showJoinedDate)
            ]),
            FaithgramSection("My profile", [
                page("Hide Phone", "phone", .cover(.phone, true)),
                page("Hide Profile ID", "person.text.rectangle", .cover(.id, true)),
                page("Hide Usernames", "textformat", .cover(.usernames, true))
            ], footer: "The same covering, applied to your own profile. \"Full\" takes the phone row away altogether instead of covering it, so it does not combine with the rest."),
            FaithgramSection("Other profiles", [
                page("Hide Phone", "phone", .cover(.phone, false)),
                page("Hide Profile ID", "person.text.rectangle", .cover(.id, false)),
                page("Hide Usernames", "textformat", .cover(.usernames, false))
            ], footer: "Covers another person's details on their profile. \"Full\" takes the row away altogether, so it does not combine with the rest; \"Spoiler\" hides the value behind a tap to reveal and \"Screen sharing\" keeps it out of screenshots, and those two can be used together."),
            FaithgramSection("Sessions", [
                link("Export sessions backup", "square.and.arrow.up", detail: "Password-protected backup of active sessions") { env in env.sessionBackup.exportSessions() },
                link("Restore sessions backup", "square.and.arrow.down", detail: "Password-protected backup of active sessions") { env in env.sessionBackup.importSessions() }
            ])
        ]

    case .messages:
        return [
            FaithgramSection("Context menu", [page("Context Menu", "list.bullet", .contextMenu)]),
            FaithgramSection("Media", [
                toggle("Show media origin", "eye", .showMediaOrigin),
                page("Media origin", "camera", .choice(FaithgramChoices.mediaOrigin)),
                toggle("Send photos in HD", "hd.square", .sendPhotosHD),
                toggle("Shot", "message", .messageShot)
            ]),
            FaithgramSection("Other", [
                toggle("Double-tap to edit messages", "pencil", .doubleTapEdit),
                page("Recording Button", "mic", .choice(FaithgramChoices.recordingButton)),
                toggle("Message Deletion Effects", "trash", .deletionEffects),
                toggle("Hide Reaction", "eye.slash", .hideReactions),
                toggle("Hide Reaction Notifications", "heart", .hideReactionNotifications),
                toggle("Hide Mention Notifications", "at", .hideMentionNotifications),
                toggle("Original date of forwards", "clock", .originalForwardDate),
                toggle("Hide Article Button", "viewfinder", .hideArticleButton),
                toggle("Post as channel by default", "megaphone", .postAsChannelDefault)
            ]),
            FaithgramSection([
                toggle("Disable spoilers for text", "eye.slash", .disableTextSpoilers),
                toggle("Disable spoilers for media", "eye.slash", .disableMediaSpoilers)
            ], footer: "Show spoiler-hidden content immediately, without tapping to reveal."),
            FaithgramSection([toggle("Seconds in messages", "clock", .secondsInMessages)], footer: "Show the time on each message with seconds.")
        ]

    case .contextMenu:
        return [
            FaithgramSection("Message menu", [
                toggle("Reply", "arrowshape.turn.up.left", .contextMenuReply),
                toggle("Edit", "pencil", .contextMenuEdit),
                toggle("Copy", "doc.on.doc", .contextMenuCopy),
                toggle("Copy link", "link", .contextMenuCopyLink),
                toggle("Forward", "arrowshape.turn.up.right", .contextMenuForward),
                toggle("Pin", "pin", .contextMenuPin),
                toggle("Select", "checkmark.circle", .contextMenuSelect),
                toggle("Translate", "character.book.closed", .contextMenuTranslate),
                toggle("Speak", "speaker.wave.2", .contextMenuSpeak),
                toggle("Save media", "square.and.arrow.down", .contextMenuSaveMedia),
                toggle("Report", "exclamationmark.bubble", .contextMenuReport),
                toggle("Delete", "trash", .contextMenuDelete)
            ], footer: "Standard items shown when you hold a message. Items that Telegram hides for a chat stay hidden."),
            FaithgramSection("Faithgram items", [
                toggle("Ghost for this chat", "eye.slash", .contextMenuGhost),
                toggle("Message history", "clock.arrow.circlepath", .contextMenuHistory),
                toggle("Media archive for this chat", "archivebox", .contextMenuMediaArchive)
            ]),
            FaithgramSection("Sticker menu", [
                toggle("Send without sound", "speaker.slash", .contextMenuSendSilently),
                toggle("Schedule message", "clock", .contextMenuSchedule),
                toggle("Add to favorites", "bookmark", .contextMenuFavorites),
                toggle("Copy sticker id", "doc.on.doc", .contextMenuCopyStickerId),
                toggle("Edit sticker", "pencil.and.outline", .contextMenuEditSticker),
                toggle("View sticker set", "face.smiling", .contextMenuStickerSet),
                toggle("Remove from recents", "trash", .contextMenuRemoveRecent)
            ], footer: "Items shown when you hold a sticker in the panel.")
        ]

    case .gifts:
        return [
            FaithgramSection([
                toggle("Multiple gift sending", "xmark", .multipleGiftSending),
                toggle("Grid sending", "gift", .gridGiftSending)
            ], footer: "Show an Nx multiplier on the gift-send screen. Sending a regular gift with an Nx multiplier sends it N times."),
            FaithgramSection([
                toggle("Choose users", "person.3", .giftChooseUsers),
                toggle("Search gifts in send/profile", "magnifyingglass", .giftSearch),
                toggle("Gift cart", "gift", .giftCart),
                toggle("Gift Manager", "circle.grid.2x2", .giftManager),
                link("Open Gift Manager", "square.grid.2x2") { env in env.push(faithgramGiftManagerController(context: env.context)) },
                toggle("Skip upgrade rolling", "clock", .skipUpgradeRolling)
            ]),
            FaithgramSection([toggle("Show hidden gifts", "gift", .showHiddenGifts)], footer: "Show gifts that Telegram removed from the store but which can still be bought. Gift ids are configured in Faithgram tools → Extra gifts."),
            FaithgramSection([
                toggle("Show ID Gifts", "gift", .showGiftIds),
                toggle("Embed", "chevron.left.forwardslash.chevron.right", .giftEmbed)
            ]),
            FaithgramSection([toggle("Require 2FA for gift actions", "shield", .giftActions2FA)])
        ]

    case .appearance:
        return [
            FaithgramSection("Tabs", [
                toggle("Hide Tab Bar", "eye.slash", .hideTabBar),
                toggle("Show Contacts Tab", "person", .showContactsTab),
                toggle("Show Calls Tab", "phone", .showCallsTab),
                toggle("Show Tab Names", "textformat", .showTabNames),
                toggle("Search Button", "magnifyingglass", .tabSearchButton),
                toggle("Wide Tab bar", "rectangle.bottomhalf.inset.filled", .wideTabBar),
                page("Notifications Badge", "exclamationmark.circle", .choice(FaithgramChoices.tabsBadge))
            ], footer: "With the tab bar hidden, swipe up with three fingers anywhere to bring it back."),
            FaithgramSection("Chat folders", [
                toggle("Folders at Bottom", "arrow.down", .foldersAtBottom),
                toggle("Hide \"All Chats\"", "eye.slash", .hideAllChats),
                toggle("Smaller spacing", "rectangle.compress.vertical", .folderSmallerSpacing),
                FaithgramRow("\"All Chats\" title", icon: "textformat", .text(key: "allChatsTitle", fallback: "", multiline: false, message: "Leave empty to keep the default title.")),
                toggle("Open Last Folder", "folder", .rememberFolder),
                toggle("Notifications Badge", "exclamationmark.circle", .folderNotificationBadge)
            ]),
            FaithgramSection("Suggest reaction", [toggle("Hide Suggested", "eye.slash", .hideSuggestedReactions)], footer: "Hides the quick reactions row above a message."),
            FaithgramSection("Buttons", [page("Settings menu", "gearshape", .settingsMenu)]),
            FaithgramSection("Stickers and emoji size", [
                FaithgramRow("Size", .slider(key: "stickerSize", fallback: 100, range: 50...200)),
                toggle("Show timestamp", "clock", .stickerTimestamp)
            ]),
            FaithgramSection("Round videos & voice messages", [
                toggle("Select Camera", "camera.rotate", .selectCamera),
                toggle("Start with Rear Camera", "camera", .startRearCamera, enabled: !on(.selectCamera)),
                toggle("Round Video in HD", "hd.square", .roundVideoHD),
                toggle("Force 60 FPS", "camera", .force60FPS),
                toggle("Force x0.5", "camera", .forceHalfZoom),
                toggle("Keep music playing", "mic", .keepMusicPlaying),
                page("Recording microphone", "mic", .choice(FaithgramChoices.recordingMicrophone)),
                toggle("Custom pitch", "mic", .customPitch)
            ], footer: "Changes your voice pitch in voice messages and round videos."),
            FaithgramSection("Gallery", [
                toggle("Camera in Gallery", "camera", .cameraInGallery),
                toggle("Camera Preview in Gallery", "eye", .cameraPreviewInGallery)
            ]),
            FaithgramSection("Pull to next", [
                toggle("Pull to Next Unread Channel", "arrow.down", .pullToNextUnreadChannel),
                toggle("Pull to Next Topic", "list.bullet", .pullToNextTopic)
            ]),
            FaithgramSection("Names", [
                toggle("Fix Invisible Name", "textformat", .fixInvisibleName),
                page("Rank Colors", "textformat", .rankColors)
            ]),
            FaithgramSection("Faithgram badge", [toggle("Disable Badge Effect", "sparkles", .disableBadgeEffect)]),
            FaithgramSection("New design [WIP]", [page("New Design", "theatermasks", .newDesign)]),
            FaithgramSection([toggle("Old Design [WIP]", "theatermask.and.paintbrush", .oldDesign)], footer: "Replaces navigation bars, the main tab bar, buttons, sheets and glass controls with the Telegram 12.0 interface. Relaunch Faithgram after changing this setting."),
            FaithgramSection("Faithgram", [
                toggle("Lowercase interface", "textformat.abc", .lowercaseInterface),
                toggle("Local premium appearance", "star", .localPremium),
                toggle("Faithgram Live Activity", "circle.dashed", .dynamicIsland),
                toggle("Island badge in the app", "capsule", .islandBadge),
                link("Live Activity status", "info.circle", label: FaithgramPreferences.text("activityStatus", fallback: "Check permissions and signing")) { env in env.showActivityStatus() },
                link("Theme, text size and chat appearance", "paintpalette") { env in env.push(themeSettingsController(context: env.context)) },
                link("Stickers and emoji", "face.smiling") { env in env.push(installedStickerPacksController(context: env.context, mode: .general)) }
            ])
        ]

    case .newDesign:
        let enabled = on(.newDesign)
        return [
            FaithgramSection([toggle("New Design [WIP]", "theatermasks", .newDesign)], footer: "Rebuilds the profile and chat the way the official client's Liquid Glass concept renders them: an avatar-derived full-bleed background, floating glass cards and round icon-only action buttons, and a floating chat navigation. More screens will follow."),
            FaithgramSection("Profile", [
                toggle("Profile", "theatermasks", .newDesignProfile, enabled: enabled),
                toggle("Posts panel", "circle.dashed", .newDesignPostsPanel, enabled: enabled)
            ]),
            FaithgramSection("Chat", [
                toggle("Floating navigation", "eye", .newDesignFloatingNavigation, enabled: enabled),
                toggle("Header avatar", "person", .newDesignHeaderAvatar, enabled: enabled),
                toggle("Chat title", "textformat", .newDesignChatTitle, enabled: enabled),
                toggle("Attach button", "square.and.arrow.up", .newDesignAttachButton, enabled: enabled),
                toggle("Message menu", "list.bullet", .newDesignMessageMenu, enabled: enabled)
            ]),
            FaithgramSection("Chat list", [toggle("Flat chat list", "list.bullet", .newDesignFlatChatList, enabled: enabled)])
        ]

    case .settingsMenu:
        return [
            FaithgramSection("Hidden entries", [
                option(.hidePremiumUI, "star.slash"), option(.hideGifts, "gift"), option(.hideCurrencies, "star.circle"),
                option(.hideBoosts, "bolt"), option(.hideEmojiStatus, "face.smiling"), option(.disablePaidReactions, "heart.slash")
            ]),
            FaithgramSection("Effects", [option(.disablePremiumEffects, "sparkles"), option(.disableMonetizationConfig, "slider.horizontal.3")])
        ]

    case .rankColors:
        return [FaithgramSection([
            page("Owner", "crown", .choice(FaithgramChoices.rankOwner)),
            page("Admin", "star", .choice(FaithgramChoices.rankAdmin)),
            page("Member", "person", .choice(FaithgramChoices.rankMember))
        ], footer: "Colours for rank labels in group member lists and messages.")]

    case .misc:
        return [
            FaithgramSection([page("Stories", "circle.dashed", .stories), page("Calls", "phone", .calls)]),
            FaithgramSection("Downloads", [
                toggle("Download TikTok from link", "music.note", .downloadTikTok),
                page("Download type", "arrow.down.to.line", .choice(FaithgramChoices.downloadType)),
                toggle("Instant View for X post", "xmark", .instantViewX)
            ]),
            FaithgramSection("Whois", [toggle("Look up IP and domains", "server.rack", .whoisLookup)], footer: "Hold a link in a chat to look up its host. Lookups go to ipwho.is."),
            FaithgramSection("Calcmula", [
                toggle("Calculation suggestions", "plus.forwardslash.minus", .calcSuggestions),
                link("Show example usage", "eye") { env in env.info("Type an expression such as 12*(3+4) or 15% of 200 in the message field. A suggestion with the result appears above the keyboard; tap it to insert the answer.", title: "calcmula") }
            ], footer: "powered by @calcmulabot"),
            FaithgramSection("Whisper", [
                toggle("Whisper messages", "theatermasks", .whisperMessages),
                link("Show example usage", "eye") { env in env.info("Start a message with @sottovoxbot, mention the recipient and write the text. Only the mentioned person can open the whisper in a group.", title: "whisper") }
            ], footer: "powered by @sottovoxbot"),
            FaithgramSection("Boosts", [
                toggle("Upload Boost", "square.and.arrow.up", .uploadBoost),
                page("Download Boost", "square.and.arrow.down", .choice(FaithgramChoices.downloadBoost))
            ]),
            FaithgramSection("Translate messages", [
                page("Service", "character.book.closed", .choice(FaithgramChoices.translateService)),
                toggle("Quick Translate button", "character.book.closed", .quickTranslateButton),
                field("Translation language", "translationTarget", fallback: Locale.current.identifier.components(separatedBy: CharacterSet(charactersIn: "_-")).first ?? "en", message: "Language code, for example en, ru, de or es. iOS may ask to download a language model.")
            ]),
            FaithgramSection("Voice-to-text", [page("Service", "waveform", .choice(FaithgramChoices.voiceService))])
        ]

    case .stories:
        return [FaithgramSection([
            toggle("Hide Stories", "eye.slash", .hideStories),
            toggle("Disable Swipe to Record Story", "hand.draw", .disableStoryCamera),
            toggle("Warn before View", "exclamationmark.circle", .warnBeforeStoryView),
            toggle("Repost to Story", "arrowshape.turn.up.right", .repostToStory),
            toggle("Story Poster", "photo", .storyPoster)
        ], footer: "Hold the story button on your profile or in the chat list to slice one photo into a grid of stories that shows as a single image in your Posts.")]

    case .calls:
        return [FaithgramSection([
            toggle("Call Confirmation", "shield", .callConfirmation),
            toggle("Force TCP", "server.rack", .forceTCPCalls)
        ])]

    case .profiles:
        let profiles = FaithgramSettingsProfiles.all
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let rows = profiles.map { profile in
            link(profile.name, "square.stack", label: formatter.string(from: profile.createdAt)) { env in env.profileActions(profile) }
        }
        let explanation = "A profile stores the Faithgram switches under a name, so a whole configuration can be swapped in one tap. Call confirmation, gift confirmation and the protocol log are never part of a shared profile."
        return [
            FaithgramSection("Profiles", rows, footer: (rows.isEmpty ? "No profiles yet. Save your current settings to create one.\n\n" : "") + explanation),
            FaithgramSection("Actions", [
                link("Save current settings", "square.and.arrow.down", accent: true) { env in env.saveProfile() },
                link("Import from link", "link", accent: true) { env in env.importProfile() }
            ])
        ]

    case .privacy:
        return [
            FaithgramSection([
                link("Privacy profiles", "person.crop.rectangle.stack", label: FaithgramPrivacySettings.currentProfile) { env in env.choosePrivacyProfile() },
                FaithgramRow("Ghost mode", icon: "moon.fill", subtitle: "Offline status, no read receipts, no typing or upload indicators.", .ghost)
            ]),
            FaithgramSection("Controls", [
                option(.alwaysOffline, "moon"), option(.blockTyping, "keyboard"), option(.blockCloudReads, "checkmark.circle"), option(.localDrafts, "doc"),
                option(.hideAds, "megaphone"), option(.hideProxyPromo, "network"), option(.cleanLinks, "link"), option(.hideAppPreview, "rectangle.on.rectangle.slash")
            ]),
            FaithgramSection("Actions", [
                link("Save current controls as custom profile", "square.and.arrow.down") { env in FaithgramPrivacySettings.saveCustomProfile(); env.info("Custom privacy profile saved.") },
                link("Restore previous privacy controls", "arrow.uturn.backward") { env in env.info(FaithgramPrivacySettings.restorePreviousProfile() ? "Previous privacy controls restored." : "No previous profile to restore.") },
                link("Ghost mode in selected chats", "eye.slash", detail: "Long-press a message to enable Ghost for that chat. Rules apply to matching chats in all local accounts.") { env in env.info("Long-press a message and choose Ghost mode for this chat. The rule suppresses reads, typing and upload indicators for that peer across local accounts. Turning it off keeps global Ghost controls active. Telegram online status applies to the whole account.") },
                link("Lock now", "lock") { env in env.lockNow() },
                link("Passcode and Face ID", "faceid") { env in env.openPasscode() }
            ])
        ]

    case .gestures:
        return [
            FaithgramSection([option(.customGestures, "hand.draw")]),
            FaithgramSection("Three-finger swipes", [
                link("Three-finger swipe up", "arrow.up", label: gestureTitle(FaithgramPreferences.text("gesture.up", fallback: "profiles"))) { env in env.chooseGesture("gesture.up", title: "Three-finger swipe up") },
                link("Three-finger swipe down", "arrow.down", label: gestureTitle(FaithgramPreferences.text("gesture.down", fallback: "ghost"))) { env in env.chooseGesture("gesture.down", title: "Three-finger swipe down") }
            ], footer: "Use three fingers outside text editors. Home Screen quick actions wait for the app to unlock.")
        ]

    case .messageTools:
        return [
            FaithgramSection("Archive", [
                option(.saveDeletedMessages, "trash.slash"), option(.saveEditHistory, "clock.arrow.circlepath"), option(.archiveDownloadedMedia, "archivebox"), option(.disableTTL, "timer"),
                field("Deleted mark", "deletedMark", fallback: "🧹"), field("Edited mark", "editedMark", fallback: "🧹"),
                link("Message history", "clock.arrow.circlepath") { env in env.push(FaithgramHistoryController(context: env.context)) }
            ]),
            FaithgramSection("Filters", [
                option(.regexFilters, "line.3.horizontal.decrease.circle"), field("Regex rules", "regexRules", multiline: true),
                option(.hideBlockedMessages, "hand.raised"), option(.hidePinnedNotifications, "pin.slash")
            ]),
            FaithgramSection("Composer and content", [
                option(.formattingPanel, "bold.italic.underline"), option(.customFactCheck, "checkmark.shield"), field("Fact-check text", "factCheckText", multiline: true),
                option(.copyProtectedContent, "doc.on.doc"), option(.showCallbackData, "curlybraces"), option(.disableSensitiveBlur, "eye"),
                option(.moreRecentStickers, "face.smiling"), option(.openLinksWithoutWarning, "link")
            ]),
            FaithgramSection("Media saving", [
                link("Save media from private chats", "person") { env in env.push(saveIncomingMediaController(context: env.context, scope: .peerType(.privateChats))) },
                link("Save media from groups", "person.2") { env in env.push(saveIncomingMediaController(context: env.context, scope: .peerType(.groups))) },
                link("Save media from channels", "megaphone") { env in env.push(saveIncomingMediaController(context: env.context, scope: .peerType(.channels))) },
                link("Downloads and media quality", "arrow.down.circle") { env in env.push(dataAndStorageController(context: env.context)) }
            ])
        ]

    case .profileDisplay:
        return [FaithgramSection([option(.customProfile, "person.text.rectangle")]), FaithgramSection("Values", FaithgramVisualPreferences.profileFields.map { FaithgramRow($0.title, .visualField($0)) })]
    case .balances:
        return [FaithgramSection([option(.customBalances, "star.circle")]), FaithgramSection("Values", FaithgramVisualPreferences.balanceFields.map { FaithgramRow($0.title, .visualField($0)) })]
    case .giftDisplay:
        return [FaithgramSection([option(.spoofGifts, "gift")]), FaithgramSection("Values", FaithgramVisualPreferences.regularGiftFields.map { FaithgramRow($0.title, .visualField($0)) })]
    case .uniqueGifts:
        return [FaithgramSection([option(.spoofUniqueGifts, "sparkles"), option(.fakeGiftTransfer, "arrow.right.arrow.left")]), FaithgramSection("Values", FaithgramVisualPreferences.uniqueGiftFields.map { FaithgramRow($0.title, .visualField($0)) })]
    case .extraGifts:
        return [
            FaithgramSection([option(.showHiddenGifts, "gift.circle")]),
            FaithgramSection("Values", FaithgramVisualPreferences.hiddenGiftFields.map { FaithgramRow($0.title, .visualField($0)) } + [link("Gift catalog ids", "number") { env in env.showGiftCatalog() }])
        ]
    case .diagnostics:
        return [FaithgramSection([option(.protocolLogger, "doc.text.magnifyingglass"), link("View protocol log", "doc.text") { env in env.showProtocolLog() }])]
    case .backup:
        return [FaithgramSection([
            link("Export encrypted settings", "square.and.arrow.up", detail: "Password-protected Faithgram preferences and chat rules") { env in env.settingsBackup.exportSettings() },
            link("Restore encrypted settings", "square.and.arrow.down", detail: "Password-protected Faithgram preferences and chat rules") { env in env.settingsBackup.importSettings() }
        ])]

    case let .choice(choice):
        let derivedFlag: PatchClientOption? = choice.key == "translateService" ? .localTranslation : (choice.key == "voiceService" ? .localTranscription : nil)
        let selected = FaithgramChoices.values(choice)
        let rows = choice.options.map { item -> FaithgramRow in
            let checked = derivedFlag.map { on($0) == (item.value == "device") } ?? selected.contains(item.value)
            return FaithgramRow(item.title, .check(checked: checked, action: { _ in
                if let flag = derivedFlag { PatchClientPolicy.setEnabled(flag, item.value == "device") }
                FaithgramChoices.select(choice, item.value)
            }))
        }
        return [FaithgramSection(rows, footer: choice.footer)]

    case let .cover(field, own):
        let modes = FaithgramProfileCover.modes(field, ownProfile: own)
        let rows = FaithgramChoices.coverOptions.map { item in
            FaithgramRow(item.title, .check(checked: modes.contains(item.value), action: { _ in FaithgramProfileCover.select(field, ownProfile: own, option: item.value) }))
        }
        return [FaithgramSection(rows, footer: own ? "\"Full\" removes the row from your profile. \"Spoiler\" and \"Screen sharing\" cover the value and can be combined." : "\"Full\" removes the row from other people's profiles. \"Spoiler\" hides the value behind a tap and \"Screen sharing\" keeps it out of screenshots; those two can be combined.")]
    }
}

// MARK: - Environment actions

extension FaithgramSettingsEnvironment {
    func showActivityStatus() {
        let status = FaithgramPreferences.text("activityStatus", fallback: "Live Activities require iOS 16.2 or later.")
        let error = FaithgramPreferences.text("activityError")
        let alert = UIAlertController(title: "faithgram live activity", message: status + (error.isEmpty ? "" : "\n\n" + error), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Start or restart"), style: .default, handler: { _ in
            PatchClientPolicy.setEnabled(.dynamicIsland, true)
            NotificationCenter.default.post(name: FaithgramPreferences.restartLiveActivity, object: nil)
        }))
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("iOS settings"), style: .default, handler: { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }))
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Close"), style: .cancel))
        self.present(alert)
    }

    func choosePrivacyProfile() {
        let names = FaithgramPrivacySettings.profiles.filter { $0 != "custom" || UserDefaults.standard.data(forKey: "faithgram.privacy.custom") != nil }
        self.choose(title: "Privacy profiles", message: "Standard turns these privacy controls off. Quiet hides your phone, ads, pinned and mention notifications, cleans links and conceals the app preview. Ghost also suppresses online status, reads, typing, upload indicators and cloud drafts. Chat-specific Ghost rules remain active.", options: names.map { name in (name, { let _ = FaithgramPrivacySettings.applyProfile(name) }) })
    }

    func chooseGesture(_ key: String, title: String) {
        self.choose(title: title, message: "Use three fingers outside text editors. Home Screen quick actions wait for the app to unlock.", options: ["none", "profiles", "ghost", "lock", "cleanLinks"].map { value in (gestureTitle(value), { FaithgramPreferences.setText(key, value) }) })
    }

    func lockNow() {
        self.disposable.set((self.context.sharedContext.accountManager.transaction { $0.getAccessChallengeData() } |> deliverOnMainQueue).start(next: { [weak self] challenge in
            guard let self else { return }
            if case .none = challenge { self.openPasscode() } else { self.context.sharedContext.appLockContext.lock() }
        }))
    }

    func openPasscode() {
        self.disposable.set((passcodeOptionsAccessController(context: self.context, pushController: { [weak self] in self?.push($0) }, completion: { [weak self] success in
            if success, let self { self.push(passcodeOptionsController(context: self.context)) }
        }) |> deliverOnMainQueue).start(next: { [weak self] controller in if let controller { self?.push(controller) } }))
    }

    func showGiftCatalog() {
        self.disposable.set((self.context.engine.payments.cachedStarGifts() |> take(1) |> deliverOnMainQueue).start(next: { [weak self] gifts in
            guard let self else { return }
            let text = (gifts ?? []).map { gift -> String in
                switch gift {
                case let .generic(gift): return "\(gift.title ?? "Gift")\nid: \(gift.id)\ncustom emoji: \(gift.file.fileId.id)"
                case let .unique(gift): return "\(gift.title) #\(gift.number)\nid: \(gift.id)\nslug: \(gift.slug)"
                }
            }.joined(separator: "\n\n")
            self.push(FaithgramTextController(context: self.context, title: FaithgramPreferences.interfaceText("Gift catalog ids"), text: text.isEmpty ? "No cached gifts yet. Open the gift catalog first." : text, save: nil))
        }))
    }

    func showProtocolLog() {
        FaithgramProtocolLog.read { [weak self] result in
            guard let self else { return }
            let text: String
            switch result {
            case let .success(value): text = value.isEmpty ? "The protocol log is empty." : value
            case .failure: text = "The protocol log could not be decrypted."
            }
            self.push(FaithgramTextController(context: self.context, title: FaithgramPreferences.interfaceText("Protocol log"), text: text, save: nil))
        }
    }

    func saveProfile() {
        self.prompt(title: "Save current settings", message: "Give this configuration a name.", placeholder: "Profile name") { name in
            if FaithgramSettingsProfiles.saveCurrent(name: name) == nil {
                self.info("Enter a name of up to 48 characters. At most \(FaithgramSettingsProfiles.maximumCount) profiles can be stored.")
            }
        }
    }

    func importProfile() {
        let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.prompt(title: "Import from link", message: "Paste a faithgram://profile link shared from another device.", placeholder: "faithgram://profile?data=…", initial: pasted.hasPrefix(FaithgramSettingsProfiles.linkPrefix) ? pasted : "", confirm: "Import") { text in
            do {
                let profile = try FaithgramSettingsProfiles.profile(fromLink: text)
                if !FaithgramSettingsProfiles.importProfile(profile) { self.info("This profile could not be stored.") }
            } catch {
                self.info("The link is not a valid Faithgram profile.")
            }
        }
    }

    func profileActions(_ profile: FaithgramSettingsProfile) {
        let alert = UIAlertController(title: profile.name, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Apply"), style: .default, handler: { [weak self] _ in
            do { try FaithgramSettingsProfiles.apply(profile) } catch { self?.info("This profile could not be applied.") }
        }))
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Copy link"), style: .default, handler: { [weak self] _ in
            if let link = FaithgramSettingsProfiles.link(for: profile) { UIPasteboard.general.string = link; self?.info("The profile link was copied.") }
        }))
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Rename"), style: .default, handler: { [weak self] _ in
            self?.prompt(title: "Rename profile", initial: profile.name) { name in FaithgramSettingsProfiles.rename(id: profile.id, name: name) }
        }))
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Delete"), style: .destructive, handler: { _ in FaithgramSettingsProfiles.delete(id: profile.id) }))
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Cancel"), style: .cancel))
        if let popover = alert.popoverPresentationController, let view = self.controller?.view {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
        }
        self.present(alert)
    }
}

// MARK: - List entries

private enum FaithgramEntryKind: Equatable {
    case rootHeader, header, footer, toggle, disclosure, slider, check
}

private struct FaithgramEntry: ItemListNodeEntry {
    let stableId: Int32
    let section: ItemListSectionId
    let kind: FaithgramEntryKind
    let title: String
    let subtitle: String?
    let icon: String?
    let label: String?
    let detail: String?
    let value: Bool
    let enabled: Bool
    let accent: Bool
    let hasArrow: Bool
    let number: Int
    let lowerBound: Int
    let upperBound: Int
    let rowIndex: Int

    static func <(lhs: FaithgramEntry, rhs: FaithgramEntry) -> Bool { return lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! FaithgramArguments
        let text = FaithgramPreferences.interfaceText
        let theme = presentationData.theme
        let rowIndex = self.rowIndex
        switch self.kind {
        case .rootHeader:
            return FaithgramHeaderItem(theme: theme, title: self.title, subtitle: self.subtitle ?? "", sectionId: self.section)
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text(self.title), sectionId: self.section)
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain(text(self.title)), sectionId: self.section)
        case .toggle:
            let icon = self.icon.flatMap { faithgramIcon($0, color: theme.list.itemPrimaryTextColor) }
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: icon, title: text(self.title), text: self.subtitle.map(text), value: self.value, enabled: self.enabled, maximumNumberOfLines: 2, sectionId: self.section, style: .blocks, updated: { value in arguments.toggle(rowIndex, value) })
        case .disclosure:
            let icon = self.icon.flatMap { faithgramIcon($0, color: self.accent ? theme.list.itemAccentColor : theme.list.itemPrimaryTextColor) }
            let label = self.detail ?? self.label ?? ""
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: icon, title: text(self.title), enabled: self.enabled, titleColor: self.accent ? .accent : .primary, label: text(label), labelStyle: self.detail != nil ? .multilineDetailText : .text, sectionId: self.section, style: .blocks, disclosureStyle: self.hasArrow ? .arrow : .none, action: { arguments.perform(rowIndex) })
        case .slider:
            return FaithgramSliderItem(theme: theme, title: text(self.title), value: self.number, minimumValue: self.lowerBound, maximumValue: self.upperBound, sectionId: self.section, updated: { value in arguments.number(rowIndex, value) })
        case .check:
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: text(self.title), style: .right, checked: self.value, zeroSeparatorInsets: false, sectionId: self.section, action: { arguments.perform(rowIndex) })
        }
    }
}

private final class FaithgramArguments {
    let env: FaithgramSettingsEnvironment
    let rows: [FaithgramRow]

    init(env: FaithgramSettingsEnvironment, rows: [FaithgramRow]) {
        self.env = env
        self.rows = rows
    }

    func toggle(_ index: Int, _ value: Bool) {
        guard index < self.rows.count else { return }
        switch self.rows[index].kind {
        case let .toggle(option):
            PatchClientPolicy.setEnabled(option, value)
            if option == .alwaysOffline, value { let _ = self.env.context.account.network.request(Api.functions.account.updateStatus(offline: .boolTrue)).startStandalone() }
        case .ghost:
            FaithgramPreferences.setGhostMode(value)
            if value { let _ = self.env.context.account.network.request(Api.functions.account.updateStatus(offline: .boolTrue)).startStandalone() }
        default:
            break
        }
    }

    func number(_ index: Int, _ value: Int) {
        guard index < self.rows.count, case let .slider(key, _, range) = self.rows[index].kind else { return }
        FaithgramPreferences.setText(key, String(min(max(value, range.lowerBound), range.upperBound)))
    }

    func perform(_ index: Int) {
        guard index < self.rows.count else { return }
        let row = self.rows[index]
        switch row.kind {
        case let .screen(screen): self.env.open(screen)
        case let .disclosure(_, _, _, action): action(self.env)
        case let .button(_, action): action(self.env)
        case let .check(_, action): action(self.env)
        case let .text(key, fallback, multiline, message): self.env.editText(title: row.title, key: key, fallback: fallback, multiline: multiline, message: message)
        case let .visualField(field): self.env.editVisualField(field)
        case .toggle, .ghost, .slider: break
        }
    }
}

private func faithgramEntries(screen: FaithgramScreen, env: FaithgramSettingsEnvironment) -> ([FaithgramEntry], [FaithgramRow]) {
    var entries: [FaithgramEntry] = []
    var rows: [FaithgramRow] = []
    var section: ItemListSectionId = 0
    func make(_ kind: FaithgramEntryKind, title: String, subtitle: String? = nil, icon: String? = nil, label: String? = nil, detail: String? = nil, value: Bool = false, enabled: Bool = true, accent: Bool = false, hasArrow: Bool = true, number: Int = 0, range: ClosedRange<Int> = 0...0, rowIndex: Int = -1) {
        entries.append(FaithgramEntry(stableId: Int32(entries.count), section: section, kind: kind, title: title, subtitle: subtitle, icon: icon, label: label, detail: detail, value: value, enabled: enabled, accent: accent, hasArrow: hasArrow, number: number, lowerBound: range.lowerBound, upperBound: range.upperBound, rowIndex: rowIndex))
    }
    if screen == .root {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        make(.rootHeader, title: "faithgram", subtitle: "\(appVersion) (\(build))")
        section += 1
    }
    for block in faithgramSections(for: screen, env: env) {
        if let header = block.header { make(.header, title: header) }
        for row in block.rows {
            rows.append(row)
            let index = rows.count - 1
            switch row.kind {
            case let .toggle(option):
                make(.toggle, title: row.title, subtitle: row.subtitle, icon: row.icon, value: PatchClientPolicy.isEnabled(option), enabled: row.enabled, rowIndex: index)
            case .ghost:
                make(.toggle, title: row.title, subtitle: row.subtitle, icon: row.icon, value: FaithgramPreferences.ghostMode, enabled: row.enabled, rowIndex: index)
            case let .screen(target):
                var detail: String?
                var label: String?
                switch target {
                case let .cover(field, own): detail = FaithgramProfileCover.label(field, ownProfile: own)
                case let .choice(choice):
                    if choice.key == "translateService" { label = PatchClientPolicy.isEnabled(.localTranslation) ? "On-device (Apple)" : "Telegram" }
                    else if choice.key == "voiceService" { label = PatchClientPolicy.isEnabled(.localTranscription) ? "On-device (Apple)" : "Telegram" }
                    else if choice.multiple { detail = FaithgramChoices.label(choice) }
                    else { label = FaithgramChoices.label(choice) }
                default: break
                }
                make(.disclosure, title: row.title, icon: row.icon, label: label, detail: detail, enabled: row.enabled, rowIndex: index)
            case let .disclosure(label, detail, accent, _):
                make(.disclosure, title: row.title, icon: row.icon, label: label, detail: detail, enabled: row.enabled, accent: accent, hasArrow: !(accent && label == nil && detail == nil && !row.title.hasPrefix("Import")), rowIndex: index)
            case let .button(destructive, _):
                make(.disclosure, title: row.title, icon: row.icon, enabled: row.enabled, accent: !destructive, hasArrow: false, rowIndex: index)
            case let .slider(key, fallback, range):
                make(.slider, title: row.title, number: Int(FaithgramPreferences.text(key)) ?? fallback, range: range, rowIndex: index)
            case let .text(key, fallback, _, _):
                let value = FaithgramPreferences.text(key, fallback: fallback)
                make(.disclosure, title: row.title, icon: row.icon, label: value.isEmpty ? "Not set" : value, enabled: row.enabled, rowIndex: index)
            case let .visualField(field):
                let value = FaithgramVisualPreferences.value(field.key, fallback: field.fallback)
                make(.disclosure, title: row.title, icon: row.icon, label: value.isEmpty ? "Not set" : value, enabled: row.enabled, rowIndex: index)
            case let .check(checked, _):
                make(.check, title: row.title, value: checked, enabled: row.enabled, rowIndex: index)
            }
        }
        if let footer = block.footer { make(.footer, title: footer) }
        section += 1
    }
    return (entries, rows)
}

// MARK: - Controller

func faithgramScreenController(context: AccountContext, screen: FaithgramScreen) -> ViewController {
    let env = FaithgramSettingsEnvironment(context: context)
    let signal = combineLatest(context.sharedContext.presentationData, faithgramSettingsChanges())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let (entries, rows) = faithgramEntries(screen: screen, env: env)
        let arguments = FaithgramArguments(env: env, rows: rows)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(FaithgramPreferences.interfaceText(screen.title)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    env.controller = controller
    return controller
}

public func patchClientSettingsController(context: AccountContext) -> ViewController {
    return faithgramScreenController(context: context, screen: .root)
}
