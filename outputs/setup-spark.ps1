# spark1.5.4 服务端一键部署脚本
# 部署目标: D:\MCSpark（旧服务器 D:\MCServer 不动，保留作备份）

$ErrorActionPreference = 'Stop'

$ZipPath    = 'D:\Downloads\spark1.5.4服务端.zip'
$DestDir    = 'D:\MCSpark'
$BackupDir  = 'D:\MCServer'
$JavaPath   = 'D:\Java\jre21\jdk-21.0.12+8-jre\bin\java.exe'

Write-Host '========================================'
Write-Host ' spark 1.5.4 服务端部署'
Write-Host '========================================'

# ---------- 1. 基本检查 ----------
if (-not (Test-Path -LiteralPath $ZipPath)) {
    Write-Host "[错误] 找不到压缩包: $ZipPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $JavaPath)) {
    $cmd = Get-Command java -ErrorAction SilentlyContinue
    $java21 = $false
    if ($cmd) {
        $ver = & java -version 2>&1 | Out-String
        if ($ver -match 'version "21') { $java21 = $true }
    }
    if ($java21) {
        $JavaPath = 'java'
    } else {
        Write-Host "[错误] 找不到 Java 21。" -ForegroundColor Red
        Write-Host "       请把 Java 21 的 java.exe 完整路径改到脚本开头的 `$JavaPath 变量。"
        exit 1
    }
}

# ---------- 2. 端口占用提示 ----------
$busy = Get-NetTCPConnection -LocalPort 25565,24454 -State Listen -ErrorAction SilentlyContinue
if ($busy) {
    Write-Host '[提示] 25565/24454 端口仍被占用，请先关闭旧服务器和旧 frpc 的窗口。' -ForegroundColor Yellow
}

# ---------- 3. 准备目标目录 ----------
if (Test-Path -LiteralPath $DestDir) {
    if ($DestDir -ne 'D:\MCSpark') {
        Write-Host '[错误] 目标目录异常，拒绝清理。' -ForegroundColor Red
        exit 1
    }
    Write-Host "[信息] 清空旧目录: $DestDir"
    Remove-Item -LiteralPath $DestDir -Recurse -Force
}
New-Item -ItemType Directory -Path $DestDir | Out-Null

# ---------- 4. 解压服务端 ----------
Write-Host '[1/5] 解压服务端（约 460MB，请稍等）...'
Expand-Archive -LiteralPath $ZipPath -DestinationPath $DestDir

# ---------- 5. 复制皮肤登录与穿透文件 ----------
Write-Host '[2/5] 复制 authlib-injector 与 frp 文件...'
$authSrc = Join-Path $BackupDir 'authlib-injector.jar'
if (-not (Test-Path -LiteralPath $authSrc)) {
    $authSrc = 'D:\WDSJ\PCL\authlib-injector.jar'
}
if (-not (Test-Path -LiteralPath $authSrc)) {
    Write-Host '[错误] 找不到 authlib-injector.jar（D:\MCServer 或 D:\WDSJ\PCL 里都没有）。' -ForegroundColor Red
    exit 1
}
Copy-Item -LiteralPath $authSrc -Destination (Join-Path $DestDir 'authlib-injector.jar') -Force

if (Test-Path -LiteralPath (Join-Path $BackupDir 'frpc.exe')) {
    Copy-Item -LiteralPath (Join-Path $BackupDir 'frpc.exe') -Destination $DestDir -Force
} else {
    Write-Host '[提示] 未找到 frpc.exe，请手动把 frpc.exe 放到 D:\MCSpark。' -ForegroundColor Yellow
}
if (Test-Path -LiteralPath (Join-Path $BackupDir 'frpc.toml')) {
    Copy-Item -LiteralPath (Join-Path $BackupDir 'frpc.toml') -Destination $DestDir -Force
} else {
    Write-Host '[提示] 未找到 frpc.toml，请手动把 frpc.toml 放到 D:\MCSpark。' -ForegroundColor Yellow
}

