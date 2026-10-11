# faithgram

personal telegram client for iphone. i made it for myself, but a few people asked me to share it, so here it is. still working on it.

based on telegram-ios 12.9.2. everything lives in one patch on top of the official source.

## what it does

settings open from a "faithgram" row above my profile.

**accounts**
- unlimited accounts
- profile id, data center and mutual contact rows in profiles
- hide phone, id and usernames in your own profile or in other people's profiles
- password-protected export and restore of logged-in sessions

**messages**
- ghost mode: offline status, no read receipts, no typing or upload indicators. can be turned on per chat from the message menu
- deleted and edited messages are kept locally, with marks on the message
- downloaded media archive with per-chat rules
- regex filters for messages, chat previews and notifications
- shot: select messages and copy a picture of them to the clipboard
- seconds in message timestamps
- reaction and mention notification filters
- context menu editor: turn off any item in the message menu and in the sticker menu, plus copy sticker id
- formatting toolbar and quick translate button above the keyboard
- on-device translation and voice transcription when the language is supported
- custom fact-check text, copy protected content, no local expiry, callback data on long press, 200 recent stickers, no link warnings, no spoilers

**gifts and profile**
- local overrides for your profile: phone, id, usernames, collectibles, verification, rating, balances
- local overrides for regular and unique gifts, extra catalog entries, fake transfer preview
- switches to hide premium, stars, gifts, boosts, paid reactions and emoji statuses

**appearance**
- folders at the bottom, hide all chats, remember the last folder
- lowercase interface (names, messages and links stay as they are)
- live activity with the app name in the dynamic island
- local premium look

**privacy**
- privacy profiles: standard, quiet, ghost, custom
- tracking parameters are stripped from outgoing links
- app switcher preview cover
- three-finger gestures and home screen shortcuts for profiles, ghost and lock
- encrypted settings backup, named settings profiles with shareable links

a lot of the newer switches in gifts, appearance and misc are still being wired up.

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
