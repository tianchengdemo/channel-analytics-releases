#!/usr/bin/env bash
set -euo pipefail

# Channel Traffic Analytics Docker 一键部署
# 用法: curl -fsSL https://raw.githubusercontent.com/tianchengdemo/channel-analytics-releases/main/install-docker.sh | bash
# 或:   bash install-docker.sh [--port 8080] [--dir /opt/site-analytics] [--password admin123]

IMAGE="ghcr.io/tianchengdemo/channel-traffic-analytics:latest"
INSTALL_DIR="/opt/site-analytics"
PORT=8080
ADMIN_USER="admin"
ADMIN_PASS=""
CONTAINER_NAME="site-analytics"

# ========== 参数解析 ==========
while [[ $# -gt 0 ]]; do
  case $1 in
    --port)      PORT="$2"; shift 2 ;;
    --dir)       INSTALL_DIR="$2"; shift 2 ;;
    --password)  ADMIN_PASS="$2"; shift 2 ;;
    --user)      ADMIN_USER="$2"; shift 2 ;;
    --name)      CONTAINER_NAME="$2"; shift 2 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

echo "=========================================="
echo "  Channel Traffic Analytics Docker 部署"
echo "=========================================="
echo "  镜像:     ${IMAGE}"
echo "  端口:     ${PORT}"
echo "  数据目录: ${INSTALL_DIR}"
echo "=========================================="

# ========== 检查 Docker ==========
if ! command -v docker &>/dev/null; then
  echo "[ERROR] 未安装 Docker，请先安装: https://docs.docker.com/get-docker/"
  exit 1
fi

# ========== 生成配置 ==========
echo "[1/4] 准备配置..."
mkdir -p "$INSTALL_DIR"/{data,logs}

if [ -z "$ADMIN_PASS" ]; then
  ADMIN_PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#' </dev/urandom | head -c 16 || true)
  echo "  [自动生成密码] $ADMIN_PASS"
fi
TOKEN_SECRET=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)

CONFIG_FILE="$INSTALL_DIR/config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" <<YAML
server:
  port: 8080
  host: "0.0.0.0"

database:
  path: "/app/data/stats.db"

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
    - "172.16.0.0/12"

buffer:
  flush_interval: 10s
  flush_threshold: 1000

log:
  level: "info"
  path: "/app/logs/app.log"
YAML
  echo "  配置已生成: $CONFIG_FILE"
else
  echo "  配置已存在，跳过: $CONFIG_FILE"
fi

# ========== 拉取镜像 ==========
echo "[2/4] 拉取最新镜像..."
docker pull "$IMAGE"

# ========== 启动容器 ==========
echo "[3/4] 启动容器..."
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p "${PORT}:8080" \
  -v "$INSTALL_DIR/data:/app/data" \
  -v "$INSTALL_DIR/logs:/app/logs" \
  -v "$CONFIG_FILE:/app/config.yaml:ro" \
  -e TZ=Asia/Shanghai \
  "$IMAGE"

# ========== 验证 ==========
echo "[4/4] 验证部署..."
sleep 3
HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" "http://127.0.0.1:${PORT}/admin/login.html" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  echo "  验证通过"
else
  echo "  [WARN] HTTP ${HTTP_CODE}，容器可能需要几秒启动"
  echo "  检查日志: docker logs $CONTAINER_NAME"
fi

echo ""
echo "=========================================="
echo "  Docker 部署完成"
echo "=========================================="
echo "  后台地址: http://服务器IP:${PORT}/admin/"
echo "  用户名:   ${ADMIN_USER}"
echo "  密码:     ${ADMIN_PASS}"
echo ""
echo "  管理命令:"
echo "    状态: docker ps -f name=${CONTAINER_NAME}"
echo "    日志: docker logs -f ${CONTAINER_NAME}"
echo "    停止: docker stop ${CONTAINER_NAME}"
echo "    重启: docker restart ${CONTAINER_NAME}"
echo "    更新: docker pull ${IMAGE} && docker rm -f ${CONTAINER_NAME} && 重新运行本脚本"
echo "=========================================="
