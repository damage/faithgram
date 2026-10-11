# faithgram badge service

The service publishes an Ed25519-signed badge list and provides an authenticated administrator API. The owner Telegram user id is the only accepted administrator; set it with `FAITHGRAM_OWNER_ID`, `--owner`, or an `owner-id` file in the data directory. The private administrator token stays on the server and in the owner's device Keychain. App builds contain only the HTTPS endpoint and public verification key.

Public responses include badge roles, peer ids and issue/expiry dates. Admin notes and revoked-grant history are available through the protected API. Requests and credentials are not logged by this service.

## Setup

Use Python 3.11 or newer and install the pinned dependency in a virtual environment:

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

## Docker deployment

The Dockerfile uses Python 3.12 on Debian Bookworm and includes the same registry and tests. Build it with `docker build -t faithgram-badges:2026-10-07 .` and run `python -m unittest -v test_server.py` inside the image before starting it.

Create a dedicated Unix service user and a private data directory owned by that user. Run the container with its numeric uid and gid, a writable mount from `/var/lib/faithgram-badges` to `/data`, and publish port 8787 to `127.0.0.1` only. The container listens on `0.0.0.0` within its own network namespace; the host publishes the API on loopback. Initialization must run with the same uid, gid and data mount as the long-running container.

Use a read-only container filesystem, a small temporary filesystem at `/tmp`, dropped capabilities, `no-new-privileges` and a restart policy. Keep the signing key, administrator token and database outside the image and source directory. The `.dockerignore` allows only the application code and build inputs.

The deployment hostname is `badges.faithgram.xyz`. `nginx-bootstrap.conf` provides the HTTP certificate challenge route and health check. Install it as a separate site in the existing Nginx configuration. After issuing a certificate, replace it with `nginx-https.conf`, validate Nginx and reload it. Leave unrelated site configurations in place.

The DNS record is type `A`, name `badges`, content the server address, TTL `Auto`. Use `DNS only` during certificate issuance. When enabling Cloudflare proxying, use `Full (strict)` with a valid origin certificate. Public snapshots and administrator responses must not be cached or placed behind an interactive browser challenge.

Certificate issuance uses the official Certbot container pinned by digest in `faithgram-certbot.sh`. Install that wrapper as `/usr/local/sbin/faithgram-certbot` and `renew-nginx.sh` as `/usr/local/sbin/faithgram-renew-nginx`, both with mode 0755. This keeps Certbot's Python dependencies separate from the host. Certificate, account and challenge directories are persistent mounts; the container does not receive the Docker socket.

After DNS is active, run `sh /opt/faithgram-badges/activate-https.sh`. It checks that the hostname resolves to this server, requests a certificate, validates the new site configuration and restores the previous configuration if validation fails. Install `faithgram-certbot.service` and `faithgram-certbot.timer` in `/etc/systemd/system`, reload systemd and enable the timer. It checks only this certificate twice daily. The host renewal wrapper reloads Nginx when the certificate changes. Directory hooks are disabled inside the container; Nginx stays managed by the host.

Verify renewal with `/usr/local/sbin/faithgram-renew-nginx --dry-run --no-random-sleep-on-renew`. Use this timer as the renewal mechanism for this deployment. Do not disable an existing system certificate timer that serves unrelated sites.

## App configuration

`assets/FaithgramBadgeService.json` contains the deployment endpoint and its public verification key. The build adds the owner id from the `FAITHGRAM_OWNER_ID` secret; it is not stored in the repository. Update the asset checksum in `manifest.json` whenever this configuration changes, then build the app. An empty endpoint or public key disables network synchronization.

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

Admin requests require `Authorization: Bearer <admin-token>` and `X-Faithgram-Actor: <owner id>`. The token is the server access credential; the app additionally gates the entire admin interface to the matching active Telegram account. Server issue dates are authoritative. Updates preserve the original issue date. A revoked role issued again creates a separate history entry.
