# faithgram source

The source patch contains all changes against the pinned Telegram-iOS revision. This directory mirrors Faithgram's core helpers and settings controllers for convenient reading. Native Telegram UI integrations, string generation, the Live Activity extension and build definitions are included in the patch.

See manifest.json for checksums and validation status. Build 11 passed the full iPhone build and 21 Swift tests. The current branding, badge administration and Live Activity fixes await a new build. Shared badges also require deployment of badge-service/ and configuration of its HTTPS endpoint and public signing key. Device testing remains separate from compilation.
