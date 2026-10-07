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
- Developer, beta tester, paid subscriber and verified badges, with explanations on tap and support for multiple roles.
- Instant passcode lock, theme and sticker controls, media quality and notification settings.
- An optional Faithgram Live Activity with the app icon. iOS controls Dynamic Island visibility and duration.

Options are off by default. History starts after it is enabled and this device receives an edit or deletion; it cannot recover messages never received. Downloaded archive files are limited to 256 MB each. Secret chats and disappearing media are excluded from the archive. Local translation and transcription do not fall back to Telegram or an external translation service while the corresponding device-only option is enabled.

## Local display tools

Profile controls include custom phone and user id labels, regular and collectible usernames, collectible purchase details, an attached channel, selected-peer verification and bot verification, rating levels, and a local frozen-account state. Stars and nanoTON overrides change displayed balances. The original server identity, authorization, ownership and payment amounts stay intact.

Gift controls can change regular gift details or display them as unique gifts, including the model, symbol, backdrop, rarity, supply, owner, host, resale and valuation fields. Target them at your profile, all profiles, or everyone except you. Extra catalog entries use matching Telegram gift and custom emoji ids. The catalog-id viewer and unique-gift copy action help identify existing assets. Fake transfer creates a local service-message preview without opening a payment form or issuing a transfer request; the preview is removed on the next process launch.

Message tools include custom fact-check text for channel messages, copying protected content, local expiry control, long-press callback-data inspection, sensitive-content and spoiler controls, 200 recent stickers, direct link opening and blocked-author filters. Monetization switches cover premium purchase UI, gifts, paid reactions, emoji statuses and effects, currencies, boosts and app configuration. Server permissions still apply to read statistics and premium actions.

The optional decoded API log records client requests, responses and errors in an encrypted local rolling store. It is off by default.

## Badge registry

Only the active account with peer id 1000 can open the badge administration screen. It supports search, active/revoked/expired views, issue dates, private notes, validity periods, profile opening and revocation. Existing local grants retain an unknown issue date rather than an invented timestamp.

`badge-service/` contains the shared SQLite registry. Clients verify public snapshots with a bundled Ed25519 public key. Admin writes require a private access token stored in device Keychain. Private notes and revoked records are omitted from the public snapshot. The endpoint and public key in `assets/FaithgramBadgeService.json` are currently empty: server deployment and configuration are still pending. Until configured, grants remain local to this installation. The owner has a bundled developer badge.

The registry refreshes in the foreground. A verified cache remains usable for up to seven days offline, so revocation is visible after a client refreshes. See the service README for deployment and credentials.

## Status

Current changes fix category alignment, add owner-only badge administration and tappable badge explanations, replace welcome-screen branding, and add Live Activity status and restart controls. Their full iPhone build is pending. The badge service passed seven local tests covering authorization, signed snapshots, persistence, multiple roles, expiry and revocation.

[Build 11](https://github.com/damage/faithgram/actions/runs/37643635225) passed the full Xcode 26.2 iPhone build, 21 Swift tests, syntax checks for 96 modified Swift files, and the generated Objective-C lowercase test. The unsigned IPA includes the Faithgram icon and Live Activity extension. The complete workflow took 9 minutes 46 seconds with the dependency cache.

Build 11 has not been tested on an iPhone. The owner previously confirmed installation with Sideloadly and app launch on iOS 26.6.1 for build 5; that startup result does not validate the new functions. Runtime checks are still needed for ghost mode traffic, archives, translation, badges and UI layout.

## Build

Run **Actions → Faithgram iOS build → Run workflow**. The workflow uses a macOS Apple Silicon runner with Xcode 26.2, so it can be started from Windows. Download the `Faithgram-unsigned` artifact after a successful run, then sign and install its `.ipa` with Sideloadly or another personal signing tool.

`TELEGRAM_API_ID` and `TELEGRAM_API_HASH` belong in repository Actions secrets. The workflow needs no Apple signing credentials or Telegram sessions. Only the Faithgram Live Activity extension is embedded in the sideload build; push-notification, share, Siri and Watch extensions are omitted.

## Local data

History uses authenticated AES-GCM encryption with device Keychain keys. Session exports contain account authorization keys and are encrypted with a password-derived key. Keep the backup and its password separately. Revoked Telegram sessions require a new login, and an expired session cannot be revived by a backup.

Cloud chats retain Telegram's normal server-side storage. These controls reduce activity reports; they do not conceal an account, IP address or sent messages from Telegram. Faithgram does not initialize the optional upstream crash analytics service.

## Source

`manifest.json` pins upstream, the source patch and icon checksums. `scripts/prepare.py` applies the patch and copies verified assets. `scripts/policy_tests.py` tests the actual Telegram API serializers, local persistence, encryption and generated UI strings. `scripts/build.py` builds and checks the unsigned IPA. Upstream source and licenses are fetched from the pinned Telegram-iOS revision.
