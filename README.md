# faithgram

A personal Telegram client for iPhone, based on Telegram-iOS 12.9.2.

## Status

The source patch adds seven settings: offline status, typing activity, cloud read receipts, local drafts, phone privacy when adding contacts, channel ads, and proxy promotions. All settings are off by default.

The latest unsigned iPhone build passed on October 6, 2026. All eight Swift tests passed: five request-policy checks against the pinned Telegram API serializers and three storage checks. The full app, including the settings screen and startup changes, compiled with Xcode 26.2.

[Build #5](https://github.com/damage/faithgram/actions/runs/37505486298) produced the `Faithgram-unsigned` artifact. The previous build stopped during a BrowserStack launch because its signature lacked the App Group entitlement. Startup now falls back to the private app container and creates the database directory before writing its key. A BrowserStack retest of this build is pending. Device traffic checks remain untested. The seven settings above are the current prototype; the remaining planned features are listed in `manifest.json`.

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
