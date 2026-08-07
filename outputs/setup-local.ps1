# 列车狼人杀 本地一键部署脚本（Windows PowerShell）
# 用法（在 PowerShell 里执行）:
#   powershell -ExecutionPolicy Bypass -File "C:\Users\TiAmo\Documents\Codex\2026-08-04\new-chat-2\outputs\setup-local.ps1"

$ErrorActionPreference = "Stop"

# ===== 可修改的配置 =====
$ServerDir   = "D:\MCServer"                                  # 本地服务器目录
$ClientDir   = "D:\WDSJ\.minecraft\versions\列车狼人杀 优化版"  # 整合包实例（mods/config/地图都在这）
$ServerIp    = "1.15.171.18"                                  # 云服务器公网 IP
$FrpPassword = "trainwolf2026"                                # frp 通信口令（两端必须一致）
$Memory      = "3G"                                           # 给 MC 的内存

function Write-Step($msg) {
    Write-Host ""
    Write-Host "========== $msg ==========" -ForegroundColor Cyan
}

function Find-Java {
    $candidates = @()
    if (Get-Command java -ErrorAction SilentlyContinue) {
        $candidates += (Get-Command java).Source
    }
    if ($env:JAVA_HOME) {
        $candidates += Join-Path $env:JAVA_HOME "bin\java.exe"
    }
    $candidates += @(
        "C:\Program Files\Java\*\bin\java.exe",
        "C:\Program Files\Eclipse Adoptium\*\bin\java.exe",
        "C:\Program Files\Microsoft\*\bin\java.exe",
        "C:\Program Files\Zulu\*\bin\java.exe",
        "C:\Program Files\Amazon Corretto\*\bin\java.exe",
        "D:\Java\*\bin\java.exe"
    ) | ForEach-Object { Get-ChildItem -Path $_ -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName }
    $candidates += Get-ChildItem -Path "D:\WDSJ" -Recurse -Filter java.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName

    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) {
            $v = cmd /c "`"$c`" -version 2>&1"
            if ($v -match "21") { return $c }
        }
    }
    return $null
}

function Download-File($url, $out) {
    Write-Host "下载中: $url"
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -L --fail -o $out $url
    } else {
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
    }
    if (-not (Test-Path $out)) { throw "下载失败: $url" }
}

Write-Step "1/8 检查 Java 21"
$Java = Find-Java
if (-not $Java) {
    Write-Host "没找到 Java 21，自动从清华镜像下载安装到 D:\Java ..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path "D:\Java" -Force | Out-Null
    $JreZip = "D:\Java\jre21.zip"
    if (-not (Test-Path $JreZip)) {
        Download-File "https://mirrors.tuna.tsinghua.edu.cn/Adoptium/21/jre/x64/windows/OpenJDK21U-jre_x64_windows_hotspot_21.0.12_8.zip" $JreZip
    }
    Expand-Archive -LiteralPath $JreZip -DestinationPath "D:\Java\jre21" -Force
    $Java = Get-ChildItem -Path "D:\Java\jre21" -Recurse -Filter java.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if (-not $Java) {
        Write-Host "Java 自动安装失败，请手动把 Java 21 解压到 D:\Java 后重试" -ForegroundColor Red
        exit 1
    }
    Write-Host "已安装 Java: $Java"
}
Write-Host "使用 Java: $Java"
$jv = cmd /c "`"$Java`" -version 2>&1"
Write-Host "  $jv"

Write-Step "2/8 创建服务器目录"
New-Item -ItemType Directory -Path $ServerDir -Force | Out-Null
if (-not (Test-Path (Join-Path $ClientDir "mods"))) { throw "找不到整合包实例: $ClientDir" }
Write-Host "服务器目录: $ServerDir"

$LaunchJar = Join-Path $ServerDir "fabric-server-launch.jar"
if (-not (Test-Path $LaunchJar)) {
    Write-Step "3/8 生成 Fabric 1.21.1 服务端"
    $Installer = Join-Path $ServerDir "fabric-installer.jar"
    if (-not (Test-Path $Installer)) {
        Download-File "https://maven.fabricmc.net/net/fabricmc/fabric-installer/1.0.1/fabric-installer-1.0.1.jar" $Installer
    }
    Push-Location $ServerDir
    & $Java -jar $Installer server -mcversion 1.21.1 -dir $ServerDir
    Pop-Location
    if (-not (Test-Path $LaunchJar)) { throw "Fabric 服务端生成失败" }
} else {
    Write-Host "Fabric 服务端已存在，跳过"
}

$ServerJar = Join-Path $ServerDir "server.jar"
if (-not (Test-Path $ServerJar) -or (Get-Item $ServerJar).Length -lt 40MB) {
    Write-Step "4/8 下载官方 server.jar（国内镜像）"
    Download-File "https://bmclapi2.bangbang93.com/version/1.21.1/server" $ServerJar
    if ((Get-Item $ServerJar).Length -lt 40MB) { throw "server.jar 下载不完整" }
} else {
    Write-Host "server.jar 已存在，跳过"
}

$ModsDir = Join-Path $ServerDir "mods"
if (-not (Test-Path (Join-Path $ModsDir "*.jar"))) {
    Write-Step "5/8 从整合包实例复制 mods（按内容去重）"
    New-Item -ItemType Directory -Path $ModsDir -Force | Out-Null
    $seen = @{}
    Get-ChildItem -LiteralPath (Join-Path $ClientDir "mods") -Filter *.jar | ForEach-Object {
        $h = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        if (-not $seen.ContainsKey($h)) {
            $seen[$h] = $true
            Copy-Item -LiteralPath $_.FullName -Destination $ModsDir
        }
    }
    $count = (Get-ChildItem -Path $ModsDir -Filter *.jar).Count
    Write-Host "mods 数量: $count"
    if ($count -lt 30) { throw "mods 复制不完整" }
} else {
    Write-Host "mods 已存在，跳过"
}

$WorldDir = Join-Path $ServerDir "The Harpy Express 2"
$ConfigDir = Join-Path $ServerDir "config"
if (-not (Test-Path $WorldDir) -or -not (Test-Path $ConfigDir)) {
    Write-Step "6/8 从整合包实例复制 config 和游戏地图"
    if (-not (Test-Path $ConfigDir) -and (Test-Path (Join-Path $ClientDir "config"))) {
        Copy-Item -LiteralPath (Join-Path $ClientDir "config") -Destination $ServerDir -Recurse -Force
    }
    if (-not (Test-Path $WorldDir) -and (Test-Path (Join-Path $ClientDir "saves\The Harpy Express 2"))) {
        Copy-Item -LiteralPath (Join-Path $ClientDir "saves\The Harpy Express 2") -Destination $ServerDir -Recurse -Force
    }
} else {
    Write-Host "地图和 config 已存在，跳过"
}

Write-Step "7/8 写入 eula.txt 和 server.properties"
Set-Content -LiteralPath (Join-Path $ServerDir "eula.txt") -Value "eula=true" -Encoding ASCII
$Props = @"
level-name=The Harpy Express 2
server-port=25565
online-mode=false
white-list=false
max-players=12
view-distance=8
motd=列车狼人杀
"@
Set-Content -LiteralPath (Join-Path $ServerDir "server.properties") -Value $Props -Encoding ASCII

Write-Step "8/8 下载并配置 frpc（内网穿透客户端）"
$FrpZip = Join-Path $ServerDir "frp.zip"
if (-not (Test-Path (Join-Path $ServerDir "frpc.exe"))) {
    if (-not (Test-Path $FrpZip)) {
        try {
            Download-File "https://ghfast.top/https://github.com/fatedier/frp/releases/download/v0.61.1/frp_0.61.1_windows_amd64.zip" $FrpZip
        } catch {
            Download-File "https://github.com/fatedier/frp/releases/download/v0.61.1/frp_0.61.1_windows_amd64.zip" $FrpZip
        }
    }
    $FrpDir = Join-Path $ServerDir "frp_extract"
    Expand-Archive -LiteralPath $FrpZip -DestinationPath $FrpDir -Force
    $FrpcExe = Get-ChildItem -Path $FrpDir -Recurse -Filter frpc.exe | Select-Object -First 1
    if (-not $FrpcExe) { throw "frpc.exe 解压失败" }
    Copy-Item -LiteralPath $FrpcExe.FullName -Destination (Join-Path $ServerDir "frpc.exe") -Force
    Remove-Item -LiteralPath $FrpDir -Recurse -Force
}

$FrpcToml = @"
serverAddr = "$ServerIp"
serverPort = 7000
auth.token = "$FrpPassword"

[[proxies]]
name = "mc-tcp"
type = "tcp"
localIP = "127.0.0.1"
localPort = 25565
remotePort = 25565

[[proxies]]
name = "mc-voice-udp"
type = "udp"
localIP = "127.0.0.1"
localPort = 24454
remotePort = 24454
"@
Set-Content -LiteralPath (Join-Path $ServerDir "frpc.toml") -Value $FrpcToml -Encoding ASCII

if ($Java -match "\\bin\\java\.exe$" -and $Java -ne "java") {
    $JavaCmd = "`"$Java`""
} else {
    $JavaCmd = "java"
}
Set-Content -LiteralPath (Join-Path $ServerDir "start-server.bat") -Value "@echo off`r`ncd /d $ServerDir`r`n$JavaCmd -Xmx$Memory -Xms1G -jar fabric-server-launch.jar nogui`r`npause" -Encoding ASCII
Set-Content -LiteralPath (Join-Path $ServerDir "start-frpc.bat") -Value "@echo off`r`ncd /d $ServerDir`r`nfrpc.exe -c frpc.toml`r`npause" -Encoding ASCII

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "本地部署完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "1. 双击启动服务器: D:\MCServer\start-server.bat"
Write-Host "   等出现 Done (...) 后，在窗口里输入:"
Write-Host "     op sqtiamo"
Write-Host "     whitelist add sqtiamo"
Write-Host "     whitelist on"
Write-Host ""
Write-Host "2. 再双击启动穿透: D:\MCServer\start-frpc.bat"
Write-Host "   看到 start proxy success 就通了（这个窗口要一直开着）"
Write-Host ""
Write-Host "3. 玩家连接地址不变: $ServerIp`:25565"
Write-Host ""
Write-Host "如果服务器启动报错，把窗口里的内容发我。"
