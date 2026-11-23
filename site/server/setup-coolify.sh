#!/usr/bin/env bash
# 已经跑着 Coolify（Traefik）的服务器用这个：起一个 nginx 小容器放网页，
# 用 docker 标签让 Coolify 的 Traefik 代理它、自动签 HTTPS。不改 Coolify 自己的任何配置。
#   ssh contabo-plus6 'bash -s xiaxia.ming95.com' < site/server/setup-coolify.sh
# 撤销：docker rm -f xiaxia-site （网页文件在 /var/www/xiaxia，留着）
set -euo pipefail
DOMAIN="${1:?用法：setup-coolify.sh 域名}"
DIR=/var/www/xiaxia
CONF=/var/www/xiaxia-conf
mkdir -p "$DIR/download" "$DIR/release-notes" "$CONF"
cat > "$CONF/default.conf" <<'NGINX'
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;
    gzip on;
    gzip_types text/css application/javascript application/xml text/xml image/svg+xml;

    location = /appcast.xml { add_header Cache-Control "no-cache"; }
    location = /download/xiaxia-ledger.dmg { add_header Cache-Control "no-cache"; }
    location = /index.html { add_header Cache-Control "no-cache"; }
    location /assets/ { add_header Cache-Control "public, max-age=604800"; }
    location / { try_files $uri $uri/ =404; }
}
NGINX
docker rm -f xiaxia-site >/dev/null 2>&1 || true
docker run -d --name xiaxia-site --restart unless-stopped --network coolify \
  -v "$DIR":/usr/share/nginx/html:ro \
  -v "$CONF/default.conf":/etc/nginx/conf.d/default.conf:ro \
  -l traefik.enable=true \
  -l "traefik.http.routers.xiaxia.rule=Host(\`$DOMAIN\`)" \
  -l traefik.http.routers.xiaxia.entrypoints=https \
  -l traefik.http.routers.xiaxia.tls=true \
  -l traefik.http.routers.xiaxia.tls.certresolver=letsencrypt \
  -l "traefik.http.routers.xiaxia-http.rule=Host(\`$DOMAIN\`)" \
  -l traefik.http.routers.xiaxia-http.entrypoints=http \
  -l traefik.http.routers.xiaxia-http.middlewares=xiaxia-https \
  -l traefik.http.middlewares.xiaxia-https.redirectscheme.scheme=https \
  -l traefik.http.services.xiaxia.loadbalancer.server.port=80 \
  -l traefik.docker.network=coolify \
  nginx:1.27-alpine >/dev/null
echo "✓ xiaxia-site 已启动（$DOMAIN），解析生效后 Traefik 会自动签 HTTPS"
