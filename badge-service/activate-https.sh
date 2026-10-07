#!/bin/sh
set -eu

domain=badges.faithgram.xyz
site=/etc/nginx/conf.d/faithgram-badges.conf
source=/opt/faithgram-badges/nginx-https.conf

getent ahostsv4 "$domain" | awk '{print $1}' | grep -Fxq <server-ip> || {
    printf '%s\n' 'The hostname must resolve directly to this server before initial certificate issuance.' >&2
    exit 78
}

/usr/local/sbin/faithgram-certbot certonly --non-interactive --agree-tos --register-unsafely-without-email \
    --webroot --webroot-path /var/lib/faithgram-acme \
    --domain "$domain" --cert-name "$domain" --keep-until-expiring

backup="/opt/faithgram-badges/.backups/nginx-before-https-$(date +%s).conf"
install -d -m 700 /opt/faithgram-badges/.backups
cp -p "$site" "$backup"
install -m 644 "$source" "$site"
if nginx -t; then
    systemctl reload nginx
else
    cp -p "$backup" "$site"
    printf '%s\n' 'The previous Nginx configuration was restored.' >&2
    exit 1
fi

curl --fail --silent --show-error --max-time 15 \
    --retry 5 --retry-delay 1 --retry-max-time 20 --retry-all-errors \
    --resolve "$domain:443:127.0.0.1" "https://$domain/health"
