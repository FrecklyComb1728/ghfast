#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}$1${NC}"; }
warn()  { echo -e "${YELLOW}$1${NC}"; }
err()   { echo -e "${RED}$1${NC}" >&2; }
abort() { err "$1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}   GH Fast 一键部署脚本${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# ======================== 前置检查 ========================
if [ "$(id -u)" -ne 0 ]; then
  abort "请以 root 用户运行此脚本（sudo ./deploy.sh）"
fi

if ! command -v nginx &>/dev/null; then
  abort "未检测到 nginx，请先安装 nginx"
fi

if [ ! -f "$SCRIPT_DIR/nginx.conf" ] || [ ! -f "$SCRIPT_DIR/index.html" ]; then
  abort "当前目录缺少 nginx.conf 或 index.html，请在仓库根目录下运行"
fi

# ======================== 1. 询问域名 ========================
echo -e "${GREEN}[1/7]${NC} 代理主域名"
echo ""
while true; do
  read -r -p "请输入代理主域名（如 gh.example.com）: " DOMAIN
  if [ -z "$DOMAIN" ]; then
    err "域名不能为空"
    continue
  fi
  if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
    err "域名格式不合法，仅允许字母、数字、连字符和点"
    continue
  fi
  break
done
echo ""

# ======================== 2. 询问 SSL ========================
echo -e "${GREEN}[2/7]${NC} SSL 证书配置"
echo ""
read -r -p "SSL 证书文件路径（fullchain.pem，留空则关闭 SSL）: " SSL_CERT

SSL_ENABLED=0
SSL_KEY=""

if [ -n "$SSL_CERT" ]; then
  if [ ! -f "$SSL_CERT" ]; then
    abort "证书文件不存在: $SSL_CERT"
  fi
  while true; do
    read -r -p "SSL 私钥文件路径（privkey.pem）: " SSL_KEY
    if [ -z "$SSL_KEY" ]; then
      err "私钥路径不能为空"
      continue
    fi
    if [ ! -f "$SSL_KEY" ]; then
      err "私钥文件不存在: $SSL_KEY"
      continue
    fi
    break
  done
  SSL_ENABLED=1
  info "已启用 SSL"
else
  warn "未提供 SSL 证书，将仅监听 HTTP (80)"
fi
echo ""

# ======================== 3. 询问 Crontab ========================
echo -e "${GREEN}[3/7]${NC} 缓存自动清理"
echo ""
warn "注意: 服务器硬盘可用空间太小（<= 10G）的话，不建议开缓存，缓存文件占用空间会非常大。"
echo ""
read -r -p "是否安装 crontab 定时清理缓存？(y/N): " INSTALL_CRON

CRON_STATIC=180
CRON_DYNAMIC=7

if [[ "$INSTALL_CRON" =~ ^[Yy]$ ]]; then
  while true; do
    read -r -p "静态缓存文件保留天数（默认 180）: " input
    if [ -z "$input" ]; then break; fi
    if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -gt 0 ]; then
      CRON_STATIC=$input; break
    fi
    err "请输入大于 0 的数字"
  done
  while true; do
    read -r -p "动态缓存文件保留天数（默认 7）: " input
    if [ -z "$input" ]; then break; fi
    if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -gt 0 ]; then
      CRON_DYNAMIC=$input; break
    fi
    err "请输入大于 0 的数字"
  done
  info "静态缓存保留 ${CRON_STATIC} 天，动态缓存保留 ${CRON_DYNAMIC} 天"
else
  warn "跳过 crontab 配置"
fi
echo ""

# ======================== 4. 询问 Web 根目录 ========================
echo -e "${GREEN}[4/7]${NC} Web 根目录"
echo ""
read -r -p "站点文件根目录（默认 /www/wwwroot/$DOMAIN）: " WEB_ROOT
WEB_ROOT="${WEB_ROOT:-/www/wwwroot/$DOMAIN}"
info "Web 根目录: $WEB_ROOT"
echo ""

# ======================== 5. 询问 Nginx 配置目录 ========================
echo -e "${GREEN}[5/7]${NC} Nginx 配置目录"
echo ""
echo "常见路径:"
echo "  /etc/nginx/conf.d/              (标准安装)"
echo "  /etc/nginx/sites-available/     (Debian/Ubuntu)"
echo "  /www/server/panel/vhost/nginx/  (宝塔面板)"
echo ""
while true; do
  read -r -p "Nginx 配置目录: " NGINX_DIR
  if [ -z "$NGINX_DIR" ]; then
    err "配置目录不能为空"
    continue
  fi
  if [ ! -d "$NGINX_DIR" ]; then
    err "目录不存在: $NGINX_DIR"
    continue
  fi
  break
done
echo ""

# ======================== 6. 询问日志目录 ========================
echo -e "${GREEN}[6/7]${NC} 日志目录"
echo ""
read -r -p "Nginx 日志目录（默认 /www/wwwlogs）: " LOG_DIR
LOG_DIR="${LOG_DIR:-/www/wwwlogs}"
echo ""

