# faithgram badge service

The service publishes an Ed25519-signed badge list and provides an authenticated administrator API. Peer id 1000 is the only accepted administrator. The private administrator token stays on the server and in the owner's device Keychain. App builds contain only the HTTPS endpoint and public verification key.

Public responses include badge roles, peer ids and issue/expiry dates. Admin notes and revoked-grant history are available through the protected API. Requests and credentials are not logged by this service.

## Setup

Use Python 3.10 or newer and install the pinned dependency in a virtual environment:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m unittest -v test_server.py
.venv/bin/python server.py --data /var/lib/faithgram-badges --init
```

Run initialization as the service user in a directory it owns. Initialization creates private files with mode 0600 and prints only the public signing key. It preserves existing keys and database contents when run again. Keep the entire data directory in a protected backup; replacing the signing key requires an app configuration update.

Run the service on loopback behind an HTTPS reverse proxy:

```sh
.venv/bin/python server.py --data /var/lib/faithgram-badges --port 8787
```

The included systemd unit assumes the code is installed in `/opt/faithgram-badges`, its virtual environment is `.venv`, and the Unix service user is `faithgram-badges`. Adjust these paths to the server's existing layout.

Example Caddy site configuration:

```caddy
badges.example.com {
    reverse_proxy 127.0.0.1:8787 {
        header_up X-Real-IP {remote_host}
    }
}
```

Use the real hostname and a valid HTTPS certificate. Keep the application bound to loopback. Do not enable logging of authorization headers in the reverse proxy.

## App configuration

Set `assets/FaithgramBadgeService.json` to the real HTTPS endpoint and public key, update its checksum in `manifest.json`, then build the app. The empty template disables network synchronization until deployment is configured.

```json
{
  "endpoint": "https://badges.example.com",
  "publicKey": "base64-encoded-public-key"
}
```

On the owner's iPhone, open `faithgram → badges → sync → set administrator key` and enter the value from the server's private `admin-token` file. Do not put this token in the repository, app resources, logs, or chat.

Clients refresh the verified public list when opened and every five minutes while in the foreground. Cached signed lists are accepted for up to seven days while offline, and badge expiry is checked locally. A revoked badge may remain visible in an offline cached list until the next successful synchronization.

Existing local grants are not automatically uploaded. New grants use the shared service once configured. The original local list remains on the owner's device for reference.

## API

- `GET /health`: readiness.
- `GET /v1/public-key`: public signing key for deployment verification.
- `GET /v1/badges`: signed public snapshot.
- `GET /v1/admin/badges`: grant history and private notes.
- `POST /v1/admin/grant`: grant or update a badge.
- `POST /v1/admin/revoke`: revoke one grant without erasing its history.

Admin requests require `Authorization: Bearer <admin-token>` and `X-Faithgram-Actor: 1000`. The token is the server access credential; the app additionally gates the entire admin interface to the matching active Telegram account. Server issue dates are authoritative. Updates preserve the original issue date. A revoked role issued again creates a separate history entry.
