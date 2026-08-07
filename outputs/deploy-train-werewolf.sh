#!/usr/bin/env bash
# 列车狼人杀 服务器一键部署脚本（Ubuntu 22.04 / 24.04）
# 用法（先把整合包 zip 上传到服务器任意位置）:
#   sudo bash deploy-train-werewolf.sh "/opt/列车狼人杀 优化版.zip"
set -euo pipefail

ZIP="${1:-/opt/列车狼人杀 优化版.zip}"
PACK_DIR=/opt/pack
SERVER_DIR=/opt/trainwolf
MC_VERSION=1.21.1
MEMORY="${MEMORY:-3G}"

if [[ ! -f "$ZIP" ]]; then
  echo "[错误] 找不到压缩包: $ZIP"
  echo "请先把整合包上传到服务器，然后执行: sudo bash deploy-train-werewolf.sh 压缩包路径"
  exit 1
fi

echo "==> 1/7 安装 Java 21、解压工具、screen"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y openjdk-21-jre-headless unzip p7zip-full screen

echo "==> 2/7 解压整合包到 $PACK_DIR"
rm -rf "$PACK_DIR"
mkdir -p "$PACK_DIR"
7z x -y -o"$PACK_DIR" "$ZIP" >/dev/null

echo "==> 3/7 生成 Fabric 1.21.1 服务端"
mkdir -p "$SERVER_DIR" && cd "$SERVER_DIR"
if [[ ! -f fabric-installer.jar ]]; then
  wget -q https://maven.fabricmc.net/net/fabricmc/fabric-installer/1.0.1/fabric-installer-1.0.1.jar -O fabric-installer.jar
fi
java -jar fabric-installer.jar server -mcversion "$MC_VERSION" -dir "$SERVER_DIR"

echo "==> 4/7 复制 mods / config / 游戏地图"
mkdir -p mods config
cp "$PACK_DIR"/overrides/mods/*.jar mods/
cp -r "$PACK_DIR"/overrides/config/. config/
cp -r "$PACK_DIR"/overrides/saves/"The Harpy Express 2" "$SERVER_DIR"/

echo "==> 5/7 写入 eula.txt 和 server.properties"
echo "eula=true" > eula.txt
cat > server.properties <<EOF
level-name=The Harpy Express 2
server-port=25565
online-mode=true
white-list=false
max-players=12
view-distance=8
motd=列车狼人杀
EOF

echo "==> 6/7 防火墙处理"
echo "    为避免影响服务器上的其他项目，脚本不会自动启用 ufw。"
echo "    请到云厂商控制台安全组放行: TCP 25565（游戏）、UDP 24454（语音）。"
if [[ "${ENABLE_UFW:-0}" == "1" ]]; then
  echo "    已设置 ENABLE_UFW=1，放行 22/25565/24454 并启用 ufw"
  ufw allow 22/tcp || true
  ufw allow 25565/tcp || true
  ufw allow 24454/udp || true
  ufw --force enable || true
fi

echo "==> 7/7 启动服务器（screen 会话，内存 $MEMORY）"
cd "$SERVER_DIR"
screen -dmS mc java -Xmx"$MEMORY" -Xms1G -jar fabric-server-launch.jar nogui
sleep 12
screen -ls || true

echo ""
echo "部署完成！"
echo "  查看/操作控制台 : screen -r mc    （按 Ctrl+A 再按 D 退出，服务器继续运行）"
echo "  启动             : screen -dmS mc java -Xmx$MEMORY -Xms1G -jar /opt/trainwolf/fabric-server-launch.jar nogui"
echo ""
echo "下一步（云厂商控制台安全组也别忘了放行 TCP 25565 和 UDP 24454）:"
echo "  1. 进入控制台: screen -r mc"
echo "  2. 给自己管理员: op 你的游戏ID"
echo "  3. 玩家连接: 公网IP:25565（客户端必须装同一个整合包，且为 1.21.1 Fabric）"
