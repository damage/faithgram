# Tests

Run `python3 scripts/policy_tests.py` on macOS. The tests use the pinned Telegram API serializers.

Badge tests cover owner permissions, multiple roles, issue dates, revocation history, expiry, and Ed25519 snapshot verification. The signature fixture is signed by the Python service and checked by Apple's CryptoKit. Tests reject modified payloads, wrong keys, revision rollback and expired caches.

Run `python -m unittest -v test_server.py` from `badge-service/` to test the server's protected API, persistence and signing. These tests create temporary credentials and do not use production keys.
