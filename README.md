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

`badge-service/` contains the shared SQLite registry deployed at https://badges.faithgram.xyz. Clients verify public snapshots with the Ed25519 public key pinned in `assets/FaithgramBadgeService.json`. Admin writes require a private access token stored in device Keychain. Private notes and revoked records are omitted from the public snapshot. The owner has a developer badge in the shared registry. Existing local grants are not automatically uploaded; new grants use the shared service after the owner enters the administrator key.

The registry refreshes in the foreground. A verified cache remains usable for up to seven days offline, so revocation is visible after a client refreshes. See the service README for deployment and credentials.

## Privacy, gestures and settings

Privacy profiles group the activity, read, draft, phone, advertising, notification, link-cleaning and app-preview controls. Standard turns these controls off; Quiet enables local privacy and clutter controls; Ghost enables all of them. Save the current controls as Custom, or restore the controls used immediately before the last profile change. Profiles leave appearance, archives, accounts and chat-specific rules intact.

Long-press a message to toggle Ghost for that chat. The rule suppresses read receipts, story-view reports, typing, recording and upload indicators for the selected peer. Rules apply to matching peer ids across all local accounts. Global controls remain effective when a chat rule is disabled. Online presence belongs to the whole Telegram account and cannot be hidden independently for one chat. Secret-chat read-content actions use an encrypted no-op to preserve service sequence numbers; legacy layer 8 has no sequence counter and the receipt is completed locally.

Link cleaning runs when normal outgoing messages and media captions enter the send queue, including hidden text links and rich-message links. It removes known tracking parameters such as `utm_*`, `fbclid` and `gclid`, preserves other parameters and fragments, and leaves signed URLs and code entities unchanged. Forwarded server messages keep their original contents. This is parameter cleanup, not protection from the destination website.

The app-preview switch covers the app window when it becomes inactive. It conceals the app-switcher thumbnail; it does not disable screenshots or screen recording.

Gestures settings enable three-finger swipes outside text editors. Assign each direction to the privacy-profile picker, Ghost toggle, lock, link-cleaning toggle, or no action. The same switch adds privacy and Ghost shortcuts to the Home Screen icon. Quick actions wait for the app to unlock. A lock gesture requires an existing app passcode.

Settings exports use a separate `faithgram.settings` envelope, AES-GCM and PBKDF2-HMAC-SHA256 with 600,000 rounds. Import validates every field before replacing the allowed Faithgram preferences. The backup includes profiles, chat rules, gestures and local display preferences; it excludes Telegram sessions, badge records, admin credentials and message archives. Sessions have their own export in Accounts.

## Status

[Build 16](https://github.com/damage/faithgram/actions/runs/37686555347) passed the full Xcode 26.2 iPhone build, 38 Swift tests, syntax checks for 110 modified Swift files and the generated Objective-C lowercase test. It includes the badge and branding fixes, Live Activity diagnostics, privacy profiles, chat-specific Ghost rules, outgoing link cleanup, app-preview cover, gestures and encrypted settings backup.

The unsigned IPA contains the Faithgram Live Activity extension. Current UI and network behavior still require device testing. The owner previously confirmed Sideloadly installation and app launch on iOS 26.6.1 for build 5; that does not validate later changes. The shared badge registry is available at https://badges.faithgram.xyz. Its HTTPS endpoint, signed public list and administrator access were verified; the app includes the pinned public verification key.

## Build

Run **Actions → Faithgram iOS build → Run workflow**. The workflow uses a macOS Apple Silicon runner with Xcode 26.2, so it can be started from Windows. Download the `Faithgram-unsigned` artifact after a successful run, then sign and install its `.ipa` with Sideloadly or another personal signing tool.

`TELEGRAM_API_ID` and `TELEGRAM_API_HASH` belong in repository Actions secrets. The workflow needs no Apple signing credentials or Telegram sessions. Only the Faithgram Live Activity extension is embedded in the sideload build; push-notification, share, Siri and Watch extensions are omitted.

## Local data

History uses authenticated AES-GCM encryption with device Keychain keys. Session exports contain account authorization keys and are encrypted with a password-derived key. Keep the backup and its password separately. Revoked Telegram sessions require a new login, and an expired session cannot be revived by a backup.

Cloud chats retain Telegram's normal server-side storage. These controls reduce activity reports; they do not conceal an account, IP address or sent messages from Telegram. Faithgram does not initialize the optional upstream crash analytics service.

## Source

`manifest.json` pins upstream, the source patch and icon checksums. `scripts/prepare.py` applies the patch and copies verified assets. `scripts/policy_tests.py` tests the actual Telegram API serializers, local persistence, encryption and generated UI strings. `scripts/build.py` builds and checks the unsigned IPA. Upstream source and licenses are fetched from the pinned Telegram-iOS revision.
