# faithgram

A personal Telegram client for iPhone, based on Telegram-iOS 12.9.2.

## Status

The source patch adds seven settings: offline status, typing activity, cloud read receipts, local drafts, phone privacy when adding contacts, channel ads, and proxy promotions. All settings are off by default.

This is an early source build. The patch applies cleanly to the pinned upstream revision. Swift compilation, IPA signing, and device testing have not been completed.

## Build

The **Faithgram iOS build** workflow runs on macOS with Xcode 26.2. You can start it from Windows.

1. Create an application at [my.telegram.org/apps](https://my.telegram.org/apps).
2. Add `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` to the repository's **Settings → Secrets and variables → Actions**.
3. Open **Actions → Faithgram iOS build → Run workflow**.
4. After a successful build, download `Faithgram-unsigned.ipa` from the `Faithgram-unsigned` artifact.
5. Sign and install the IPA with [Sideloadly](https://sideloadly.io/) or another personal signing tool.

The initial build excludes app extensions, push notifications, Siri, iCloud, and Watch support. Installation on iOS 26.6.1 has not been tested.

## Source

`manifest.json` pins the upstream revision and patch checksum. `scripts/prepare.py` downloads the source and applies the patch. `scripts/policy_tests.py` tests request handling against the actual Telegram API serializers. `scripts/build.py` builds the unsigned IPA.

API credentials belong in repository secrets. Telegram session data and Apple signing credentials are not used by the build workflow.

## Privacy

These settings do not hide your account from Telegram or add end-to-end encryption to cloud chats. Disabling activity reports, read receipts, or ads conflicts with the [Telegram API terms](https://core.telegram.org/api/terms).

Telegram-iOS source code and its licenses are fetched from the pinned upstream repository during preparation.
