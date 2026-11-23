#!/usr/bin/env bash
# 在 VPS 上跑一次（Debian / Ubuntu）：装 Caddy，配好网站目录和 HTTPS。
#   ssh vps 'sudo bash -s xiaxia.example.com' < site/server/setup.sh
# 跑之前：域名的 A 记录（有 IPv6 再加 AAAA）要已经指向这台 VPS，80 和 443 端口要开着。
set -euo pipefail
DOMAIN="${1:?用法：setup.sh 域名}"
DIR=/var/www/xiaxia
if ! command -v caddy >/dev/null; then
  apt-get update -y
  apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -y && apt-get install -y caddy
fi
mkdir -p "$DIR/download" "$DIR/release-notes"
chown -R "${SUDO_USER:-root}":"${SUDO_USER:-root}" "$DIR"
CF=/etc/caddy/Caddyfile
[ -f "$CF" ] && cp "$CF" "$CF.bak-$(date +%Y%m%d%H%M%S)"
cat > "$CF" <<CADDY
$DOMAIN {
	root * $DIR
	encode zstd gzip
	file_server
	@fresh path /appcast.xml /download/xiaxia-ledger.dmg /index.html /
	header @fresh Cache-Control "no-cache"
	@assets path /assets/*
	header @assets Cache-Control "public, max-age=604800"
	@dmg path /download/*.dmg
	header @dmg Content-Type "application/x-apple-diskimage"
	header {
		Strict-Transport-Security "max-age=31536000"
		X-Content-Type-Options nosniff
		Referrer-Policy strict-origin-when-cross-origin
	}
}
www.$DOMAIN {
	redir https://$DOMAIN{uri} permanent
}
CADDY
if command -v ufw >/dev/null && ufw status | grep -q active; then ufw allow 80/tcp; ufw allow 443/tcp; fi
systemctl enable caddy >/dev/null 2>&1 || true
systemctl reload caddy || systemctl restart caddy
echo "✓ Caddy 已配好 $DOMAIN（第一次打开时自动申请 HTTPS 证书）"
