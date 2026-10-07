#!/bin/sh
set -eu

image=certbot/certbot@sha256:f70ad0adbb7e117f0fe42a63c553f28ea451edabc0148757b6efcd9735acaa20

install -d -m 700 /etc/letsencrypt /var/lib/letsencrypt /var/log/letsencrypt
exec /usr/bin/docker run --rm --read-only --cap-drop ALL \
    --security-opt no-new-privileges \
    --tmpfs /tmp:rw,noexec,nosuid,size=64m \
    --mount type=bind,src=/etc/letsencrypt,dst=/etc/letsencrypt \
    --mount type=bind,src=/var/lib/letsencrypt,dst=/var/lib/letsencrypt \
    --mount type=bind,src=/var/log/letsencrypt,dst=/var/log/letsencrypt \
    --mount type=bind,src=/var/lib/faithgram-acme,dst=/var/lib/faithgram-acme \
    "$image" "$@" --no-directory-hooks