# ---------- 6. server.properties ----------
Write-Host '[3/5] 写入 server.properties...'
$props = @'
#Minecraft server properties
accepts-transfers=false
allow-flight=false
allow-nether=true
broadcast-console-to-ops=true
difficulty=easy
enable-command-block=false
enable-rcon=false
enforce-secure-profile=false
enforce-whitelist=false
force-gamemode=false
gamemode=survival
generate-structures=true
hardcore=false
level-name=world
level-type=minecraft\:normal
max-players=12
max-tick-time=60000
motd=Spark 1.5.4
network-compression-threshold=256
online-mode=true
op-permission-level=4
player-idle-timeout=0
pvp=true
rate-limit=0
server-port=25565
simulation-distance=8
spawn-monsters=true
spawn-npcs=true
spawn-protection=16
sync-chunk-writes=true
use-native-transport=true
view-distance=8
white-list=true
'@
Set-Content -LiteralPath (Join-Path $DestDir 'server.properties') -Value $props -Encoding ASCII

# ---------- 7. 白名单与 OP（沿用原来的玩家） ----------
Write-Host '[4/5] 写入白名单和 OP...'
$whitelist = @'
[
  {"uuid":"093b9ce9-51da-3102-8124-91976311cf9e","name":"yumaoyueyuehai"},
  {"uuid":"b26d5a90-c8c0-3823-a31e-b53fb3b87b54","name":"CPD_Fertilizer"},
  {"uuid":"6c1b2212-419e-3f0c-9587-936f8ead8a7a","name":"sqtiamo"}
]
'@
$ops = @'
[
  {"uuid":"093b9ce9-51da-3102-8124-91976311cf9e","name":"yumaoyueyuehai","level":4,"bypassesPlayerLimit":false},
  {"uuid":"b26d5a90-c8c0-3823-a31e-b53fb3b87b54","name":"CPD_Fertilizer","level":4,"bypassesPlayerLimit":false},
  {"uuid":"6c1b2212-419e-3f0c-9587-936f8ead8a7a","name":"sqtiamo","level":4,"bypassesPlayerLimit":false}
]
'@
Set-Content -LiteralPath (Join-Path $DestDir 'whitelist.json') -Value $whitelist -Encoding ASCII
Set-Content -LiteralPath (Join-Path $DestDir 'ops.json') -Value $ops -Encoding ASCII

# ---------- 8. 启动脚本 ----------
Write-Host '[5/5] 写入启动脚本...'
$startServer = "@echo off`r`ncd /d $DestDir`r`n`"$JavaPath`" -javaagent:`"$DestDir\authlib-injector.jar=https://mcskin.com.cn/api/yggdrasil`" -Xmx3G -Xms1G -jar fabric-server-launch.jar nogui`r`npause"
Set-Content -LiteralPath (Join-Path $DestDir 'start-server.bat') -Value $startServer -Encoding ASCII

$startFrpc = "@echo off`r`ncd /d $DestDir`r`nfrpc.exe -c frpc.toml`r`npause"
Set-Content -LiteralPath (Join-Path $DestDir 'start-frpc.bat') -Value $startFrpc -Encoding ASCII

# ---------- 9. 完成 ----------
Write-Host ''
Write-Host '========================================'
Write-Host ' 部署完成！服务器目录: D:\MCSpark'
Write-Host '========================================'
Write-Host '1. 先关闭旧服务器窗口和旧 frpc 窗口（D:\MCServer 下的）。'
Write-Host '2. 双击 D:\MCSpark\start-server.bat 启动服务器，'
Write-Host '   等出现 Done (...) 后服务器就在 25565 端口运行了。'
Write-Host '3. 双击 D:\MCSpark\start-frpc.bat 启动内网穿透，'
Write-Host '   看到 start proxy success 说明外网已通（窗口保持打开）。'
Write-Host '4. 玩家连接地址不变: 1.15.171.18:25565'
Write-Host '   客户端版本用 HarpyExpress-SparkMC + 红石皮肤站外置登录。'
Write-Host ''
Write-Host '已预置白名单/OP: sqtiamo、yumaoyueyuehai、CPD_Fertilizer'
Write-Host '新增玩家请在服务器窗口输入: whitelist add 游戏ID'
Write-Host '旧服务器 D:\MCServer 已保留作备份，确认没问题后可自行删除。'
