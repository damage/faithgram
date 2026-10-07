# faithgram

A personal Telegram client for iPhone, based on Telegram-iOS 12.9.2.

## Features

Faithgram settings sit above My Profile and open a categorized settings screen. The app uses a black icon with a white mark.

- Interface-only lowercase, leaving names, messages, links and drafts unchanged.
- Unlimited local accounts and password-protected backups of active Telegram sessions.
- Ghost mode: offline status, suppressed read receipts, typing, recording and upload indicators.
- Independent encrypted history for deleted cloud messages and previous edits, with configurable marks.
- Downloaded media archives, per-chat archive rules, and photo/video autosave exceptions.
- Local regex filters for messages, chat previews and in-app notifications.
- A formatting toolbar and a translation button above the keyboard.
- Apple on-device voice transcription and chat translation where the device and language support them.
- Story-strip and camera-swipe controls; folder placement, All Chats visibility and last-folder restoration.
- Pinned-message and mention notification filters.
- Locally assigned developer, beta tester and verified badges, plus a cosmetic premium star.
- Instant passcode lock, theme and sticker controls, media quality and notification settings.
- An optional Faithgram Live Activity with the app icon. iOS controls Dynamic Island visibility and duration.

Options are off by default. History starts after it is enabled and this device receives an edit or deletion; it cannot recover messages never received. Downloaded archive files are limited to 256 MB each. Secret chats and disappearing media are excluded from the archive. Local translation and transcription do not fall back to Telegram or an external translation service while the corresponding device-only option is enabled.

## Status

The new feature set is awaiting compilation and device testing. The previous [build 5](https://github.com/damage/faithgram/actions/runs/37505486298) passed eight Swift tests and the full Xcode 26.2 build. The owner confirmed installation with Sideloadly and app launch on iOS 26.6.1. That result covers the previous build only.

## Build

Run **Actions → Faithgram iOS build → Run workflow**. The workflow uses a macOS Apple Silicon runner with Xcode 26.2, so it can be started from Windows. Download the `Faithgram-unsigned` artifact after a successful run, then sign and install its `.ipa` with Sideloadly or another personal signing tool.

`TELEGRAM_API_ID` and `TELEGRAM_API_HASH` belong in repository Actions secrets. The workflow needs no Apple signing credentials or Telegram sessions. Only the Faithgram Live Activity extension is embedded in the sideload build; push-notification, share, Siri and Watch extensions are omitted.

## Local data

History uses authenticated AES-GCM encryption with device Keychain keys. Session exports contain account authorization keys and are encrypted with a password-derived key. Keep the backup and its password separately. Revoked Telegram sessions require a new login, and an expired session cannot be revived by a backup.

Cloud chats retain Telegram's normal server-side storage. These controls reduce activity reports; they do not conceal an account, IP address or sent messages from Telegram. Faithgram does not initialize the optional upstream crash analytics service.

## Source

`manifest.json` pins upstream, the source patch and icon checksums. `scripts/prepare.py` applies the patch and copies verified assets. `scripts/policy_tests.py` tests the actual Telegram API serializers, local persistence, encryption and generated UI strings. `scripts/build.py` builds and checks the unsigned IPA. Upstream source and licenses are fetched from the pinned Telegram-iOS revision.
