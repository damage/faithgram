# faithgram

personal telegram client for iphone. i made it for myself, but a few people asked me to share it, so here it is. still working on it.

based on telegram-ios 12.9.2. everything lives in one patch on top of the official source.

## what it does

settings open from a "faithgram" row above my profile.

**accounts**
- unlimited accounts
- profile id, data center and mutual contact rows in profiles
- hide phone, id and usernames in your own profile or in other people's profiles: remove the row or cover it with a spoiler
- online alerts: get a notification when a chosen contact comes online
- password-protected export and restore of logged-in sessions

**messages**
- ghost mode: offline status, no read receipts, no typing or upload indicators. can be turned on per chat from the message menu
- deleted and edited messages are kept locally, with marks on the message
- downloaded media archive with per-chat rules
- regex filters for messages, chat previews and notifications
- shot: select messages and copy a picture of them to the clipboard
- seconds in message timestamps, original date of forwarded messages
- message info: ids, dates, views, file details
- double-tap to edit your own message, swipe to reply can be turned off
- reactions can be hidden, reaction and mention notifications can be muted
- spoilers in text and media can be shown right away, deletion effects can be turned off
- post as your channel by default, send photos in hd by default
- voice or round video on the record button, or both
- context menu editor: turn off any item in the message menu and in the sticker menu, plus copy sticker id
- formatting toolbar and quick translate button above the keyboard
- on-device translation and voice transcription when the language is supported
- calculator in the input field: type 12*(3+4)= and the result appears
- whisper to someone in a group through @sottovoxbot
- custom fact-check text, copy protected content, no local expiry, callback data on long press, 200 recent stickers, no link warnings

**gifts**
- send a gift several times in a row, pick the amount from a grid or type it
- choose several recipients at once
- search the gift catalog by name, price, id or number
- gift manager: show, hide, pin and unpin all your gifts from one list
- skip the upgrade animation, show gift ids, copy an embed code
- ask for the cloud password before paid gift actions
- local overrides for your profile, balances, regular and unique gifts, extra catalog entries, fake transfer preview
- switches to hide premium, stars, gifts, boosts, paid reactions and emoji statuses

**appearance**
- tabs: hide contacts, show calls, hide names, hide the whole bar (three-finger swipe up brings it back), pick which tabs show badges
- folders at the bottom, hide all chats, rename all chats, hide folder badges, remember the last folder
- sticker size and sticker timestamps, hide suggested reactions, hide the ai button in the input
- round videos: start with the rear camera, lock the camera, 60 fps, 0.5x, keep music playing
- camera tile and live preview in the gallery can be turned off
- pull to next unread channel or topic can be turned off
- fix invisible names, rank colors for owner, admin and member labels
- lowercase interface (names, messages and links stay as they are)
- live activity and an island badge with the app name
- local premium look

**privacy**
- privacy profiles: standard, quiet, ghost, custom
- tracking parameters are stripped from outgoing links
- app switcher preview cover
- three-finger gestures and home screen shortcuts for profiles, ghost and lock
- encrypted settings backup, named settings profiles with shareable links

**misc**
- stories: hide them, no swipe to record, ask before viewing, repost to story
- calls: ask before calling, force tcp
- links: look up the host, download a tiktok video, open x posts with a preview
- upload boost and download boost
- translation and voice-to-text through telegram or on the device

still being wired up: gift cart, wide tab bar, recording microphone, voice pitch, round video hd, new and old design, story poster, joined date, screen-sharing cover.

## build

actions → faithgram ios build → run workflow. it needs `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` in the repository secrets. download the `Faithgram-unsigned` artifact and sign it with sideloadly or whatever you use. no apple developer account needed.

the build is pinned to xcode 26.2. only the live activity extension is included, push and share extensions are not.

## notes

all of this is local. telegram still sees your account, ip and sent messages like before, it just gets fewer activity reports. secret chats and disappearing media are not archived. the message archive only keeps what this device received after you turned it on.

## source

- `patches/` — the patch over telegram-ios
- `source/` — readable copies of the added files
- `scripts/` — prepare, test and build
- `tests/` — swift tests for the core parts
- `manifest.json` — pinned upstream revision and checksums