# ======================== 7. 确认执行 ========================
SCHEME="http"
[ "$SSL_ENABLED" -eq 1 ] && SCHEME="https"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}   确认配置${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "  域名:           ${GREEN}$DOMAIN${NC}"
echo -e "  Web 根目录:     ${GREEN}$WEB_ROOT${NC}"
echo -e "  Nginx 配置目录:  ${GREEN}$NGINX_DIR${NC}"
echo -e "  日志目录:        ${GREEN}$LOG_DIR${NC}"
if [ "$SSL_ENABLED" -eq 1 ]; then
  echo -e "  SSL 证书:       ${GREEN}$SSL_CERT${NC}"
  echo -e "  SSL 私钥:       ${GREEN}$SSL_KEY${NC}"
else
  echo -e "  SSL:            ${YELLOW}已关闭 (仅 HTTP)${NC}"
fi
if [[ "$INSTALL_CRON" =~ ^[Yy]$ ]]; then
  echo -e "  静态缓存保留:    ${GREEN}${CRON_STATIC} 天${NC}"
  echo -e "  动态缓存保留:    ${GREEN}${CRON_DYNAMIC} 天${NC}"
else
  echo -e "  缓存清理:        ${YELLOW}跳过${NC}"
fi
echo ""
read -r -p "确认执行？(y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  warn "已取消"
  exit 0
fi
echo ""

# ======================== 执行部署 ========================
echo -e "${CYAN}开始部署...${NC}"
echo ""

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

cp "$SCRIPT_DIR/nginx.conf" "$WORK_DIR/nginx.conf"
cp "$SCRIPT_DIR/index.html" "$WORK_DIR/index.html"

# --- 转义域名中的特殊字符供 sed 使用 ---
DOMAIN_ESC=$(printf '%s' "$DOMAIN" | sed 's/[&/\]/\\&/g')
WEB_ROOT_ESC=$(printf '%s' "$WEB_ROOT" | sed 's/[&/\]/\\&/g')
LOG_DIR_ESC=$(printf '%s' "$LOG_DIR" | sed 's/[&/\]/\\&/g')

# --- [1/6] 替换路径（必须在域名替换之前） ---
echo -e "${GREEN}[1/6]${NC} 替换路径"

sed -i "s|/www/wwwroot/gh\.1s\.fan|${WEB_ROOT}|g" "$WORK_DIR/nginx.conf"
sed -i "s|/www/wwwlogs|${LOG_DIR}|g" "$WORK_DIR/nginx.conf"
echo "  Web 根目录和日志路径已替换"
echo ""

# --- [2/6] 替换域名 ---
echo -e "${GREEN}[2/6]${NC} 替换域名 gh.1s.fan -> $DOMAIN"

sed -i "s/gh\.1s\.fan/${DOMAIN_ESC}/g" "$WORK_DIR/nginx.conf"
sed -i "s/gh\.1s\.fan/${DOMAIN_ESC}/g" "$WORK_DIR/index.html"
echo "  nginx.conf 和 index.html 中的域名已替换"
echo ""

# --- [3/6] SSL 处理 ---
if [ "$SSL_ENABLED" -eq 1 ]; then
  echo -e "${GREEN}[3/6]${NC} 配置 SSL"
  SSL_CERT_ESC=$(printf '%s' "$SSL_CERT" | sed 's/[&/\]/\\&/g')
  SSL_KEY_ESC=$(printf '%s' "$SSL_KEY" | sed 's/[&/\]/\\&/g')
  sed -i "s|ssl_certificate .*;|ssl_certificate ${SSL_CERT};|" "$WORK_DIR/nginx.conf"
  sed -i "s|ssl_certificate_key .*;|ssl_certificate_key ${SSL_KEY};|" "$WORK_DIR/nginx.conf"
  echo "  SSL 证书路径已设置"
else
  echo -e "${GREEN}[3/6]${NC} 关闭 SSL"
  sed -i '/listen 443 ssl;/d' "$WORK_DIR/nginx.conf"
  sed -i '/listen \[::\]:443 ssl;/d' "$WORK_DIR/nginx.conf"
  sed -i '/http2 on;/d' "$WORK_DIR/nginx.conf"
  sed -i '/ssl_certificate_key /d' "$WORK_DIR/nginx.conf"
  sed -i '/ssl_certificate /d' "$WORK_DIR/nginx.conf"
  sed -i '/ssl_protocols /d' "$WORK_DIR/nginx.conf"
  sed -i '/ssl_ciphers /d' "$WORK_DIR/nginx.conf"
  sed -i '/ssl_prefer_server_ciphers /d' "$WORK_DIR/nginx.conf"
  sed -i '/ssl_session_cache /d' "$WORK_DIR/nginx.conf"
  sed -i '/ssl_session_timeout /d' "$WORK_DIR/nginx.conf"
  sed -i "s|https://\$redirect_subdomain|http://\$redirect_subdomain|g" "$WORK_DIR/nginx.conf"
  sed -i 's|https://\$1\.|http://\$1.|g' "$WORK_DIR/nginx.conf"
  sed -i "s|https://assets\.|http://assets.|g" "$WORK_DIR/nginx.conf"
  sed -i "s|https://ghcr\.|http://ghcr.|g" "$WORK_DIR/nginx.conf"
  sed -i "s|https://${DOMAIN_ESC}|http://${DOMAIN_ESC}|g" "$WORK_DIR/nginx.conf"
  echo "  SSL 相关配置已移除，协议已改为 http"
fi
echo ""

# --- [4/6] 清理宝塔面板专属 include ---
echo -e "${GREEN}[4/6]${NC} 清理环境相关配置"

sed -i '/include.*panel\/vhost\/nginx\/extension/d' "$WORK_DIR/nginx.conf"
sed -i '/include.*panel\/vhost\/nginx\/well-known/d' "$WORK_DIR/nginx.conf"

# 自动检测 CA 证书路径
CA_BUNDLE=""
for ca in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/cert.pem; do
  if [ -f "$ca" ]; then
    CA_BUNDLE="$ca"
    break
  fi
done
if [ -n "$CA_BUNDLE" ]; then
  sed -i "s|/etc/pki/tls/certs/ca-bundle.crt|${CA_BUNDLE}|g" "$WORK_DIR/nginx.conf"
  echo "  CA 证书路径: $CA_BUNDLE"
else
  warn "  未找到系统 CA 证书，请手动修改 proxy_ssl_trusted_certificate 路径"
fi
echo ""

# --- [5/6] 创建目录 ---
echo -e "${GREEN}[5/6]${NC} 创建目录结构"

mkdir -p "$WEB_ROOT/proxy_cache_dir/static" "$WEB_ROOT/proxy_cache_dir/dynamic"

SUBDOMAINS=(api raw camo docs gist assets avatars objects codeload ghcr gist-assets user-images release-assets github-releases)
for sub in "${SUBDOMAINS[@]}"; do
  mkdir -p "$WEB_ROOT/$sub.$DOMAIN"
done
mkdir -p "$WEB_ROOT/$DOMAIN"
mkdir -p "$LOG_DIR"

echo "  已创建缓存目录、15 个域名子文件夹和日志目录"
echo ""

# --- [6/6] 复制文件 ---
echo -e "${GREEN}[6/6]${NC} 部署文件"

cp "$WORK_DIR/index.html" "$WEB_ROOT/$DOMAIN/index.html"
echo "  index.html -> $WEB_ROOT/$DOMAIN/"

cp "$WORK_DIR/nginx.conf" "$NGINX_DIR/ghfast.conf"
echo "  nginx.conf -> $NGINX_DIR/ghfast.conf"
echo ""

# --- Crontab ---
if [[ "$INSTALL_CRON" =~ ^[Yy]$ ]]; then
  echo -e "${CYAN}配置 crontab...${NC}"
  CRON_TAG="# ghfast-cache-cleanup"
  (crontab -l 2>/dev/null | grep -v "$CRON_TAG") | crontab -
  {
    crontab -l 2>/dev/null
    echo "0 2 * * 0 find $WEB_ROOT/proxy_cache_dir/static -type f -mtime +${CRON_STATIC} -delete $CRON_TAG"
    echo "0 3 * * 0 find $WEB_ROOT/proxy_cache_dir/dynamic -type f -mtime +${CRON_DYNAMIC} -delete $CRON_TAG"
  } | crontab -
  info "crontab 已配置:"
  echo "  静态缓存: 每周日 2:00 清理 ${CRON_STATIC} 天未访问文件"
  echo "  动态缓存: 每周日 3:00 清理 ${CRON_DYNAMIC} 天未访问文件"
  echo ""
fi

# --- Nginx 检查 ---
echo -e "${CYAN}验证 Nginx 配置...${NC}"
echo ""
if nginx -t 2>&1; then
  echo ""
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}   部署完成${NC}"
  echo -e "${GREEN}========================================${NC}"
  echo ""
  echo -e "  访问地址:  ${SCHEME}://$DOMAIN"
  echo -e "  配置文件:  $NGINX_DIR/ghfast.conf"
  echo -e "  首页路径:  $WEB_ROOT/$DOMAIN/index.html"
  echo ""
  read -r -p "是否立即重载 Nginx 使配置生效？(y/N): " RELOAD
  if [[ "$RELOAD" =~ ^[Yy]$ ]]; then
    nginx -s reload
    info "Nginx 已重载"
  else
    echo ""
    echo -e "手动重载: ${CYAN}nginx -s reload${NC}"
  fi
  echo ""
else
  echo ""
  err "========================================"
  err "   Nginx 配置验证失败"
  err "========================================"
  echo ""
  echo -e "请检查: $NGINX_DIR/ghfast.conf"
  echo ""
  exit 1
fi
