# 应用服务器配置修改（和平 / 冒险模式 / 命令方块 / PVP / 强制模式 / 地图名 world）
# 同时校验客户端"地图投票"键位为 H

$ErrorActionPreference = 'Stop'

$ServerProps = 'D:\MCSpark\server.properties'
$OptionsTxt  = 'D:\WDSJ\.minecraft\versions\HarpyExpress-SparkMC\options.txt'

Write-Host '========================================'
Write-Host ' 应用服务器配置修改'
Write-Host '========================================'

if (-not (Test-Path -LiteralPath $ServerProps)) {
    Write-Host "[错误] 找不到 $ServerProps" -ForegroundColor Red
    exit 1
}

# 服务器是否在运行（25565 端口被监听）
$serverRunning = Get-NetTCPConnection -LocalPort 25565 -State Listen -ErrorAction SilentlyContinue
if ($serverRunning) {
    Write-Host '[提示] 检测到服务器正在运行，改完配置后需要重启服务器才生效。' -ForegroundColor Yellow
} else {
    Write-Host '[信息] 服务器当前未运行，可以放心修改。'
}

# ---------- 1. 备份 ----------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bak = "$ServerProps.bak-$stamp"
Copy-Item -LiteralPath $ServerProps -Destination $bak
Write-Host "[信息] 已备份原配置: $bak"

# ---------- 2. 修改 server.properties ----------
$changes = [ordered]@{
    'difficulty'            = 'peaceful'
    'gamemode'              = 'adventure'
    'force-gamemode'        = 'true'
    'enable-command-block'  = 'true'
    'pvp'                   = 'true'
    'level-name'            = 'world'
}

$lines = Get-Content -LiteralPath $ServerProps -Encoding UTF8
$newLines = @()
foreach ($line in $lines) {
    $matched = $false
    foreach ($key in $changes.Keys) {
        if ($line -match "^$([regex]::Escape($key))\s*=") {
            $newLines += "$key=$($changes[$key])"
            $matched = $true
            break
        }
    }
    if (-not $matched) {
        $newLines += $line
    }
}
# 补上缺失的键
foreach ($key in $changes.Keys) {
    $exists = $newLines | Where-Object { $_ -match "^$([regex]::Escape($key))\s*=" }
    if (-not $exists) {
        $newLines += "$key=$($changes[$key])"
    }
}
Set-Content -LiteralPath $ServerProps -Value $newLines -Encoding ASCII

Write-Host ''
Write-Host '[完成] server.properties 已更新：'
foreach ($key in $changes.Keys) {
    Write-Host ("  {0} = {1}" -f $key, $changes[$key])
}

# ---------- 3. 客户端地图投票键位 ----------
Write-Host ''
Write-Host '[检查] 客户端"地图投票"键位...'
$needLine = 'key_key.wathe.map_vote:key.keyboard.h'
if (Test-Path -LiteralPath $OptionsTxt) {
    $gameRunning = Get-Process -Name javaw,java -ErrorAction SilentlyContinue
    if ($gameRunning) {
        Write-Host '[提示] 检测到 Java 正在运行。如果开着 Minecraft 客户端，改完键位会被游戏覆盖，建议先关游戏再改。' -ForegroundColor Yellow
    }
    $opts = Get-Content -LiteralPath $OptionsTxt -Encoding UTF8
    $already = $opts | Where-Object { $_ -match '^key_key\.wathe\.map_vote:key\.keyboard\.h\s*$' }
    if ($already) {
        Write-Host '[信息] 客户端地图投票键已经是 H，无需修改。'
    } else {
        $opts = $opts | Where-Object { $_ -notmatch '^key_key\.wathe\.map_vote:' }
        $opts += $needLine
        Set-Content -LiteralPath $OptionsTxt -Value $opts -Encoding UTF8
        Write-Host '[完成] 客户端地图投票键已改为 H。'
    }
} else {
    Write-Host '[提示] 找不到客户端 options.txt。请进游戏手动改：选项 → 控制 → wathe → 地图投票 → 按 H。' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '========================================'
Write-Host ' 全部完成！'
Write-Host '========================================'
Write-Host '1. 如果服务器在运行，关掉 start-server.bat 窗口后重新双击启动。'
Write-Host '2. 玩家重新进服后就是和平 + 冒险模式，PVP 开启，命令方块可用。'
