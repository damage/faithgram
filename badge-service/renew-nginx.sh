#!/bin/sh
set -eu

cert=/etc/letsencrypt/live/badges.faithgram.xyz/fullchain.pem
before=$(sha256sum "$cert")
/usr/local/sbin/faithgram-certbot renew --cert-name badges.faithgram.xyz \
    --non-interactive --quiet "$@"
after=$(sha256sum "$cert")
if [ "$before" != "$after" ]; then
    /usr/sbin/nginx -t
    /bin/systemctl reload nginx
fi
