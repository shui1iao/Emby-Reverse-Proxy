#!/usr/bin/env bash
set -euo pipefail

DEFAULT_DOMAIN="${DOMAIN:-}"
DEFAULT_UPSTREAM="${UPSTREAM:-}"
PROXY_ENGINE="${PROXY_ENGINE:-auto}" # auto|caddy|nginx

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 运行：sudo bash $0"
  exit 1
fi

log() { printf '\033[36m[Emby-Proxy]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[提示]\033[0m %s\n' "$*"; }
fail() { printf '\033[31m[错误]\033[0m %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

ask() {
  local var_name="$1" prompt="$2" default_value="${3:-}" value
  if [ -n "$default_value" ]; then
    read -r -p "$prompt [$default_value]: " value || true
    value="${value:-$default_value}"
  else
    while true; do
      read -r -p "$prompt: " value || true
      [ -n "$value" ] && break
      warn "不能为空"
    done
  fi
  printf -v "$var_name" '%s' "$value"
}

normalize_upstream() {
  local u="$1"
  if [[ ! "$u" =~ ^https?:// ]]; then
    u="https://$u"
  fi
  echo "$u"
}

host_from_url() {
  local u="$1"
  u="${u#http://}"
  u="${u#https://}"
  u="${u%%/*}"
  u="${u%%:*}"
  echo "$u"
}

install_caddy() {
  log "未检测到 Caddy/Nginx，安装 Caddy..."
  if need_cmd apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y caddy
  elif need_cmd dnf; then
    dnf install -y 'dnf-command(copr)' || true
    dnf copr enable -y @caddy/caddy || true
    dnf install -y caddy
  elif need_cmd yum; then
    yum install -y yum-plugin-copr || true
    yum copr enable -y @caddy/caddy || true
    yum install -y caddy
  else
    fail "未找到 apt/dnf/yum，无法自动安装 Caddy"
  fi
}

open_firewall() {
  if need_cmd ufw && ufw status 2>/dev/null | grep -qi active; then
    ufw allow 80/tcp || true
    ufw allow 443/tcp || true
  fi
  if need_cmd firewall-cmd && systemctl is-active --quiet firewalld 2>/dev/null; then
    firewall-cmd --permanent --add-service=http || true
    firewall-cmd --permanent --add-service=https || true
    firewall-cmd --reload || true
  fi
}

choose_engine() {
  case "$PROXY_ENGINE" in
    caddy|nginx) echo "$PROXY_ENGINE"; return ;;
    auto) ;;
    *) fail "PROXY_ENGINE 只能是 auto/caddy/nginx" ;;
  esac

  if need_cmd caddy; then
    echo caddy
  elif need_cmd nginx; then
    echo nginx
  else
    install_caddy
    echo caddy
  fi
}

write_caddy() {
  local domain="$1" upstream="$2" upstream_host="$3"
  local caddyfile="/etc/caddy/Caddyfile"
  local begin="# >>> emby-reverse-proxy:$domain >>>"
  local end="# <<< emby-reverse-proxy:$domain <<<"
  local tmp
  tmp=$(mktemp)
  mkdir -p /etc/caddy
  touch "$caddyfile"
  cp -a "$caddyfile" "$caddyfile.bak-emby-proxy-$(date +%Y%m%d%H%M%S)"

  cat > "$tmp" <<EOC
$begin
$domain {
    encode zstd gzip

    reverse_proxy $upstream {
        header_up Host $upstream_host
        header_up X-Forwarded-Proto https
        header_up X-Real-IP {remote_host}
    }
}
$end
EOC

  awk -v begin="$begin" -v end="$end" '
    $0 == begin {skip=1; next}
    $0 == end {skip=0; next}
    !skip {print}
  ' "$caddyfile" > "$caddyfile.tmp"
  cat "$tmp" >> "$caddyfile.tmp"
  mv "$caddyfile.tmp" "$caddyfile"
  rm -f "$tmp"

  caddy fmt --overwrite "$caddyfile" >/dev/null || true
  caddy validate --config "$caddyfile"
  systemctl enable --now caddy
  systemctl reload caddy || systemctl restart caddy
}

write_nginx() {
  local domain="$1" upstream="$2" upstream_host="$3"
  local conf="/etc/nginx/conf.d/emby-${domain}.conf"
  if [ ! -d /etc/nginx/conf.d ]; then
    mkdir -p /etc/nginx/conf.d
  fi
  [ -f "$conf" ] && cp -a "$conf" "$conf.bak-$(date +%Y%m%d%H%M%S)"

  cat > "$conf" <<EON
server {
    listen 80;
    listen [::]:80;
    server_name $domain;

    client_max_body_size 0;
    proxy_buffering off;

    location / {
        proxy_pass $upstream;
        proxy_http_version 1.1;

        proxy_set_header Host $upstream_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
EON

  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx || systemctl restart nginx
  warn "检测到已有 Nginx，已写入 HTTP 反代配置：$conf"
  warn "如果需要 HTTPS，请用你现有的证书方案，或运行：certbot --nginx -d $domain"
}

main() {
  ask DOMAIN_INPUT "请输入你自己的域名，例如 emby.example.com" "$DEFAULT_DOMAIN"
  ask UPSTREAM_INPUT "请输入要反代的 Emby 地址，例如 https://lite.cn2gias.uk:443" "$DEFAULT_UPSTREAM"

  local domain upstream upstream_host engine ip
  domain="$DOMAIN_INPUT"
  upstream=$(normalize_upstream "$UPSTREAM_INPUT")
  upstream_host=$(host_from_url "$upstream")

  log "目标域名：$domain"
  log "上游 Emby：$upstream"

  engine=$(choose_engine)
  log "使用反代服务：$engine"

  if [ "$engine" = "caddy" ]; then
    write_caddy "$domain" "$upstream" "$upstream_host"
  else
    write_nginx "$domain" "$upstream" "$upstream_host"
  fi

  open_firewall
  ip=$(curl -4fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)

  echo
  log "完成。请确认 DNS：$domain A -> ${ip:-本机公网 IPv4}，并保持 DNS only/灰云。"
  if [ "$engine" = "caddy" ]; then
    log "访问地址：https://$domain"
  else
    log "访问地址：http://$domain"
    warn "Nginx 模式默认只写 HTTP 反代；如需 HTTPS，请用现有证书方案或 certbot --nginx -d $domain。"
  fi
  warn "如果服务器 curl 返回 403，但浏览器能打开，通常是上游 WAF 对命令行请求的拦截，不一定代表反代失败。"
}

main "$@"
