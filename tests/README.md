# Tests

Run `python3 scripts/policy_tests.py` on macOS. The tests use the pinned Telegram API serializers.

Badge tests cover owner permissions, multiple roles, issue dates, revocation history, expiry, and Ed25519 snapshot verification. The signature fixture is signed by the Python service and checked by Apple's CryptoKit. Tests reject modified payloads, wrong keys, revision rollback and expired caches.

Run `python -m unittest -v test_server.py` from `badge-service/` to test the server's protected API, persistence and signing. These tests create temporary credentials and do not use production keys.

Privacy tests exercise profile restoration and the actual user, group, channel and encrypted-chat RPC descriptions. They check namespace separation, negative secret-chat ids and the precedence of global controls.

Link tests cover signed URLs, useful query parameters, excluded code ranges and UTF-16 offsets with emoji and multiple replacements. Settings tests cover encrypted round trips, credential exclusion, wrong passwords, tampering, separate session envelopes and validation before mutation.

## iPhone checks

- Sign the current IPA with its Live Activity extension retained. Open Appearance → Live Activity status to inspect iOS permissions, extension presence and any start error.
- Open Faithgram settings and a profile with developer and beta badges. Check category alignment, icon, lowercase title and each badge explanation. Check that a different account cannot open badge administration.
- Apply Quiet and Ghost profiles, save Custom, and restore the previous controls. Switch away from the app and check that its preview is covered when enabled.
- Enable Ghost for one chat from a message menu. Observe reads and typing from a second account, then compare another chat with no rule. Test global Ghost separately; online status applies to the whole account.
- Send tracking links to Saved Messages with emoji, formatting, hidden links and a media caption. Check useful parameters, signed links and code snippets.
- Assign the three-finger gestures, use them outside the editor, and test Home Screen shortcuts with the app locked.
- Export settings, change several controls, then import the backup. Verify restoration and wrong-password rejection; Telegram sessions and badge data should remain intact.
