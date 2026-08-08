#!/bin/bash
# =====================================================
#  frps 一键安装脚本（Ubuntu / Debian）
#  用途: 在云服务器上安装 frps 内网穿透服务端
#  用法: sudo bash install-frps.sh
#  说明: 自动下载 frp -> 安装到 /opt/frps -> 注册 systemd 服务(开机自启)
#        -> 放行防火墙端口(7000/25565/24454)
# =====================================================
set -e

# ---------------- 可修改参数 ----------------
FRP_VERSION="0.61.1"                  # frp 版本号（文件名用，不带 v；下载 tag 会自动加 v）
BIND_PORT=7000                        # frps 监听端口（frpc 连接用）
AUTH_TOKEN="${FRPS_TOKEN:-trainwolf2026}"   # 认证密码（可用环境变量 FRPS_TOKEN 覆盖，必须和本地 frpc.toml 一致）
OPEN_PORTS="7000/tcp 25565/tcp 25565/udp 24454/udp"   # 需放行的端口

# 下载地址（直连 + 国内镜像，逐个尝试）
URLS=(
  "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz"
  "https://ghfast.top/https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz"
  "https://gh-proxy.com/https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz"
  "https://ghproxy.net/https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz"
)

echo "================ 开始安装 frps ================"

# 1. 清理旧的 frps 进程（可能是之前的 screen / nohup 方式）
if pgrep -x frps >/dev/null 2>&1; then
  echo "[1/6] 停止旧 frps 进程..."
  pkill -x frps || true
  sleep 1
else
  echo "[1/6] 无旧 frps 进程"
fi

# 2. 准备压缩包：优先用本地上传的，否则在服务器上下载
echo "[2/6] 准备 frp ${FRP_VERSION} 压缩包 ..."
TMPDIR_T=$(mktemp -d)
TARBALL=""
LOCAL_ARCHIVE="$(dirname "$0")/frp_${FRP_VERSION}_linux_amd64.tar.gz"
if [ -f "$LOCAL_ARCHIVE" ]; then
  echo "  使用已上传的压缩包: $LOCAL_ARCHIVE"
  TARBALL="$LOCAL_ARCHIVE"
else
  echo "  服务器上没有压缩包，开始下载..."
  for url in "${URLS[@]}"; do
    echo "  尝试: $url"
    if wget --progress=bar:force --timeout=60 -O "$TMPDIR_T/frp.tar.gz" "$url"; then
      TARBALL="$TMPDIR_T/frp.tar.gz"
      break
    fi
  done
fi
if [ -z "$TARBALL" ]; then
  echo "错误: 没有可用压缩包（未上传且所有下载源失败），请用 send-to-server.ps1 本地下好后上传。" >&2
  rm -rf "$TMPDIR_T"
  exit 1
fi

# 3. 解压并安装
echo "[3/6] 解压并安装到 /opt/frps ..."
tar xzf "$TARBALL" -C "$TMPDIR_T"
rm -rf /opt/frps
mv "$TMPDIR_T/frp_${FRP_VERSION}_linux_amd64" /opt/frps
chmod +x /opt/frps/frps

# 4. 写入 frps.toml
echo "[4/6] 写入 /opt/frps/frps.toml ..."
cat > /opt/frps/frps.toml <<EOF
bindPort = ${BIND_PORT}

auth.method = "token"
auth.token = "${AUTH_TOKEN}"
EOF

# 5. 注册 systemd 服务（开机自启）
echo "[5/6] 注册 systemd 服务 ..."
cat > /etc/systemd/system/frps.service <<'EOF'
[Unit]
Description=frp Server
After=network.target

[Service]
Type=simple
ExecStart=/opt/frps/frps -c /opt/frps/frps.toml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable frps >/dev/null 2>&1 || true
systemctl restart frps

# 6. 放行防火墙端口
echo "[6/6] 放行防火墙端口 ..."
if command -v ufw >/dev/null 2>&1; then
  for p in $OPEN_PORTS; do
    ufw allow "$p" >/dev/null 2>&1 || true
  done
  echo "  ufw 已放行: $OPEN_PORTS"
else
  echo "  未检测到 ufw，请自行在安全组/防火墙放行: $OPEN_PORTS"
fi

# 清理
rm -rf "$TMPDIR_T"

echo ""
echo "================ 安装完成 ================"
systemctl status frps --no-pager || true
echo ""
echo "frps 监听端口检查:"
ss -tlnp 2>/dev/null | grep ":${BIND_PORT}" || echo "  未发现 ${BIND_PORT} 监听（请检查上面的状态输出）"
echo ""
echo "提示:"
echo "  1. 本地 frpc.toml 的 serverAddr=云服务器IP, serverPort=${BIND_PORT}, token 必须与此脚本一致。"
echo "  2. 腾讯云控制台 -> 防火墙/安全组 也要放行: $OPEN_PORTS"
echo "  3. 重启服务器后 frps 会自动启动（systemd 服务）"
