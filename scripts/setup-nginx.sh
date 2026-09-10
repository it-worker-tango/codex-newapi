#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
domain="aitest.work"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx certbot python3-certbot-nginx

install -d -m 0755 "/var/www/$domain"
install -m 0644 "$project_dir/nginx/site/index.html" "/var/www/$domain/index.html"
install -m 0644 "$project_dir/nginx/aitest.work.conf" "/etc/nginx/sites-available/$domain"
ln -sfn "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-enabled/$domain"
if [[ -L /etc/nginx/sites-enabled/default ]]; then
  unlink /etc/nginx/sites-enabled/default
fi

nginx -t
systemctl enable --now nginx
systemctl reload nginx

certbot --nginx -d "$domain" \
  --non-interactive \
  --agree-tos \
  --register-unsafely-without-email \
  --redirect

nginx -t
systemctl reload nginx
echo "HTTPS enabled: https://$domain"
