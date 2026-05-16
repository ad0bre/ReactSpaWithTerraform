#!/bin/sh
# ============================================================================
# 02-configure-nginx.sh
#
# Replaces the default nginx site with an SPA-friendly config:
#   - serves /var/www/html
#   - try_files falls back to index.html so client-side routes don't 404
#   - basic gzip on
# ============================================================================
set -eu

echo "[02] Removing default nginx site"
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-available/default

echo "[02] Installing SPA nginx config"
install -m 0644 /tmp/nginx-spa.conf /etc/nginx/sites-available/spa.conf
ln -sf /etc/nginx/sites-available/spa.conf /etc/nginx/sites-enabled/spa.conf

echo "[02] Ensuring /var/www/html exists and is owned by www-data"
mkdir -p /var/www/html
chown -R www-data:www-data /var/www/html

echo "[02] Validating nginx config"
nginx -t

echo "[02] Enabling nginx to start on boot"
systemctl enable nginx
