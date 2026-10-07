#!/usr/bin/env python3
"""Signed badge registry. Run behind an HTTPS reverse proxy."""
import argparse
import base64
from collections import OrderedDict
from contextlib import contextmanager
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import sqlite3
import threading
import time
from urllib.parse import urlsplit
import uuid

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

OWNER = 1000
ROLES = {'developer', 'betaTester', 'paidSubscriber', 'verified'}


class Registry:
    def __init__(self, directory: Path, initialize=False):
        self.directory = directory.resolve()
        if initialize:
            self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
            for name, content in [
                ('signing-key', Ed25519PrivateKey.generate().private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())),
                ('admin-token', secrets.token_hex(32).encode('ascii')),
            ]:
                path = self.directory / name
                try:
                    with path.open('xb') as output:
                        output.write(content)
                    path.chmod(0o600)
                except FileExistsError:
                    pass
        self.signer = Ed25519PrivateKey.from_private_bytes((self.directory / 'signing-key').read_bytes())
        self.token_hash = hashlib.sha256((self.directory / 'admin-token').read_bytes().strip()).digest()
        self.public_key = base64.b64encode(self.signer.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode('ascii')
        self.lock = threading.RLock()
        self.rate_lock = threading.Lock()
        self.failures = OrderedDict()
        with self.database() as db:
            db.executescript('''
                CREATE TABLE IF NOT EXISTS grants (
                    id TEXT PRIMARY KEY, peer_id INTEGER NOT NULL, role TEXT NOT NULL,
                    issued_at REAL, issued_by INTEGER NOT NULL,
                    expires_at REAL, note TEXT NOT NULL DEFAULT '', revoked_at REAL
                );
                CREATE TABLE IF NOT EXISTS state (id INTEGER PRIMARY KEY CHECK(id=1), revision INTEGER NOT NULL);
                INSERT OR IGNORE INTO state VALUES(1, 1);
                CREATE TABLE IF NOT EXISTS audit (id INTEGER PRIMARY KEY, at REAL NOT NULL, actor INTEGER NOT NULL, action TEXT NOT NULL, grant_id TEXT NOT NULL);
            ''')
            if db.execute('SELECT COUNT(*) FROM grants').fetchone()[0] == 0:
                db.execute('INSERT INTO grants VALUES(?,?,?,?,?,?,?,?)', ('owner-developer', OWNER, 'developer', None, OWNER, None, '', None))
        (self.directory / 'registry.sqlite3').chmod(0o600)

    @contextmanager
    def database(self):
        with self.lock:
            db = sqlite3.connect(self.directory / 'registry.sqlite3', timeout=10)
            db.row_factory = sqlite3.Row
            try:
                with db:
                    yield db
            finally:
                db.close()

    @staticmethod
    def record(row, private=False):
        value = {'id': row['id'], 'peerId': row['peer_id'], 'role': row['role'], 'issuedAt': row['issued_at'], 'issuedBy': row['issued_by'], 'expiresAt': row['expires_at'], 'revokedAt': row['revoked_at'], 'note': row['note'] if private else ''}
        return value

    def snapshot(self):
        now = time.time()
        with self.database() as db:
            revision = db.execute('SELECT revision FROM state WHERE id=1').fetchone()[0]
            rows = db.execute('SELECT * FROM grants WHERE revoked_at IS NULL AND (expires_at IS NULL OR expires_at>?) ORDER BY peer_id,role', (now,)).fetchall()
        payload = json.dumps({'version': 1, 'revision': revision, 'generatedAt': now, 'grants': [self.record(row) for row in rows]}, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')
        return {'payload': base64.b64encode(payload).decode('ascii'), 'signature': base64.b64encode(self.signer.sign(payload)).decode('ascii')}

    def admin_records(self):
        with self.database() as db:
            return {'grants': [self.record(row, private=True) for row in db.execute('SELECT * FROM grants ORDER BY issued_at DESC')], 'audit': [dict(row) for row in db.execute('SELECT * FROM audit ORDER BY id DESC LIMIT 1000')]}

    def authorize(self, bearer, actor, address):
        now = time.monotonic()
        with self.rate_lock:
            failures, since = self.failures.get(address, (0, now))
            if now - since >= 60:
                failures, since = 0, now
            if failures >= 20:
                return False
            ok = actor == str(OWNER) and len(bearer) <= 256 and hmac.compare_digest(hashlib.sha256(bearer.encode()).digest(), self.token_hash)
            if not ok:
                self.failures[address] = (failures + 1, since)
                self.failures.move_to_end(address)
                while len(self.failures) > 1024:
                    self.failures.popitem(last=False)
            return ok

    def grant(self, body):
        peer = body.get('peerId')
        role = body.get('role')
        note = body.get('note', '')
        expiry = body.get('expiresAt')
        now = time.time()
        if type(peer) is not int or not 0 < peer <= 9223372036854775807 or not isinstance(role, str) or role not in ROLES:
            raise ValueError('invalid user or badge')
        if not isinstance(note, str) or len(note.encode('utf-8')) > 1024:
            raise ValueError('invalid note')
        if expiry is not None and (type(expiry) not in (int, float) or not now < expiry <= now + 36500 * 86400):
            raise ValueError('invalid expiry')
        with self.database() as db:
            if db.execute('SELECT COUNT(*) FROM grants').fetchone()[0] >= 20000:
                raise ValueError('registry limit reached')
            old = db.execute('SELECT * FROM grants WHERE peer_id=? AND role=? AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at>?)', (peer, role, now)).fetchone()
            if old:
                grant_id = old['id']
                db.execute('UPDATE grants SET note=?,expires_at=? WHERE id=?', (note, expiry, grant_id))
                action = 'update'
            else:
                grant_id = str(uuid.uuid4())
                db.execute('INSERT INTO grants VALUES(?,?,?,?,?,?,?,?)', (grant_id, peer, role, now, OWNER, expiry, note, None))
                action = 'grant'
            db.execute('UPDATE state SET revision=revision+1 WHERE id=1')
            db.execute('INSERT INTO audit(at,actor,action,grant_id) VALUES(?,?,?,?)', (now, OWNER, action, grant_id))
        return {'id': grant_id}

    def revoke(self, grant_id):
        with self.database() as db:
            result = db.execute('UPDATE grants SET revoked_at=? WHERE id=? AND revoked_at IS NULL', (time.time(), grant_id))
            if result.rowcount != 1:
                raise ValueError('active grant not found')
            db.execute('UPDATE state SET revision=revision+1 WHERE id=1')
            db.execute('INSERT INTO audit(at,actor,action,grant_id) VALUES(?,?,?,?)', (time.time(), OWNER, 'revoke', grant_id))
        return {'ok': True}


def handler(registry):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'
        def setup(self):
            super().setup()
            self.connection.settimeout(15)
        def log_message(self, *_args):
            pass
        def respond(self, value, code=200):
            data = json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
            self.send_response(code)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.end_headers()
            self.wfile.write(data)
        def authorized(self):
            value = self.headers.get('Authorization', '')
            bearer = value[7:] if value.startswith('Bearer ') else ''
            # The proxy is local. A verified proxy may supply the actual address.
            address = self.headers.get('X-Real-IP', self.client_address[0])[:128]
            return registry.authorize(bearer, self.headers.get('X-Faithgram-Actor', ''), address)
        def do_GET(self):
            path = urlsplit(self.path).path
            if path == '/health': self.respond({'ok': True}); return
            if path == '/v1/public-key': self.respond({'publicKey': registry.public_key}); return
            if path == '/v1/badges': self.respond(registry.snapshot()); return
            if path == '/v1/admin/badges' and self.authorized(): self.respond(registry.admin_records()); return
            self.respond({'error': 'not found or unauthorized'}, 404)
        def do_POST(self):
            if not self.authorized(): self.respond({'error': 'unauthorized'}, 401); return
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if not 0 < size <= 8192: raise ValueError('invalid body size')
                body = json.loads(self.rfile.read(size))
                path = urlsplit(self.path).path
                if path == '/v1/admin/grant': result = registry.grant(body)
                elif path == '/v1/admin/revoke':
                    grant_id = body.get('id')
                    if not isinstance(grant_id, str) or len(grant_id) > 128: raise ValueError('invalid grant id')
                    result = registry.revoke(grant_id)
                else: self.respond({'error': 'not found'}, 404); return
                self.respond(result)
            except (ValueError, TypeError, KeyError, AttributeError): self.respond({'error': 'invalid request'}, 400)
    return Handler


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--data', type=Path, default=Path('/var/lib/faithgram-badges'))
    parser.add_argument('--init', action='store_true')
    parser.add_argument('--port', type=int, default=8787)
    args = parser.parse_args()
    os.umask(0o077)
    store = Registry(args.data, initialize=args.init)
    if args.init:
        print('Public signing key: ' + store.public_key)
        print('Administrator credential saved locally in admin-token. Keep this file private.')
    else:
        ThreadingHTTPServer(('127.0.0.1', args.port), handler(store)).serve_forever()
