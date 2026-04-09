#!/usr/bin/env bash
set -euo pipefail

# Channel Traffic Analytics 一键部署脚本 (Linux / macOS)
# 用法: curl -fsSL https://raw.githubusercontent.com/tianchengdemo/channel-analytics-releases/main/release/install.sh | bash
# 或:   bash install.sh [--port 8080] [--dir /opt/site-analytics] [--password admin123]

REPO="tianchengdemo/channel-analytics-releases"
INSTALL_DIR="/opt/site-analytics"
PORT=8080
ADMIN_USER="admin"
ADMIN_PASS=""
TOKEN_SECRET=""

# ========== 参数解析 ==========
while [[ $# -gt 0 ]]; do
  case $1 in
    --port)      PORT="$2"; shift 2 ;;
    --dir)       INSTALL_DIR="$2"; shift 2 ;;
    --password)  ADMIN_PASS="$2"; shift 2 ;;
    --user)      ADMIN_USER="$2"; shift 2 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

# ========== 检测平台 ==========
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$OS" in
  linux)  GOOS="linux" ;;
  darwin) GOOS="darwin" ;;
  *)      echo "[ERROR] 不支持的操作系统: $OS"; exit 1 ;;
esac

case "$ARCH" in
  x86_64|amd64)  GOARCH="amd64" ;;
  aarch64|arm64) GOARCH="arm64" ;;
  *)             echo "[ERROR] 不支持的架构: $ARCH"; exit 1 ;;
esac

BINARY="site-analytics-${GOOS}-${GOARCH}"
echo "=========================================="
echo "  Channel Traffic Analytics 一键部署"
echo "=========================================="
echo "  平台:     ${GOOS}/${GOARCH}"
echo "  安装目录: ${INSTALL_DIR}"
echo "  端口:     ${PORT}"
echo "=========================================="

# ========== 获取最新版本 ==========
echo "[1/6] 获取最新版本..."
if command -v gh &>/dev/null; then
  LATEST=$(gh release view --repo "$REPO" --json tagName -q '.tagName' 2>/dev/null || echo "")
fi
if [ -z "${LATEST:-}" ]; then
  LATEST=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
fi
if [ -z "$LATEST" ]; then
  echo "[ERROR] 无法获取最新版本"; exit 1
fi
echo "  最新版本: $LATEST"

# ========== 下载二进制 ==========
echo "[2/6] 下载 ${BINARY}..."
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${LATEST}/${BINARY}"
TMP_FILE=$(mktemp)
curl -fSL --progress-bar "$DOWNLOAD_URL" -o "$TMP_FILE"
chmod +x "$TMP_FILE"

# ========== 安装 ==========
echo "[3/6] 安装到 ${INSTALL_DIR}..."
sudo mkdir -p "$INSTALL_DIR"/{data,logs}
sudo cp "$TMP_FILE" "$INSTALL_DIR/site-analytics"
sudo chmod +x "$INSTALL_DIR/site-analytics"
rm -f "$TMP_FILE"

# ========== 生成配置 ==========
echo "[4/6] 生成配置文件..."
if [ -z "$ADMIN_PASS" ]; then
  ADMIN_PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#' </dev/urandom | head -c 16 || true)
  echo "  [自动生成密码] $ADMIN_PASS"
fi
if [ -z "$TOKEN_SECRET" ]; then
  TOKEN_SECRET=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)
fi

CONFIG_FILE="$INSTALL_DIR/config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
  sudo tee "$CONFIG_FILE" > /dev/null <<YAML
server:
  port: ${PORT}
  host: "0.0.0.0"

database:
  path: "${INSTALL_DIR}/data/stats.db"

admin:
  username: "${ADMIN_USER}"
  password: "${ADMIN_PASS}"
  token_secret: "${TOKEN_SECRET}"

reporting:
  token: ""
  max_batch_size: 500

detail:
  enabled: false
  retention_days: 30

proxy:
  trusted_proxies:
    - "127.0.0.1/32"

buffer:
  flush_interval: 10s
  flush_threshold: 1000

log:
  level: "info"
  path: "${INSTALL_DIR}/logs/app.log"
YAML
  echo "  配置已写入: $CONFIG_FILE"
else
  echo "  配置已存在，跳过覆盖: $CONFIG_FILE"
fi

# ========== 注册 systemd 服务 (仅 Linux) ==========
if [ "$GOOS" = "linux" ] && command -v systemctl &>/dev/null; then
  echo "[5/6] 注册 systemd 服务..."
  sudo tee /etc/systemd/system/site-analytics.service > /dev/null <<SERVICE
[Unit]
Description=Channel Traffic Analytics
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/site-analytics -config ${INSTALL_DIR}/config.yaml
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICE

  sudo systemctl daemon-reload
  sudo systemctl enable site-analytics
  sudo systemctl restart site-analytics
  sleep 2

  if systemctl is-active --quiet site-analytics; then
    echo "  服务已启动"
  else
    echo "  [WARN] 服务启动异常，请检查: journalctl -u site-analytics -n 20"
  fi
else
  echo "[5/6] 非 Linux systemd 环境，跳过服务注册"
  echo "  手动启动: ${INSTALL_DIR}/site-analytics -config ${INSTALL_DIR}/config.yaml"
fi

# ========== 验证 ==========
echo "[6/6] 验证部署..."
sleep 1
HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" "http://127.0.0.1:${PORT}/admin/login.html" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  echo "  验证通过"
else
  echo "  [WARN] HTTP 状态码: $HTTP_CODE (服务可能需要几秒启动)"
fi

echo ""
echo "=========================================="
echo "  部署完成"
echo "=========================================="
echo "  后台地址: http://服务器IP:${PORT}/admin/"
echo "  用户名:   ${ADMIN_USER}"
echo "  密码:     ${ADMIN_PASS}"
echo "  配置文件: ${CONFIG_FILE}"
echo "  数据目录: ${INSTALL_DIR}/data/"
echo "  日志目录: ${INSTALL_DIR}/logs/"
echo ""
echo "  管理命令:"
echo "    启动: sudo systemctl start site-analytics"
echo "    停止: sudo systemctl stop site-analytics"
echo "    状态: sudo systemctl status site-analytics"
echo "    日志: journalctl -u site-analytics -f"
echo "=========================================="
