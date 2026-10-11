import base64
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from server import Registry, handler


class RegistryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.registry = Registry(Path(self.directory.name), initialize=True, owner=1000)
    def tearDown(self):
        self.directory.cleanup()
    def test_owner_and_private_token_are_both_required(self):
        token = (Path(self.directory.name) / 'admin-token').read_text()
        self.assertFalse(self.registry.authorize(token, '999', 'local'))
        self.assertFalse(self.registry.authorize('incorrect', '1000', 'local'))
        self.assertTrue(self.registry.authorize(token, '1000', 'local'))
    def test_signature_detects_payload_changes(self):
        envelope = self.registry.snapshot()
        payload, signature = base64.b64decode(envelope['payload']), base64.b64decode(envelope['signature'])
        key = Ed25519PublicKey.from_public_bytes(base64.b64decode(self.registry.public_key))
        key.verify(signature, payload)
        with self.assertRaises(InvalidSignature): key.verify(signature, payload + b' ')
    def test_multiple_roles_revocation_and_private_notes(self):
        first = self.registry.grant({'peerId': 98765, 'role': 'betaTester', 'note': 'private admin note'})['id']
        self.registry.grant({'peerId': 98765, 'role': 'paidSubscriber'})
        public = json.loads(base64.b64decode(self.registry.snapshot()['payload']))
        self.assertEqual(len([g for g in public['grants'] if g['peerId'] == 98765]), 2)
        self.assertTrue(all(g['note'] == '' for g in public['grants']))
        self.assertEqual(next(g for g in self.registry.admin_records()['grants'] if g['id'] == first)['note'], 'private admin note')
        self.registry.revoke(first)
        public = json.loads(base64.b64decode(self.registry.snapshot()['payload']))
        self.assertEqual([g['role'] for g in public['grants'] if g['peerId'] == 98765], ['paidSubscriber'])
        self.assertTrue(next(g for g in self.registry.admin_records()['grants'] if g['id'] == first)['revokedAt'])
        self.assertEqual(self.registry.admin_records()['audit'][0]['action'], 'revoke')
    def test_update_preserves_issue_date_and_expiry_filters(self):
        with patch('server.time.time', return_value=1700000000):
            first = self.registry.grant({'peerId': 98765, 'role': 'betaTester', 'expiresAt': 1700000060})['id']
        with patch('server.time.time', return_value=1700000010):
            second = self.registry.grant({'peerId': 98765, 'role': 'betaTester', 'expiresAt': 1700000060, 'note': 'updated'})['id']
            self.assertEqual(first, second)
            self.assertEqual(next(g for g in self.registry.admin_records()['grants'] if g['id'] == first)['issuedAt'], 1700000000)
        with patch('server.time.time', return_value=1700000060):
            public = json.loads(base64.b64decode(self.registry.snapshot()['payload']))
            self.assertFalse(any(g['peerId'] == 98765 for g in public['grants']))
    def test_restart_keeps_identity_records_and_revision(self):
        self.registry.grant({'peerId': 98765, 'role': 'verified'})
        before = json.loads(base64.b64decode(self.registry.snapshot()['payload']))
        restarted = Registry(Path(self.directory.name), initialize=True, owner=1000)
        self.assertEqual(restarted.public_key, self.registry.public_key)
        after = json.loads(base64.b64decode(restarted.snapshot()['payload']))
        self.assertEqual(before['revision'], after['revision'])
        self.assertEqual(before['grants'], after['grants'])
    def test_invalid_grant_is_not_saved(self):
        for body in [{'peerId': 0, 'role': 'verified'}, {'peerId': 98765, 'role': 'unknown'}, {'peerId': 98765, 'role': 'verified', 'expiresAt': 1}, {'peerId': 98765, 'role': 'verified', 'note': 'x' * 1025}]:
            with self.assertRaises(ValueError): self.registry.grant(body)
        self.assertEqual(len(self.registry.admin_records()['grants']), 1)
    def test_http_rejects_unauthenticated_writes(self):
        http = ThreadingHTTPServer(('127.0.0.1', 0), handler(self.registry))
        thread = threading.Thread(target=http.serve_forever, daemon=True)
        thread.start()
        try:
            url = f'http://127.0.0.1:{http.server_port}/v1/admin/grant'
            data = json.dumps({'peerId': 98765, 'role': 'verified'}).encode()
            with self.assertRaises(HTTPError) as failure: urlopen(Request(url, data=data))
            self.assertEqual(failure.exception.code, 401)
            token = (Path(self.directory.name) / 'admin-token').read_text()
            response = urlopen(Request(url, data=data, headers={'Authorization': 'Bearer ' + token, 'X-Faithgram-Actor': '1000'}))
            self.assertEqual(response.status, 200)
            self.assertEqual(len(self.registry.admin_records()['grants']), 2)
        finally:
            http.shutdown()
            http.server_close()
            thread.join()


if __name__ == '__main__': unittest.main()
