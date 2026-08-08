#requires -Version 5.1
param(
    [switch]$SmokeTest,
    [switch]$UITest,
    [string]$AppDir = ''
)

# =====================================================
#  MC 服务器管理器 (MC Server Manager)
#  部署 / 启动 / 管理 Minecraft 服务器
#  用法: 双击 start-manager.bat 或在 PowerShell 运行本文件
# =====================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------- 全局状态 ----------------
$script:settingsPath = if ($AppDir) {
    Join-Path $AppDir 'mc-server-manager-settings.json'
} else {
    Join-Path $PSScriptRoot 'mc-server-manager-settings.json'
}
$script:serverDir = ''
$script:javaPath = ''
$script:javaMap = @{}
$script:javaInstallDir = ''
$script:authUrl = 'https://mcskin.com.cn/api/yggdrasil'
$script:useAuth = $true
$script:authMode = 'thirdparty'   # premium / thirdparty
$script:skinStation = '红石皮肤站'  # 红石皮肤站 / LittleSkin / 自定义
$script:maxMem = 3
$script:maxPlayers = 12
$script:freshZip = ''
$script:freshDir = ''
$script:frpIp = ''
$script:frpPort = ''
$script:frpToken = ''
$script:gamePort = ''
$script:voicePort = ''
$script:deployZip = ''
$script:deployDir = ''
$script:freshMcVersion = ''
$script:sshIp = ''
$script:sshUser = ''
$script:sshScript = ''
$script:sshRemote = ''
$script:sshToken = ''
$script:frpcExe = ''
$script:frpcCfg = ''
$script:serverProfiles = @{}
$script:switchingServer = $false
$script:serverProc = $null
$script:frpcProc = $null
$script:consolePos = 0
$script:frpcPos = 0
$script:modItems = @()
$script:appVersion = 'v2.52'
$script:lastPortCheck = 0
$script:cachedServerRunning = $false

# ---------------- 工具函数 ----------------
function Set-UiStatus {
    param([string]$Text)
    if ($script:lblStatus) { $script:lblStatus.Text = $Text }
}

function Save-Settings {
    if ($script:serverDir) {
        $script:serverProfiles[$script:serverDir] = @{
            name       = [System.IO.Path]::GetFileName($script:serverDir.TrimEnd('\'))
            javaPath   = $script:javaPath
            maxMem     = $script:maxMem
            authMode   = $script:authMode
            skinStation = $script:skinStation
            authUrl    = $script:authUrl
            frpcExe    = $script:frpcExe
            frpcCfg    = $script:frpcCfg
        }
    }
    $data = [ordered]@{
        serverDir = $script:serverDir
        javaPath  = $script:javaPath
        javaMap   = $script:javaMap
        javaInstallDir = $script:javaInstallDir
        authUrl   = $script:authUrl
        useAuth   = $script:useAuth
        authMode  = $script:authMode
        skinStation = $script:skinStation
        maxMem    = $script:maxMem
        maxPlayers = $script:maxPlayers
        freshZip  = $script:freshZip
        freshDir  = $script:freshDir
        frpIp     = $script:frpIp
        frpPort   = $script:frpPort
        frpToken  = $script:frpToken
        gamePort  = $script:gamePort
        voicePort = $script:voicePort
        deployZip = $script:deployZip
        deployDir = $script:deployDir
        freshMcVersion = $script:freshMcVersion
        sshIp     = $script:sshIp
        sshUser   = $script:sshUser
        sshScript = $script:sshScript
        sshRemote = $script:sshRemote
        sshToken  = $script:sshToken
        frpcExe   = $script:frpcExe
        frpcCfg   = $script:frpcCfg
        serverProfiles = $script:serverProfiles
    }
    try {
        $data | ConvertTo-Json | Set-Content -LiteralPath $script:settingsPath -Encoding UTF8
    } catch { }
}

function Load-Settings {
    if (-not (Test-Path -LiteralPath $script:settingsPath)) { return }
    try {
        $s = Get-Content -LiteralPath $script:settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($s.javaPath) { $script:javaPath = $s.javaPath }
        if ($s.javaMap) {
            foreach ($p in $s.javaMap.PSObject.Properties) { $script:javaMap[$p.Name] = [string]$p.Value }
        }
        if ($s.javaInstallDir) { $script:javaInstallDir = $s.javaInstallDir }
        if ($s.authUrl) { $script:authUrl = $s.authUrl }
        if ($null -ne $s.useAuth) { $script:useAuth = [bool]$s.useAuth }
        if ($s.authMode) { $script:authMode = [string]$s.authMode }
        if ($s.skinStation) { $script:skinStation = [string]$s.skinStation }
        if ($script:authMode -eq 'authlib' -or $script:authMode -eq 'offline') {
            $script:authMode = 'thirdparty'
        }
        if ($script:authMode -notin @('premium', 'thirdparty')) {
            $script:authMode = if ($script:useAuth) { 'thirdparty' } else { 'thirdparty' }
        }
        if ($s.maxMem) { $script:maxMem = [int]$s.maxMem }
        if ($s.maxPlayers) { $script:maxPlayers = [int]$s.maxPlayers }
        if ($s.freshZip) { $script:freshZip = $s.freshZip }
        if ($s.freshDir) { $script:freshDir = $s.freshDir }
        if ($s.frpIp) { $script:frpIp = $s.frpIp }
        if ($s.frpPort) { $script:frpPort = $s.frpPort }
        if ($s.frpToken) { $script:frpToken = $s.frpToken }
        if ($s.gamePort) { $script:gamePort = $s.gamePort }
        if ($s.voicePort) { $script:voicePort = $s.voicePort }
        if ($s.deployZip) { $script:deployZip = $s.deployZip }
        if ($s.deployDir) { $script:deployDir = $s.deployDir }
        if ($s.freshMcVersion) { $script:freshMcVersion = $s.freshMcVersion }
        if ($s.sshIp) { $script:sshIp = $s.sshIp }
        if ($s.sshUser) { $script:sshUser = $s.sshUser }
        if ($s.sshScript) { $script:sshScript = $s.sshScript }
        if ($s.sshRemote) { $script:sshRemote = $s.sshRemote }
        if ($s.sshToken) { $script:sshToken = $s.sshToken }
        if ($s.frpcExe) { $script:frpcExe = $s.frpcExe }
        if ($s.frpcCfg) { $script:frpcCfg = $s.frpcCfg }
        if ($s.serverProfiles) {
            foreach ($p in $s.serverProfiles.PSObject.Properties) {
                $script:serverProfiles[$p.Name] = @{
                    name        = [string]$p.Value.name
                    javaPath    = [string]$p.Value.javaPath
                    maxMem      = [int]$p.Value.maxMem
                    authMode    = [string]$p.Value.authMode
                    skinStation = [string]$p.Value.skinStation
                    authUrl     = [string]$p.Value.authUrl
                    frpcExe     = [string]$p.Value.frpcExe
                    frpcCfg     = [string]$p.Value.frpcCfg
                }
            }
        }
        # 兼容旧版本：没有 profiles 时，用当前设置建一个档案
        if ($script:serverProfiles.Count -eq 0 -and $script:serverDir) {
            $script:serverProfiles[$script:serverDir] = @{
                name        = [System.IO.Path]::GetFileName($script:serverDir.TrimEnd('\'))
                javaPath    = $script:javaPath
                maxMem      = $script:maxMem
                authMode    = $script:authMode
                skinStation = $script:skinStation
                authUrl     = $script:authUrl
                frpcExe     = $script:frpcExe
                frpcCfg     = $script:frpcCfg
            }
        }
    } catch { }
}

function New-RandomPassword {
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    return -join (1..12 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

function Get-ServerPort {
    if (-not $script:serverDir) { return 25565 }
    $p = Join-Path $script:serverDir 'server.properties'
    if (Test-Path -LiteralPath $p) {
        $line = Get-Content -LiteralPath $p -Encoding UTF8 | Where-Object { $_ -match '^server-port\s*=' } | Select-Object -First 1
        if ($line) { return [int](($line -split '=', 2)[1].Trim()) }
    }
    return 25565
}

function Get-RconPort {
    $p = Join-Path $script:serverDir 'server.properties'
    if (Test-Path -LiteralPath $p) {
        $line = Get-Content -LiteralPath $p -Encoding UTF8 | Where-Object { $_ -match '^rcon\.port\s*=' } | Select-Object -First 1
        if ($line) { return [int](($line -split '=', 2)[1].Trim()) }
    }
    return 25575
}

function Get-RconPassword {
    $p = Join-Path $script:serverDir 'server.properties'
    if (Test-Path -LiteralPath $p) {
        $line = Get-Content -LiteralPath $p -Encoding UTF8 | Where-Object { $_ -match '^rcon\.password=' } | Select-Object -First 1
        if ($line) { return ($line -replace '^rcon\.password=', '').Trim() }
    }
    return ''
}

function Test-PortListen {
    param([int]$Port)
    $conns = Get-NetTCPConnection -ErrorAction SilentlyContinue
    foreach ($c in $conns) {
        if ($c.State -eq 'Listen' -and $c.LocalPort -eq $Port) { return $true }
    }
    return $false
}

function Test-ServerLaunchable {
    param([string]$Dir)
    if (Test-Path -LiteralPath (Join-Path $Dir 'fabric-server-launch.jar')) { return $true }
    if (Test-Path -LiteralPath (Join-Path $Dir 'server.jar')) { return $true }
    if (Test-Path -LiteralPath (Join-Path $Dir 'libraries\net\neoforged')) { return $true }
    if (Test-Path -LiteralPath (Join-Path $Dir 'libraries\net\minecraftforge')) { return $true }
    if (Get-ChildItem -LiteralPath $Dir -Filter 'forge-*-universal.jar' -ErrorAction SilentlyContinue) { return $true }
    return $false
}

function Get-ServerLaunchInfo {
    $dir = $script:serverDir
    if (Test-Path -LiteralPath (Join-Path $dir 'fabric-server-launch.jar')) {
        return @{ Type = 'fabric'; Args = @('-jar', 'fabric-server-launch.jar', 'nogui') }
    }
    $neoforge = Get-ChildItem -LiteralPath (Join-Path $dir 'libraries\net\neoforged\neoforge') -Recurse -Filter 'win_args.txt' -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($neoforge) {
        return @{ Type = 'neoforge'; Args = @('@' + $neoforge.FullName, 'nogui') }
    }
    $forge = Get-ChildItem -LiteralPath (Join-Path $dir 'libraries\net\minecraftforge\forge') -Recurse -Filter 'win_args.txt' -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($forge) {
        return @{ Type = 'forge'; Args = @('@' + $forge.FullName, 'nogui') }
    }
    $oldForge = Get-ChildItem -LiteralPath $dir -Filter 'forge-*-universal.jar' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($oldForge) {
        return @{ Type = 'forge-old'; Args = @('-jar', $oldForge.Name, 'nogui') }
    }
    if (Test-Path -LiteralPath (Join-Path $dir 'server.jar')) {
        return @{ Type = 'vanilla'; Args = @('-jar', 'server.jar', 'nogui') }
    }
    return $null
}

function Get-SkinStationUrl {
    param([string]$Name)
    switch ($Name) {
        '离线模式'   { return '' }
        '红石皮肤站' { return 'https://mcskin.com.cn/api/yggdrasil' }
        'LittleSkin' { return 'https://littleskin.cn/api/yggdrasil' }
        '自定义'     { return $script:authUrl }
        default      { return $script:authUrl }
    }
}

function Get-SkinStationNameFromUrl {
    param([string]$Url)
    if (-not $Url) { return '离线模式' }
    if ($Url -match 'mcskin\.com\.cn') { return '红石皮肤站' }
    if ($Url -match 'littleskin\.(cn|com|dev)') { return 'LittleSkin' }
    return '自定义'
}

function Get-AuthJavaAgentArg {
    param([string]$ServerDir)
    if ($script:authMode -ne 'thirdparty' -or $script:skinStation -eq '离线模式') { return '' }
    $agent = Join-Path $ServerDir 'authlib-injector.jar'
    if (-not (Test-Path -LiteralPath $agent)) {
        foreach ($cand in @('D:\WDSJ\PCL\authlib-injector.jar', 'D:\MCServer\authlib-injector.jar', 'D:\MCSpark\authlib-injector.jar')) {
            if (Test-Path -LiteralPath $cand) {
                try { Copy-Item -LiteralPath $cand -Destination $agent -Force; break } catch { }
            }
        }
    }
    if (-not (Test-Path -LiteralPath $agent)) { return '' }
    if ($agent -match '\s') {
        return '-javaagent:"' + $agent + '=' + $script:authUrl + '"'
    }
    return '-javaagent:' + $agent + '=' + $script:authUrl
}

function Sync-AuthToServerProps {
    if (-not $script:serverDir) { return }
    $spFile = Join-Path $script:serverDir 'server.properties'
    if (-not (Test-Path -LiteralPath $spFile)) { return }
    # 官方与第三方皮肤站(带 authlib-injector)都应保持 online-mode=true，
    # 由服务器在线验证并把皮肤分发给所有客户端；仅“离线模式”才用 false。
    $expectedOnline = 'false'
    if ($script:authMode -eq 'premium' -or ($script:authMode -eq 'thirdparty' -and $script:skinStation -ne '离线模式')) {
        $expectedOnline = 'true'
    }
    Update-PropertyFile -FilePath $spFile -Changes @{ 'online-mode' = $expectedOnline }
}

function Write-RunBat {
    param([string]$ServerDir)
    if (-not $ServerDir -or -not (Test-Path -LiteralPath $ServerDir)) { return $null }
    $launch = Get-ServerLaunchInfo
    if (-not $launch) {
        $dir = $ServerDir
        if (Test-Path -LiteralPath (Join-Path $dir 'server.jar')) {
            $launch = @{ Type = 'vanilla'; Args = @('-jar', 'server.jar', 'nogui') }
        } else {
            return $null
        }
    }
    $java = $script:javaPath
    if (-not $java -and $script:javaMap.ContainsKey($ServerDir)) { $java = $script:javaMap[$ServerDir] }
    if (-not $java) {
        $mcVer = Get-McVersionFromServerDir -Dir $ServerDir
        if ($mcVer) {
            $j = Find-JavaByMajor -Major (Get-RequiredJavaMajor -McVersion $mcVer)
            if ($j) { $java = $j }
        }
    }
    if (-not $java) { $java = 'java' }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('@echo off')
    $lines.Add('chcp 65001 >nul')
    $lines.Add('cd /d "%~dp0"')
    if ($java -ne 'java') {
        $lines.Add('set "JAVA=' + $java + '"')
        $lines.Add('if not exist "%JAVA%" (')
        $lines.Add('  echo [错误] 找不到 Java: %JAVA%')
        $lines.Add('  pause')
        $lines.Add('  exit /b 1')
        $lines.Add(')')
    } else {
        $lines.Add('set "JAVA=java"')
    }
    $jvmArgs = @()
    if ($script:authMode -eq 'thirdparty' -and $script:skinStation -ne '离线模式') {
        $agentArg = Get-AuthJavaAgentArg -ServerDir $ServerDir
        if ($agentArg) { $jvmArgs += $agentArg }
    }
    $jvmArgs += '-Xmx' + $script:maxMem + 'G'
    $jvmArgs += '-Xms1G'
    if ($launch.Type -eq 'fabric') {
        $cmd = '"%JAVA%" ' + ($jvmArgs -join ' ') + ' -jar fabric-server-launch.jar nogui'
        $lines.Add($cmd)
    } elseif ($launch.Type -eq 'vanilla') {
        $cmd = '"%JAVA%" ' + ($jvmArgs -join ' ') + ' -jar server.jar nogui'
        $lines.Add($cmd)
    } elseif ($launch.Type -eq 'forge-old') {
        $cmd = '"%JAVA%" ' + ($jvmArgs -join ' ') + ' -jar "' + $launch.Args[1] + '" nogui'
        $lines.Add($cmd)
    } elseif ($launch.Type -eq 'neoforge' -or $launch.Type -eq 'forge') {
        $winArgs = $launch.Args[0]
        $lines.Add('REM ' + $launch.Type + ' server launcher')
        if ($jvmArgs.Count -gt 0) {
            $cmd = '"%JAVA%" ' + ($jvmArgs -join ' ') + ' @' + $winArgs + ' nogui'
            $lines.Add($cmd)
        } else {
            $cmd = '"%JAVA%" @' + $winArgs + ' nogui'
            $lines.Add($cmd)
        }
    } else {
        return $null
    }
    $lines.Add('pause')
    $batPath = Join-Path $ServerDir 'run.bat'
    try {
        [System.IO.File]::WriteAllLines($batPath, $lines, (New-Object System.Text.UTF8Encoding($false)))
        return $batPath
    } catch {
        return 'ERR:' + $_.Exception.Message
    }
}

function Get-SshTool {
    param([string]$Name)
    $p = "C:\Windows\System32\OpenSSH\$Name.exe"
    if (Test-Path -LiteralPath $p) { return $p }
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-McVersionFromInstaller {
    param([string]$ServerDir)
    $installer = Get-ChildItem -LiteralPath $ServerDir -Filter 'forge-*-installer.jar' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $installer) { $installer = Get-ChildItem -LiteralPath $ServerDir -Filter 'neoforge-*-installer.jar' -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if (-not $installer) { return '' }
    if ($installer.Name -match '-(\d+\.\d+(?:\.\d+)?)-') { return $matches[1] }
    return ''
}

function Get-McVersionFromServerDir {
    param([string]$Dir)
    $v = Get-McVersionFromInstaller -ServerDir $Dir
    if ($v) { return $v }
    $verDir = Join-Path $Dir 'versions'
    if (Test-Path -LiteralPath $verDir) {
        $sub = Get-ChildItem -LiteralPath $verDir -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($sub -and $sub.Name -match '^\d+\.\d+(\.\d+)?') { return $sub.Name }
    }
    $forge = Get-ChildItem -LiteralPath (Join-Path $Dir 'libraries\net\minecraftforge\forge') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($forge -and $forge.Name -match '^(\d+\.\d+(\.\d+)?)-') { return $matches[1] }
    $neo = Get-ChildItem -LiteralPath (Join-Path $Dir 'libraries\net\neoforged\neoforge') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($neo -and $neo.Name -match '^(\d+\.\d+(\.\d+)?)-') { return $matches[1] }
    return ''
}

function Get-RequiredJavaMajor {
    param([string]$McVersion)
    if ($McVersion -match '^1\.21') { return 21 }
    if ($McVersion -match '^1\.20\.(5|6)') { return 21 }
    if ($McVersion -match '^1\.(17|18|19|20)') { return 17 }
    if ($McVersion -match '^1\.(8|9|10|11|12|13|14|15|16)') { return 8 }
    return 21
}

function Match-JavaForVersion {
    $mcVer = $script:txtFMcVersion.Text.Trim()
    if (-not $mcVer) {
        $script:lblFJavaMatch.Text = '输入后自动匹配对应 Java'
        if ($script:btnFDownloadJava) { $script:btnFDownloadJava.Text = '下载安装' }
        return
    }
    $major = Get-RequiredJavaMajor -McVersion $mcVer
    $java = Find-JavaByMajor -Major $major
    if ($java) {
        $script:javaPath = $java
        $script:txtJava.Text = $java
        $script:lblFJavaMatch.Text = "已匹配 Java $major"
        if ($script:lblFJavaStatus) { $script:lblFJavaStatus.Text = "已匹配: $java" }
    } else {
        $script:lblFJavaMatch.Text = "需要 Java $major（本机未找到，部署时会提示下载）"
        if ($script:lblFJavaStatus) { $script:lblFJavaStatus.Text = "未找到 Java $major" }
    }
    if ($script:btnFDownloadJava) { $script:btnFDownloadJava.Text = "下载 Java $major" }
    Save-Settings
}

function Match-JavaForServerDir {
    if (-not $script:serverDir) { return }
    $mcVer = Get-McVersionFromServerDir -Dir $script:serverDir
    if (-not $mcVer) {
        if ($script:lblJava) { $script:lblJava.Text = 'Java:' }
        return
    }
    $major = Get-RequiredJavaMajor -McVersion $mcVer
    if ($script:lblJava) { $script:lblJava.Text = "Java ${major}:" }
    if ($script:btnDownloadJava) { $script:btnDownloadJava.Text = "下载 Java $major" }
    $j = Find-JavaByMajor -Major $major
    if ($j -and $j -ne $script:javaPath) {
        $script:javaPath = $j
        $script:txtJava.Text = $j
        Save-Settings
    }
}

function Get-DefaultJavaInstallDir {
    if ($script:javaPath -and (Test-Path -LiteralPath $script:javaPath)) {
        $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $script:javaPath))
        if ($root -and (Test-Path -LiteralPath $root)) { return $root }
    }
    return 'D:\Java'
}

function Download-NeededJava {
    $major = 21
    $detected = $false
    if ($script:serverDir) {
        $mcVer = Get-McVersionFromServerDir -Dir $script:serverDir
        if ($mcVer) { $major = Get-RequiredJavaMajor -McVersion $mcVer; $detected = $true }
    }
    if (-not $detected -and $script:txtFMcVersion) {
        $mcVer = $script:txtFMcVersion.Text.Trim()
        if ($mcVer) { $major = Get-RequiredJavaMajor -McVersion $mcVer }
    }
    return Install-JavaByMajor -Major $major
}

function Get-JavaDownloadUrl {
    param([int]$Major)
    try {
        $page = (Invoke-WebRequest -Uri "https://mirrors.tuna.tsinghua.edu.cn/Adoptium/$Major/jre/x64/windows/" -UseBasicParsing -TimeoutSec 20).Content
        $names = @([regex]::Matches($page, "OpenJDK${Major}U-jre_x64_windows_hotspot_[0-9._]+\.zip") | ForEach-Object { $_.Value } | Sort-Object -Unique)
        $best = $null
        $bestVer = @(0, 0, 0, 0)
        foreach ($n in $names) {
            if ($n -match 'hotspot_([0-9]+)\.([0-9]+)\.([0-9]+)(?:_([0-9]+))?\.zip') {
                $v4 = if ($matches[4]) { [int]$matches[4] } else { 0 }
                $ver = @([int]$matches[1], [int]$matches[2], [int]$matches[3], $v4)
                $newer = $false
                for ($i = 0; $i -lt 4; $i++) {
                    if ($ver[$i] -gt $bestVer[$i]) { $newer = $true; break }
                    if ($ver[$i] -lt $bestVer[$i]) { break }
                }
                if ($newer -or -not $best) { $best = $n; $bestVer = $ver }
            }
        }
        if ($best) { return "https://mirrors.tuna.tsinghua.edu.cn/Adoptium/$Major/jre/x64/windows/$best" }
    } catch { }
    return "https://api.adoptium.net/v3/binary/latest/$Major/ga/windows/x64/jre/hotspot/normal/eclipse"
}

function Get-JavaVersionPattern {
    param([int]$Major)
    if ($Major -eq 8) { return 'version "1\.8' }
    return ('version "' + $Major)
}

function Find-JavaByMajor {
    param([int]$Major)
    $candidates = @()
    foreach ($scanDir in @($script:javaInstallDir, 'D:\Java')) {
        if ($scanDir -and (Test-Path -LiteralPath $scanDir)) {
            $candidates += Get-ChildItem -LiteralPath $scanDir -Recurse -Filter java.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        }
    }
    $cmd = Get-Command java -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    foreach ($c in ($candidates | Select-Object -Unique)) {
        if (-not $c) { continue }
        try {
            $v = (& $c -version 2>&1 | Out-String)
            if ($v -match (Get-JavaVersionPattern -Major $Major)) { return $c }
        } catch { }
    }
    return $null
}

function Install-JavaByMajor {
    param([int]$Major)
    $destDir = if ($script:javaInstallDir) { $script:javaInstallDir } else { 'D:\Java' }
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    $zipPath = Join-Path $destDir "OpenJDK${Major}U-jre.zip"
    $url = Get-JavaDownloadUrl -Major $Major
    Set-UiStatus "正在下载 Java $Major（清华镜像，请稍候）..."
    [System.Windows.Forms.Application]::DoEvents()
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
    Set-UiStatus "正在解压 Java $Major..."
    [System.Windows.Forms.Application]::DoEvents()
    Expand-Archive -LiteralPath $zipPath -DestinationPath $destDir -Force
    return Find-JavaByMajor -Major $Major
}

function Install-ForgeServer {
    param([string]$ServerDir)
    $installer = Get-ChildItem -LiteralPath $ServerDir -Filter 'forge-*-installer.jar' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $installer) { $installer = Get-ChildItem -LiteralPath $ServerDir -Filter 'neoforge-*-installer.jar' -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if (-not $installer) { return '未找到 Forge/NeoForge 安装器' }

    # 1. 输入/确认 Minecraft 版本
    $detected = $script:freshMcVersion
    if (-not $detected) { $detected = Get-McVersionFromInstaller -ServerDir $ServerDir }
    Add-Type -AssemblyName Microsoft.VisualBasic
    $mcVer = [Microsoft.VisualBasic.Interaction]::InputBox("请输入 Minecraft 版本（例如 1.20.1）：`r`n将根据版本选择对应的 Java（1.17~1.20.4 用 17，1.20.5+ / 1.21 用 21，1.16 及以下用 8）。", 'Forge 安装', $detected)
    if (-not $mcVer) { return '已取消' }
    $mcVer = $mcVer.Trim()

    # 2. 查找对应 Java
    $major = Get-RequiredJavaMajor -McVersion $mcVer
    $useJava = $null
    if ($script:javaPath -and (Test-Path -LiteralPath $script:javaPath)) {
        $v = (& $script:javaPath -version 2>&1 | Out-String)
        if ($v -match (Get-JavaVersionPattern -Major $major)) { $useJava = $script:javaPath }
    }
    if (-not $useJava) { $useJava = Find-JavaByMajor -Major $major }
    if (-not $useJava) {
        $r = [System.Windows.Forms.MessageBox]::Show("未找到 Java $major，需要下载安装（Adoptium 官方源，约 40MB）。`r`n要现在下载吗？", 'Java', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
            $useJava = Install-JavaByMajor -Major $major
        }
    }
    if (-not $useJava) { return "未找到 Java $major，无法安装。请手动安装 Java $major 或点'选择'指定 java.exe。" }
    $script:javaMap[$ServerDir] = $useJava
    Save-Settings

    # 3. 运行安装器
    Set-UiStatus "正在用 Java $major 运行 Forge 安装器（$($installer.Name)），需要联网下载，请稍候..."
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $proc = Start-Process -FilePath $useJava -ArgumentList @('-jar', $installer.Name, '--installServer') -WorkingDirectory $ServerDir -WindowStyle Hidden -PassThru
        while (-not $proc.HasExited) {
            Start-Sleep -Milliseconds 500
            [System.Windows.Forms.Application]::DoEvents()
        }
    } catch {
        return "安装器启动失败: $($_.Exception.Message)"
    }
    Set-UiStatus '安装器已结束，检查结果...'
    $argsTxt = Get-ChildItem -LiteralPath (Join-Path $ServerDir 'libraries\net\minecraftforge') -Recurse -Filter 'win_args.txt' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $argsTxt) {
        $argsTxt = Get-ChildItem -LiteralPath (Join-Path $ServerDir 'libraries\net\neoforged') -Recurse -Filter 'win_args.txt' -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $argsTxt) { return '安装完成但未生成运行文件（win_args.txt），可能是网络问题，请重试或手动运行安装器。' }
    return $null
}

function Download-VanillaServer {
    param([string]$ServerDir, [string]$McVersion)
    $jar = Join-Path $ServerDir 'server.jar'
    $url = "https://bmclapi2.bangbang93.com/version/$McVersion/server"
    Set-UiStatus "正在下载原版服务端 $McVersion（BMCLAPI 镜像）..."
    [System.Windows.Forms.Application]::DoEvents()
    try {
        Invoke-WebRequest -Uri $url -OutFile $jar -UseBasicParsing
    } catch {
        return "下载失败: $($_.Exception.Message)"
    }
    $size = (Get-Item -LiteralPath $jar).Length
    if ($size -lt 10MB) { return '下载的文件异常（可能版本号有误或镜像不可用）。' }
    return $null
}

function Test-ServerRunning {
    if ($script:serverProc -and -not $script:serverProc.HasExited) {
        $script:cachedServerRunning = $true
        return $true
    }
    $now = [Environment]::TickCount
    if (($now - $script:lastPortCheck) -gt 1500) {
        $script:lastPortCheck = $now
        $script:cachedServerRunning = Test-PortListen (Get-ServerPort)
    }
    return $script:cachedServerRunning
}

function Get-RunningOverview {
    $lines = @()
    $dirs = @($script:serverProfiles.Keys)
    if ($dirs.Count -eq 0 -and $script:serverDir) { $dirs = @($script:serverDir) }

    # ---------- MC 服务器（按各档案 server.properties 的端口检测） ----------
    $mcFound = $false
    foreach ($dir in $dirs) {
        $sp = Join-Path $dir 'server.properties'
        if (-not (Test-Path -LiteralPath $sp)) { continue }
        $port = 25565
        $pl = Get-Content -LiteralPath $sp -Encoding UTF8 | Where-Object { $_ -match '^server-port\s*=' } | Select-Object -First 1
        if ($pl) { try { $port = [int](($pl -split '=', 2)[1].Trim()) } catch { } }
        if (Test-PortListen $port) {
            $mcFound = $true
            $name = if ($script:serverProfiles.ContainsKey($dir) -and $script:serverProfiles[$dir].name) { $script:serverProfiles[$dir].name } else { [System.IO.Path]::GetFileName($dir.TrimEnd('\')) }
            $lines += "[MC 服务器] $name  ($dir) —— 端口 $port 正在监听"
        }
    }
    if (-not $mcFound) { $lines += '[MC 服务器] 未检测到运行中的服务器（所有档案的端口均未监听）' }

    # ---------- frpc（枚举全部 frpc 进程，解析 -c 配置文件归属） ----------
    $frpcs = @(Get-Process -Name frpc -ErrorAction SilentlyContinue)
    if ($frpcs.Count -eq 0) {
        $lines += '[frpc] 没有运行中的 frpc 进程'
    } else {
        foreach ($p in $frpcs) {
            $cfg = ''
            try {
                $procInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $($p.Id)" -ErrorAction Stop
                $cmd = [string]$procInfo.CommandLine
                if ($cmd -match '-c\s+"([^"]+)"') { $cfg = $matches[1].Trim() }
                elseif ($cmd -match '-c\s+(\S+)') { $cfg = $matches[1].Trim() }
            } catch { }
            $owner = ''
            if ($cfg) {
                foreach ($dir in $dirs) {
                    $dirCfg = Join-Path $dir 'frpc.toml'
                    if ($cfg -ieq $dirCfg) {
                        $owner = if ($script:serverProfiles.ContainsKey($dir) -and $script:serverProfiles[$dir].name) { $script:serverProfiles[$dir].name } else { [System.IO.Path]::GetFileName($dir.TrimEnd('\')) }
                        $owner = $owner + '  (' + $dir + ')'
                        break
                    }
                    if ($script:serverProfiles.ContainsKey($dir) -and $script:serverProfiles[$dir].frpcCfg -and $cfg -ieq [string]$script:serverProfiles[$dir].frpcCfg) {
                        $owner = $script:serverProfiles[$dir].name + '  (' + $dir + ')'
                        break
                    }
                }
            }
            if (-not $owner -and $p.Path) {
                foreach ($dir in $dirs) {
                    if ($script:serverProfiles.ContainsKey($dir) -and $script:serverProfiles[$dir].frpcExe -and $p.Path -ieq [string]$script:serverProfiles[$dir].frpcExe) {
                        $owner = $script:serverProfiles[$dir].name + '  (' + $dir + ')'
                        break
                    }
                }
            }
            if ($owner) { $lines += "[frpc] PID $($p.Id) → $owner" }
            elseif ($cfg) { $lines += "[frpc] PID $($p.Id) → 配置文件 $cfg （不在已保存的服务器档案中）" }
            else { $lines += "[frpc] PID $($p.Id) → 无法定位配置文件（可能由其它方式启动）" }
        }
    }
    return $lines
}

function Find-Java21 {
    $candidates = @()
    foreach ($scanDir in @($script:javaInstallDir, 'D:\Java')) {
        if ($scanDir -and (Test-Path -LiteralPath $scanDir)) {
            $candidates += Get-ChildItem -LiteralPath $scanDir -Recurse -Filter java.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        }
    }
    $cmd = Get-Command java -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    foreach ($c in $candidates) {
        if (-not $c) { continue }
        try {
            $v = (& $c -version 2>&1 | Out-String)
            if ($v -match 'version "21') {
                $script:javaPath = $c
                return $c
            }
        } catch { }
    }
    return $null
}

function Install-Java21 {
    $destDir = if ($script:javaInstallDir) { $script:javaInstallDir } else { 'D:\Java' }
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    $zipPath = Join-Path $destDir 'OpenJDK21U-jre_x64_windows_hotspot_21.0.12_8.zip'
    $url = 'https://mirrors.tuna.tsinghua.edu.cn/Adoptium/21/jre/x64/windows/OpenJDK21U-jre_x64_windows_hotspot_21.0.12_8.zip'
    Set-UiStatus '正在下载 Java 21（约 47MB，请稍候）...'
    [System.Windows.Forms.Application]::DoEvents()
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
    Set-UiStatus '正在解压 Java 21...'
    [System.Windows.Forms.Application]::DoEvents()
    Expand-Archive -LiteralPath $zipPath -DestinationPath $destDir -Force
    return Find-Java21
}

function Update-PropertyFile {
    param([string]$FilePath, [hashtable]$Changes)
    if (-not (Test-Path -LiteralPath $FilePath)) { return }
    $lines = @(Get-Content -LiteralPath $FilePath -Encoding UTF8)
    $newLines = @()
    foreach ($line in $lines) {
        $matched = $false
        foreach ($key in $Changes.Keys) {
            if ($line -match "^$([regex]::Escape($key))\s*=") {
                $newLines += "$key=$($Changes[$key])"
                $matched = $true
                break
            }
        }
        if (-not $matched) { $newLines += $line }
    }
    foreach ($key in $Changes.Keys) {
        if (-not ($newLines | Where-Object { $_ -match "^$([regex]::Escape($key))\s*=" })) {
            $newLines += "$key=$($Changes[$key])"
        }
    }
    Set-Content -LiteralPath $FilePath -Value $newLines -Encoding ASCII
}

function Ensure-Rcon {
    $p = Join-Path $script:serverDir 'server.properties'
    if (-not (Test-Path -LiteralPath $p)) { return }
    $changes = @{
        'enable-rcon'    = 'true'
        'rcon.port'      = '25575'
        'rcon.password'  = New-RandomPassword
    }
    Update-PropertyFile -FilePath $p -Changes $changes
}

function New-RconPacket {
    param([int]$RequestId, [int]$Type, [byte[]]$Payload)
    $body = New-Object byte[] ($Payload.Length + 2)
    [Array]::Copy($Payload, $body, $Payload.Length)
    $body[$body.Length - 2] = 0
    $body[$body.Length - 1] = 0
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([int]($body.Length + 8))
    $bw.Write([int]$RequestId)
    $bw.Write([int]$Type)
    $bw.Write($body)
    $bw.Flush()
    return $ms.ToArray()
}

function Read-RconResponse {
    param($Stream)
    $br = New-Object System.IO.BinaryReader($Stream)
    $len = $br.ReadInt32()
    $reqId = $br.ReadInt32()
    $type = $br.ReadInt32()
    $payloadLen = $len - 10
    if ($payloadLen -lt 0) { $payloadLen = 0 }
    $payload = $br.ReadBytes($payloadLen)
    if ($len - $payloadLen - 10 -gt 0) { $br.ReadBytes($len - $payloadLen - 10) | Out-Null }
    return @{ RequestId = $reqId; Type = $type; Payload = $payload }
}

function Send-RconCommand {
    param([string]$Command)
    if (-not $script:serverDir) { return '[RCON] 未选择服务器目录' }
    $pass = Get-RconPassword
    if (-not $pass) { return '[RCON] server.properties 没有 rcon 密码（启动时会自动生成）' }
    $port = Get-RconPort
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect('127.0.0.1', $port)
        $client.ReceiveTimeout = 15000
        $client.SendTimeout = 15000
        $stream = $client.GetStream()
        $stream.ReadTimeout = 15000
        $stream.WriteTimeout = 15000
        $reqId = Get-Random -Minimum 100000 -Maximum 999999

        $login = New-RconPacket -RequestId $reqId -Type 3 -Payload ([System.Text.Encoding]::ASCII.GetBytes($pass))
        $stream.Write($login, 0, $login.Length)
        $stream.Flush()
        $resp = Read-RconResponse -Stream $stream
        if ($resp.Type -ne 2) {
            $client.Close()
            return '[RCON] 登录失败（密码错误？）'
        }

        $cmdBytes = [System.Text.Encoding]::UTF8.GetBytes($Command)
        $pkt = New-RconPacket -RequestId $reqId -Type 2 -Payload $cmdBytes
        $stream.Write($pkt, 0, $pkt.Length)
        $stream.Flush()
        $resp2 = Read-RconResponse -Stream $stream
        $client.Close()
        if ($resp2.Payload -and $resp2.Payload.Length -gt 0) {
            return [System.Text.Encoding]::UTF8.GetString($resp2.Payload)
        }
        return '(命令已发送)'
    } catch {
        return "[RCON] 发送失败: $($_.Exception.Message)"
    }
}

function Start-MCServer {
    if (-not $script:serverDir -or -not (Test-Path -LiteralPath $script:serverDir)) {
        [System.Windows.Forms.MessageBox]::Show('请先在"总览"页选择服务器目录。', '提示', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $script:lastPortCheck = 0
    if (Test-ServerRunning) {
        [System.Windows.Forms.MessageBox]::Show('检测到服务器已经在运行（端口 ' + (Get-ServerPort) + ' 被占用），不会重复启动。如需重启请先点"停止服务器"。', '提示') | Out-Null
        return
    }
    $useJava = $script:javaPath
    if ($script:javaMap.ContainsKey($script:serverDir)) { $useJava = $script:javaMap[$script:serverDir] }
    if (-not $script:javaMap.ContainsKey($script:serverDir)) {
        $mcVer = Get-McVersionFromServerDir -Dir $script:serverDir
        if ($mcVer) {
            $major = Get-RequiredJavaMajor -McVersion $mcVer
            $j = Find-JavaByMajor -Major $major
            if ($j) {
                $script:javaMap[$script:serverDir] = $j
                $useJava = $j
                $script:javaPath = $j
                $script:txtJava.Text = $j
                Save-Settings
            }
        }
    }
    if (-not $useJava -or -not (Test-Path -LiteralPath $useJava)) {
        [System.Windows.Forms.MessageBox]::Show('未找到对应的 Java（请先在"总览"页设置 java.exe 路径）。', '提示') | Out-Null
        return
    }
    $launch = Get-ServerLaunchInfo
    if (-not $launch) {
        $installer = Get-ChildItem -LiteralPath $script:serverDir -Filter 'forge-*-installer.jar' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $installer) { $installer = Get-ChildItem -LiteralPath $script:serverDir -Filter 'neoforge-*-installer.jar' -ErrorAction SilentlyContinue | Select-Object -First 1 }
        if ($installer) {
            $r = [System.Windows.Forms.MessageBox]::Show("检测到 $($installer.Name)`r`n这是未安装的 Forge/NeoForge 服务端，需要先运行安装器生成运行文件（需联网，约几分钟）。`r`n现在自动安装并启动吗？", 'Forge 安装器', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
                $installResult = Install-ForgeServer -ServerDir $script:serverDir
                if ($installResult) {
                    [System.Windows.Forms.MessageBox]::Show($installResult, '安装失败', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
                    return
                }
                if ($script:javaMap.ContainsKey($script:serverDir)) { $useJava = $script:javaMap[$script:serverDir] }
                $launch = Get-ServerLaunchInfo
            }
        }
        if (-not $launch) {
            $r = [System.Windows.Forms.MessageBox]::Show("目录里没有任何服务端文件。是否自动下载原版 server.jar 并启动？`r`n（原版不加载模组；模组包需要对应的 Fabric/Forge 已安装）", '下载原版服务端', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
                $mcVer = $script:freshMcVersion
                if (-not $mcVer) {
                    Add-Type -AssemblyName Microsoft.VisualBasic
                    $mcVer = [Microsoft.VisualBasic.Interaction]::InputBox('请输入 Minecraft 版本（例如 1.21.1）：', 'Minecraft 版本', '1.21.1')
                    if (-not $mcVer) { return }
                    $mcVer = $mcVer.Trim()
                }
                $dlResult = Download-VanillaServer -ServerDir $script:serverDir -McVersion $mcVer
                if ($dlResult) {
                    [System.Windows.Forms.MessageBox]::Show($dlResult, '下载失败', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
                    return
                }
                $launch = Get-ServerLaunchInfo
            }
        }
        if (-not $launch) {
        [System.Windows.Forms.MessageBox]::Show('服务器目录里没有可识别的启动文件（Fabric / NeoForge / Forge / server.jar），无法启动。', '错误') | Out-Null
        return
        }
    }

    # 确保 eula 与 rcon
    $eula = Join-Path $script:serverDir 'eula.txt'
    if (Test-Path -LiteralPath $eula) {
        $eulaText = Get-Content -LiteralPath $eula -Raw -Encoding UTF8
        if ($eulaText -notmatch 'eula=true') {
            Set-Content -LiteralPath $eula -Value "eula=true`r`n" -Encoding ASCII
        }
    } else {
        Set-Content -LiteralPath $eula -Value "eula=true`r`n" -Encoding ASCII
    }
    Ensure-Rcon

    $args = @()
    $agentArg = ''
    if ($script:authMode -eq 'thirdparty' -and $script:skinStation -ne '离线模式') {
        $agentArg = Get-AuthJavaAgentArg -ServerDir $script:serverDir
        if ($agentArg) { $args += $agentArg }
    }
    $agentMissing = $false
    $spFile = Join-Path $script:serverDir 'server.properties'
    if (Test-Path -LiteralPath $spFile) {
        # 第三方皮肤站必须 online-mode=true，服务器才能把皮肤分发给所有客户端；
        # 若缺少 authlib-injector 则退回离线模式并提示，避免所有玩家无法进服。
        $expectedOnline = 'false'
        if ($script:authMode -eq 'premium') {
            $expectedOnline = 'true'
        } elseif ($script:authMode -eq 'thirdparty' -and $script:skinStation -ne '离线模式') {
            if ($agentArg) { $expectedOnline = 'true' } else { $agentMissing = $true }
        }
        Update-PropertyFile -FilePath $spFile -Changes @{ 'online-mode' = $expectedOnline }
    }
    $args += '-Xmx' + $script:maxMem + 'G'
    $args += '-Xms1G'
    $args += $launch.Args

    $script:consolePos = 0
    Set-UiStatus '正在启动服务器...'
    try {
        $proc = Start-Process -FilePath $useJava -ArgumentList $args -WorkingDirectory $script:serverDir -WindowStyle Hidden -PassThru
        $script:serverProc = $proc
        Save-Settings
        $script:txtConsole.AppendText("`r`n[系统] 服务器已启动 (PID $($proc.Id))，等待 Done...`r`n")
        Set-UiStatus "服务器启动中 (PID $($proc.Id))"
        if ($agentMissing) {
            [System.Windows.Forms.MessageBox]::Show('未找到 authlib-injector.jar，服务器已退回离线模式(online-mode=false)，皮肤需要客户端解析。请确认服务器目录里有 authlib-injector.jar。', '提示') | Out-Null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show('启动失败: ' + $_.Exception.Message, '错误') | Out-Null
    }
}

function Stop-MCServer {
    if (-not (Test-ServerRunning)) {
        $script:serverProc = $null
        Set-UiStatus '服务器未运行'
        return
    }
    Set-UiStatus '正在停止服务器...'
    Send-RconFireForget -Command 'stop' | Out-Null
    for ($i = 0; $i -lt 24; $i++) {
        Start-Sleep -Milliseconds 500
        if (-not (Test-ServerRunning)) { break }
    }
    if (Test-ServerRunning) {
        if ($script:serverProc -and -not $script:serverProc.HasExited) {
            Stop-Process -Id $script:serverProc.Id -Force -ErrorAction SilentlyContinue
        }
        $conn = Get-NetTCPConnection -LocalPort (Get-ServerPort) -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($conn) { Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue }
    }
    $script:serverProc = $null
    $script:consolePos = 0
    Set-UiStatus '服务器已停止'
}

function Update-ConsoleView {
    if (-not $script:serverDir) { return }
    $logPath = Join-Path $script:serverDir 'logs\latest.log'
    if (-not (Test-Path -LiteralPath $logPath)) { return }
    try {
        $fs = [System.IO.File]::Open($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            if ($fs.Length -lt $script:consolePos) { $script:consolePos = 0 }
            $fs.Seek($script:consolePos, [System.IO.SeekOrigin]::Begin) | Out-Null
            $remaining = $fs.Length - $fs.Position
            if ($remaining -gt 0) {
                if ($remaining -gt 262144) {
                    $fs.Seek(-262144, [System.IO.SeekOrigin]::End) | Out-Null
                    $script:consolePos = $fs.Position
                    $remaining = $fs.Length - $fs.Position
                }
                $buf = New-Object byte[] $remaining
                $read = 0
                while ($read -lt $remaining) {
                    $n = $fs.Read($buf, $read, $remaining - $read)
                    if ($n -le 0) { break }
                    $read += $n
                }
                $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
                $script:consolePos = $fs.Position
                if ($text.Length -gt 0) {
                    $script:txtConsole.AppendText($text)
                    if ($script:txtConsole.TextLength -gt 500000) {
                        $script:txtConsole.Text = $script:txtConsole.Text.Substring($script:txtConsole.TextLength - 400000)
                    }
                    $script:txtConsole.SelectionStart = $script:txtConsole.TextLength
                    $script:txtConsole.ScrollToCaret()
                }
            }
        } finally {
            $fs.Dispose()
        }
    } catch { }
}

function Get-FrpcProcesses {
    $procs = @(Get-Process -Name frpc -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return @() }
    if ($script:frpcExe) {
        $target = $script:frpcExe.ToLower()
        $matched = @($procs | Where-Object { $_.Path -and $_.Path.ToLower() -eq $target })
        if ($matched.Count -gt 0) { return $matched }
    }
    return $procs
}

function Start-Frpc {
    if (-not $script:frpcExe -or -not (Test-Path -LiteralPath $script:frpcExe)) {
        [System.Windows.Forms.MessageBox]::Show('请先选择 frpc.exe 路径。', '提示') | Out-Null
        return
    }
    if (-not $script:frpcCfg -or -not (Test-Path -LiteralPath $script:frpcCfg)) {
        [System.Windows.Forms.MessageBox]::Show('请先选择 frpc.toml 配置文件路径。', '提示') | Out-Null
        return
    }
    $running = @(Get-FrpcProcesses)
    if ($running.Count -gt 0) {
        $script:frpcProc = $running[0]
        $ids = ($running | ForEach-Object { $_.Id }) -join ', '
        [System.Windows.Forms.MessageBox]::Show("检测到 frpc 已经在运行（PID: $ids），已复用现有进程，不会重复启动。`r`n如需重启请先点'停止穿透'。", 'frpc') | Out-Null
        Set-UiStatus "frpc 已在运行 (PID $ids)"
        return
    }
    $workDir = Split-Path -Parent $script:frpcExe
    $stdout = Join-Path $workDir 'frpc-manager.log'
    $stderr = Join-Path $workDir 'frpc-manager.err.log'
    $script:frpcPos = 0
    try {
        $proc = Start-Process -FilePath $script:frpcExe -ArgumentList @('-c', $script:frpcCfg) -WorkingDirectory $workDir -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
        $script:frpcProc = $proc
        Save-Settings
        Set-UiStatus "frpc 已启动 (PID $($proc.Id))"
        $script:txtFrpc.AppendText("[系统] frpc 已启动`r`n")
    } catch {
        [System.Windows.Forms.MessageBox]::Show('frpc 启动失败: ' + $_.Exception.Message, '错误') | Out-Null
    }
}

function Stop-Frpc {
    $running = @(Get-FrpcProcesses)
    if ($running.Count -gt 0) {
        $ids = ($running | ForEach-Object { $_.Id }) -join ', '
        if ($script:frpcProc -and -not $script:frpcProc.HasExited) {
            $running | Stop-Process -Force -ErrorAction SilentlyContinue
            $script:frpcProc = $null
            Set-UiStatus 'frpc 已停止'
            $script:txtFrpc.AppendText("[系统] frpc 已停止（PID $ids）`r`n")
        } else {
            $r = [System.Windows.Forms.MessageBox]::Show("检测到 frpc.exe 正在运行（PID: $ids，可能是之前启动的），要结束它吗？", 'frpc', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
                $running | Stop-Process -Force -ErrorAction SilentlyContinue
                $script:frpcProc = $null
                Set-UiStatus 'frpc 已停止'
                $script:txtFrpc.AppendText("[系统] frpc 已停止（PID $ids）`r`n")
            }
        }
    } else {
        $script:frpcProc = $null
        Set-UiStatus 'frpc 未运行'
    }
}

function Update-FrpcView {
    if (-not $script:frpcProc) { return }
    $workDir = Split-Path -Parent $script:frpcExe
    $logPath = Join-Path $workDir 'frpc-manager.log'
    if (-not (Test-Path -LiteralPath $logPath)) { return }
    try {
        $fs = [System.IO.File]::Open($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            if ($fs.Length -lt $script:frpcPos) { $script:frpcPos = 0 }
            $fs.Seek($script:frpcPos, [System.IO.SeekOrigin]::Begin) | Out-Null
            $remaining = $fs.Length - $fs.Position
            if ($remaining -gt 0) {
                $buf = New-Object byte[] $remaining
                $read = 0
                while ($read -lt $remaining) {
                    $n = $fs.Read($buf, $read, $remaining - $read)
                    if ($n -le 0) { break }
                    $read += $n
                }
                $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
                $script:frpcPos = $fs.Position
                if ($text.Length -gt 0) {
                    $script:txtFrpc.AppendText($text)
                    if ($script:txtFrpc.TextLength -gt 300000) {
                        $script:txtFrpc.Text = $script:txtFrpc.Text.Substring($script:txtFrpc.TextLength - 200000)
                    }
                    $script:txtFrpc.SelectionStart = $script:txtFrpc.TextLength
                    $script:txtFrpc.ScrollToCaret()
                }
            }
        } finally {
            $fs.Dispose()
        }
    } catch { }
}

function Update-StatusBar {
    $procAlive = $script:serverProc -and -not $script:serverProc.HasExited
    $now = [Environment]::TickCount
    if (($now - $script:lastPortCheck) -gt 1500) {
        $script:lastPortCheck = $now
        $script:cachedServerRunning = Test-PortListen (Get-ServerPort)
    }
    $portUp = $script:cachedServerRunning
    if ($procAlive) {
        $serverState = if ($portUp) { '运行中' } else { '启动中' }
    } elseif ($portUp) {
        $serverState = '运行中'
    } else {
        $serverState = '未运行'
    }
    if ($serverState -eq '运行中' -and $script:serverDir) {
        $logPath = Join-Path $script:serverDir 'logs\latest.log'
        if (Test-Path -LiteralPath $logPath) {
            $age = (Get-Date) - (Get-Item -LiteralPath $logPath).LastWriteTime
            if ($age.TotalMinutes -gt 5) { $serverState = '疑似无响应' }
        }
    }
    $frpcRunning = @(Get-FrpcProcesses)
    $frpcState = if ($frpcRunning.Count -gt 0) { '运行中' } else { '未运行' }
    $dir = if ($script:serverDir) { $script:serverDir } else { '未选择' }
    if ($script:lblServerState) {
        $script:lblServerState.Text = "[$serverState]"
        $script:lblServerState.ForeColor = switch ($serverState) {
            '运行中'     { [System.Drawing.Color]::ForestGreen }
            '启动中'     { [System.Drawing.Color]::Orange }
            '疑似无响应' { [System.Drawing.Color]::IndianRed }
            default      { [System.Drawing.Color]::Gray }
        }
    }
    if ($script:lblFrpcState) {
        $script:lblFrpcState.Text = "[$frpcState]"
        $script:lblFrpcState.ForeColor = if ($frpcState -eq '运行中') { [System.Drawing.Color]::ForestGreen } else { [System.Drawing.Color]::Gray }
    }
    if ($script:lblStatus) { $script:lblStatus.Text = " | 目录: $dir" }
}

function Update-TunnelView {
    if (-not $script:txtTunnelIp) { return }
    $ip = ''
    $cfg = $script:frpcCfg
    if (-not $cfg -and $script:serverDir) { $cfg = Join-Path $script:serverDir 'frpc.toml' }
    if ($cfg -and (Test-Path -LiteralPath $cfg)) {
        $line = Get-Content -LiteralPath $cfg -Encoding UTF8 | Where-Object { $_ -match '^\s*serverAddr\s*=' } | Select-Object -First 1
        if ($line -match '^\s*serverAddr\s*=\s*"([^"]+)"') { $ip = $matches[1] }
    }
    if ($script:txtTunnelIp.Text -ne $ip) { $script:txtTunnelIp.Text = $ip }
    $running = @(Get-FrpcProcesses)
    if ($running.Count -gt 0) {
        $ids = ($running | ForEach-Object { $_.Id }) -join ', '
        $port = Get-ServerPort
        if ($ip) { $script:lblTunnelState.Text = "frpc 运行中 (PID $ids) → 玩家地址 $ip`:$port" }
        else { $script:lblTunnelState.Text = "frpc 运行中 (PID $ids)（未读取到云服务器 IP）" }
    } else {
        $script:lblTunnelState.Text = 'frpc 未运行（启动后外地朋友可连）'
    }
}

function Get-WhitelistNames {
    if (-not $script:serverDir) { return @() }
    $p = Join-Path $script:serverDir 'whitelist.json'
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    try {
        $data = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
        return @($data | ForEach-Object { $_.name })
    } catch { return @() }
}

function Get-OpNames {
    if (-not $script:serverDir) { return @() }
    $p = Join-Path $script:serverDir 'ops.json'
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    try {
        $data = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
        return @($data | ForEach-Object { $_.name })
    } catch { return @() }
}

function Write-OpsJson {
    param([object[]]$Ops, [string]$Path)
    $json = '[' + (($Ops | ForEach-Object { $_ | ConvertTo-Json -Compress }) -join ',') + ']'
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Remove-OpFromFile {
    param([string]$Name)
    $p = Join-Path $script:serverDir 'ops.json'
    if (-not (Test-Path -LiteralPath $p)) { return '找不到 ops.json' }
    try {
        $data = @(Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json)
        $remaining = @($data | Where-Object { $_.name -ine $Name })
        Write-OpsJson -Ops $remaining -Path $p
        return "已从 ops.json 移除 $Name"
    } catch {
        return "修改 ops.json 失败: $($_.Exception.Message)"
    }
}

function Add-OpToFile {
    param([string]$Name)
    $wlPath = Join-Path $script:serverDir 'whitelist.json'
    $opPath = Join-Path $script:serverDir 'ops.json'
    $uuid = ''
    if (Test-Path -LiteralPath $wlPath) {
        $wl = @(Get-Content -LiteralPath $wlPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        $match = @($wl | Where-Object { $_.name -ieq $Name })
        if ($match.Count -gt 0) { $uuid = $match[0].uuid }
    }
    if (-not $uuid) { return "找不到 $Name 的 UUID（玩家不在白名单里），无法离线添加 OP" }
    $ops = @()
    if (Test-Path -LiteralPath $opPath) { $ops = @(Get-Content -LiteralPath $opPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
    $ops = @($ops | Where-Object { $_.name -ine $Name })
    $ops += [pscustomobject]@{ uuid = $uuid; name = $Name; level = 4; bypassesPlayerLimit = $false }
    Write-OpsJson -Ops $ops -Path $opPath
    return "已在 ops.json 添加 $Name（OP 等级 4）"
}

function Remove-WhitelistFromFile {
    param([string]$Name)
    $p = Join-Path $script:serverDir 'whitelist.json'
    if (-not (Test-Path -LiteralPath $p)) { return '找不到 whitelist.json' }
    try {
        $data = @(Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json)
        $remaining = @($data | Where-Object { $_.name -ine $Name })
        $json = '[' + (($remaining | ForEach-Object { $_ | ConvertTo-Json -Compress }) -join ',') + ']'
        [System.IO.File]::WriteAllText($p, $json, (New-Object System.Text.UTF8Encoding($false)))
        return "已从 whitelist.json 移除 $Name"
    } catch {
        return "修改 whitelist.json 失败: $($_.Exception.Message)"
    }
}

function Send-RconFireForget {
    param([string]$Command)
    if (-not $script:serverDir) { return '[RCON] 未选择服务器目录' }
    $pass = Get-RconPassword
    if (-not $pass) { return '[RCON] 没有 rcon 密码' }
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect('127.0.0.1', (Get-RconPort))
        $client.ReceiveTimeout = 8000
        $client.SendTimeout = 8000
        $stream = $client.GetStream()
        $stream.ReadTimeout = 8000
        $stream.WriteTimeout = 8000
        $rid = Get-Random -Minimum 100000 -Maximum 999999
        $login = New-RconPacket -RequestId $rid -Type 3 -Payload ([System.Text.Encoding]::ASCII.GetBytes($pass))
        $stream.Write($login, 0, $login.Length)
        $stream.Flush()
        $br = New-Object System.IO.BinaryReader($stream)
        $len = $br.ReadInt32()
        $respId = $br.ReadInt32()
        $type = $br.ReadInt32()
        $payloadLen = [Math]::Max(0, $len - 10)
        if ($payloadLen -gt 0) { $null = $br.ReadBytes($payloadLen) }
        try { $null = $br.ReadBytes(2) } catch { }
        if ($type -ne 2) {
            $client.Close()
            return '[RCON] 登录失败（密码不匹配）'
        }
        $pkt = New-RconPacket -RequestId $rid -Type 2 -Payload ([System.Text.Encoding]::UTF8.GetBytes($Command))
        $stream.Write($pkt, 0, $pkt.Length)
        $stream.Flush()
        # 读取服务器响应（超时由 stream.ReadTimeout 控制），确认指令已被执行
        $rlen = $br.ReadInt32()
        $rid2 = $br.ReadInt32()
        $rtype2 = $br.ReadInt32()
        $rpayloadLen = [Math]::Max(0, $rlen - 10)
        $rpayload = New-Object byte[] $rpayloadLen
        $got = 0
        while ($got -lt $rpayloadLen) {
            $n = $stream.Read($rpayload, $got, $rpayloadLen - $got)
            if ($n -le 0) { break }
            $got += $n
        }
        try { $null = $br.ReadBytes(2) } catch { }
        $client.Close()
        return $null
    } catch {
        return "[RCON] $($_.Exception.Message)"
    }
}

function Wait-FileCondition {
    param([scriptblock]$Condition, [int]$TimeoutSeconds = 8)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if (& $Condition) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Read-OpNamesStrict {
    $p = Join-Path $script:serverDir 'ops.json'
    if (-not (Test-Path -LiteralPath $p)) { throw 'ops.json 不存在' }
    $data = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($data | ForEach-Object { $_.name })
}

function Read-WhitelistNamesStrict {
    $p = Join-Path $script:serverDir 'whitelist.json'
    if (-not (Test-Path -LiteralPath $p)) { throw 'whitelist.json 不存在' }
    $data = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($data | ForEach-Object { $_.name })
}

function Resolve-PlayerUuid {
    param([string]$Name)
    try {
        $body = @($Name) | ConvertTo-Json
        $resp = Invoke-RestMethod -Uri 'https://mcskin.com.cn/api/yggdrasil/api/profiles/minecraft' -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 10
        if ($resp -and $resp[0] -and $resp[0].id) {
            $id = [string]$resp[0].id
            return ($id -replace '^(.{8})(.{4})(.{4})(.{4})(.{12})$', '$1-$2-$3-$4-$5')
        }
    } catch { }
    return ''
}

function Add-WhitelistByUuid {
    param([string]$Name, [string]$Uuid)
    $p = Join-Path $script:serverDir 'whitelist.json'
    $data = @()
    if (Test-Path -LiteralPath $p) { $data = @(Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json) }
    $data = @($data | Where-Object { $_.name -ine $Name })
    $data += [pscustomobject]@{ uuid = $Uuid; name = $Name }
    $json = '[' + (($data | ForEach-Object { $_ | ConvertTo-Json -Compress }) -join ',') + ']'
    [System.IO.File]::WriteAllText($p, $json, (New-Object System.Text.UTF8Encoding($false)))
    return "已在 whitelist.json 添加 $Name（UUID $Uuid）"
}

function Invoke-OpChange {
    param([string]$Name, [bool]$MakeOp)
    # 先直接改文件（列表立即更新），服务器在线时再发指令让服务器内存同步
    if ($MakeOp) { $editMsg = Add-OpToFile $Name } else { $editMsg = Remove-OpFromFile $Name }
    if ($editMsg -like '找不到*') { return $editMsg }
    if (Test-ServerRunning) {
        $cmd = if ($MakeOp) { "op $Name" } else { "deop $Name" }
        $sent = Send-RconFireForget -Command $cmd
        if ($sent) { return "文件已修改（$editMsg），但 RCON 发送失败：$sent。建议重启服务器让改动稳定生效。" }
        return $null
    }
    return "服务器未运行，已直接修改（$editMsg）。"
}

function Invoke-WhitelistRemove {
    param([string]$Name)
    $editMsg = Remove-WhitelistFromFile $Name
    if ($editMsg -like '找不到*') { return $editMsg }
    if (Test-ServerRunning) {
        $sent = Send-RconFireForget -Command "whitelist remove $Name"
        if ($sent) { return "文件已修改（$editMsg），但 RCON 发送失败：$sent。建议重启服务器让改动稳定生效。" }
        return $null
    }
    return "服务器未运行，已直接修改（$editMsg）。"
}

function Invoke-WhitelistAdd {
    param([string]$Name, [int]$TimeoutSeconds = 8)
    if (Test-ServerRunning) {
        $sent = Send-RconFireForget -Command "whitelist add $Name"
        if (-not $sent) {
            $ok = Wait-FileCondition -Condition {
                try { (@(Read-WhitelistNamesStrict) | Where-Object { $_ -ieq $Name }).Count -gt 0 } catch { $false }
            } -TimeoutSeconds $TimeoutSeconds
            if ($ok) { return $null }
        }
        # RCON 不可用或玩家未添加 → 走皮肤站 API 解析 UUID 直接写文件
        $uuid = Resolve-PlayerUuid $Name
        if (-not $uuid) { return "无法从皮肤站解析 $Name 的 UUID（可能还没注册）。请让 $Name 先在红石皮肤站注册并登录一次。" }
        $msg = Add-WhitelistByUuid $Name $uuid
        return "RCON 未确认，已通过皮肤站解析 UUID 直接写入白名单：$msg（服务器运行中建议重启生效）"
    }
    $uuid = Resolve-PlayerUuid $Name
    if (-not $uuid) { return "服务器未运行，且无法从皮肤站解析 $Name 的 UUID（可能还没注册）。请让 $Name 先在红石皮肤站注册并登录一次。" }
    $msg = Add-WhitelistByUuid $Name $uuid
    return "服务器未运行，已通过皮肤站解析 UUID 直接写入白名单：$msg"
}

function Refresh-PlayerList {
    $script:lstPlayers.Items.Clear()
    $names = Get-WhitelistNames
    $opSet = @{}
    foreach ($op in (Get-OpNames)) { $opSet[$op.ToLower()] = $true }
    $opCount = 0
    foreach ($n in $names) {
        if ($opSet.ContainsKey($n.ToLower())) {
            [void]$script:lstPlayers.Items.Add($n + '  [OP]')
            $opCount++
        } else {
            [void]$script:lstPlayers.Items.Add($n)
        }
    }
    $wlPath = if ($script:serverDir) { Join-Path $script:serverDir 'whitelist.json' } else { '' }
    $fileInfo = if ($script:serverDir -and (Test-Path -LiteralPath $wlPath)) {
        "白名单文件: $wlPath（共 $($names.Count) 人，管理员 $opCount 人）"
    } else {
        '未找到 whitelist.json'
    }
    if (Test-ServerRunning) {
        $script:lblPlayersHint.Text = "服务器在线：可直接添加/移除/OP，标 [OP] 的是管理员。$fileInfo"
    } else {
        $script:lblPlayersHint.Text = "服务器离线：显示白名单文件中的玩家，标 [OP] 的是管理员。$fileInfo"
    }
}

function Refresh-ModList {
    if (-not $script:serverDir) { return }
    $script:lstMods.Items.Clear()
    $script:modItems = @()
    $modsDir = Join-Path $script:serverDir 'mods'
    if (-not (Test-Path -LiteralPath $modsDir)) { return }
    foreach ($f in (Get-ChildItem -LiteralPath $modsDir -File)) {
        if ($f.Name -like '*.jar') {
            $script:modItems += @{ Path = $f.FullName; Name = $f.Name; Disabled = $false }
            [void]$script:lstMods.Items.Add($f.Name)
        } elseif ($f.Name -like '*.jar.disabled') {
            $script:modItems += @{ Path = $f.FullName; Name = $f.Name; Disabled = $true }
            [void]$script:lstMods.Items.Add($f.Name + '  [已禁用]')
        }
    }
}

function Load-QuickConfigFromServer {
    if (-not $script:comboDiff) { return }
    if (-not $script:serverDir) { return }
    $spPath = Join-Path $script:serverDir 'server.properties'
    if (-not (Test-Path -LiteralPath $spPath)) { return }
    $sp = Get-Content -LiteralPath $spPath -Encoding UTF8
    $get = { param($k) ($sp | Where-Object { $_ -match "^$k\s*=" } | Select-Object -First 1) -replace "^$k\s*=", '' }
    $diff = (& $get 'difficulty').Trim()
    if ($script:comboDiff.Items.Contains($diff)) { $script:comboDiff.SelectedItem = $diff } else { $script:comboDiff.SelectedIndex = 0 }
    $gm = (& $get 'gamemode').Trim()
    if ($script:comboGm.Items.Contains($gm)) { $script:comboGm.SelectedItem = $gm } else { $script:comboGm.SelectedIndex = 0 }
    if ($script:txtGamePort) { $script:txtGamePort.Text = (& $get 'server-port').Trim() }
    if ($script:txtFrpPort) {
        $p = Get-FrpcPorts
        $script:txtFrpPort.Text = "$($p.FrpPort)"
        $script:txtVoicePort.Text = "$($p.VoicePort)"
    }
    $script:txtMotd.Text = (& $get 'motd').Trim()
    $script:txtMaxPlayers.Text = (& $get 'max-players').Trim()
    $script:chkPvp.Checked = ((& $get 'pvp').Trim() -eq 'true')
    $script:chkWhitelist.Checked = ((& $get 'white-list').Trim() -eq 'true')
    $script:chkForce.Checked = ((& $get 'force-gamemode').Trim() -eq 'true')
    $script:chkCmdBlock.Checked = ((& $get 'enable-command-block').Trim() -eq 'true')
    $script:chkOnline.Checked = ((& $get 'online-mode').Trim() -eq 'true')
    $script:txtViewDist.Text = (& $get 'view-distance').Trim()
    $script:txtSimDist.Text = (& $get 'simulation-distance').Trim()
    $script:txtSpawnProtect.Text = (& $get 'spawn-protection').Trim()
    $script:txtIdleTimeout.Text = (& $get 'player-idle-timeout').Trim()
    $script:txtMaxTickTime.Text = (& $get 'max-tick-time').Trim()
    $script:txtMaxWorldSize.Text = (& $get 'max-world-size').Trim()
    $script:txtNetCompress.Text = (& $get 'network-compression-threshold').Trim()
    $script:txtOpLevel.Text = (& $get 'op-permission-level').Trim()
    $script:txtFuncLevel.Text = (& $get 'function-permission-level').Trim()
    $script:txtEntBroadcast.Text = (& $get 'entity-broadcast-range-percentage').Trim()
    $script:txtLevelName.Text = (& $get 'level-name').Trim()
    $script:txtLevelSeed.Text = (& $get 'level-seed').Trim()
    $script:txtLevelType.Text = (& $get 'level-type').Trim()
    $script:chkAllowFlight.Checked = ((& $get 'allow-flight').Trim() -eq 'true')
    $script:chkSpawnAnimals.Checked = ((& $get 'spawn-animals').Trim() -eq 'true')
    $script:chkSpawnMonsters.Checked = ((& $get 'spawn-monsters').Trim() -eq 'true')
    $script:chkSpawnNpcs.Checked = ((& $get 'spawn-npcs').Trim() -eq 'true')
    $script:chkHardcore.Checked = ((& $get 'hardcore').Trim() -eq 'true')
    $script:chkGenStructures.Checked = ((& $get 'generate-structures').Trim() -eq 'true')
    $script:chkAllowNether.Checked = ((& $get 'allow-nether').Trim() -eq 'true')
    $script:chkEnforceWhitelist.Checked = ((& $get 'enforce-whitelist').Trim() -eq 'true')
    $script:chkEnableStatus.Checked = ((& $get 'enable-status').Trim() -eq 'true')
    $script:chkEnableQuery.Checked = ((& $get 'enable-query').Trim() -eq 'true')
    $script:chkSyncChunkWrites.Checked = ((& $get 'sync-chunk-writes').Trim() -eq 'true')
    $script:chkHideOnline.Checked = ((& $get 'hide-online-players').Trim() -eq 'true')
    $script:chkLogIps.Checked = ((& $get 'log-ips').Trim() -eq 'true')
    $script:chkBroadcastOps.Checked = ((& $get 'broadcast-console-to-ops').Trim() -eq 'true')
}

function Deploy-Server {
    param([string]$ZipPath, [string]$DestDir)
    if (-not $ZipPath -or -not (Test-Path -LiteralPath $ZipPath)) {
        [System.Windows.Forms.MessageBox]::Show('请选择服务器压缩包。', '提示') | Out-Null
        return
    }
    if (-not $DestDir) {
        [System.Windows.Forms.MessageBox]::Show('请选择安装目录。', '提示') | Out-Null
        return
    }
    if ($DestDir -match '^[A-Za-z]:\\?$') {
        [System.Windows.Forms.MessageBox]::Show('不能把服务器直接装到盘符根目录，请选择子目录。', '错误') | Out-Null
        return
    }
    if (Test-Path -LiteralPath $DestDir) {
        $items = Get-ChildItem -LiteralPath $DestDir -Force -ErrorAction SilentlyContinue
        if ($items.Count -gt 0) {
            $r = [System.Windows.Forms.MessageBox]::Show('目标目录已有内容，要清空后重新部署吗？' + "`r`n$DestDir", '确认', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            $items | Remove-Item -Recurse -Force
        }
    } else {
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    }

    Set-UiStatus '正在解压服务器压缩包，请稍候（大包可能需要一两分钟）...'
    [System.Windows.Forms.Application]::DoEvents()
    try {
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $DestDir -Force
    } catch {
        [System.Windows.Forms.MessageBox]::Show('解压失败: ' + $_.Exception.Message, '错误') | Out-Null
        Set-UiStatus '部署失败'
        return
    }

    # 如果压缩包只有一层文件夹，把内容提升到根目录
    $hasJar = Test-ServerLaunchable -Dir $DestDir
    if (-not $hasJar) {
        $subs = @(Get-ChildItem -LiteralPath $DestDir -Directory -ErrorAction SilentlyContinue)
        if ($subs.Count -eq 1) {
            $subJar = Test-ServerLaunchable -Dir $subs[0].FullName
            if ($subJar) {
                Get-ChildItem -LiteralPath $subs[0].FullName -Force | Move-Item -Destination $DestDir -Force
                Remove-Item -LiteralPath $subs[0].FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # eula
    $eula = Join-Path $DestDir 'eula.txt'
    if (-not (Test-Path -LiteralPath $eula)) { Set-Content -LiteralPath $eula -Value "eula=true`r`n" -Encoding ASCII }
    else {
        $eulaText = Get-Content -LiteralPath $eula -Raw -Encoding UTF8
        if ($eulaText -notmatch 'eula=true') { Set-Content -LiteralPath $eula -Value "eula=true`r`n" -Encoding ASCII }
    }

    # 默认 server.properties（不存在才生成）
    $sp = Join-Path $DestDir 'server.properties'
    if (-not (Test-Path -LiteralPath $sp)) {
        $defaults = @(
            'enable-rcon=true'
            'rcon.port=25575'
            'rcon.password=' + (New-RandomPassword)
            'online-mode=true'
            'enforce-secure-profile=false'
            'server-port=25565'
            'level-name=world'
            'difficulty=easy'
            'gamemode=survival'
            'pvp=true'
            'white-list=false'
            'max-players=20'
            'view-distance=8'
            'motd=A Minecraft Server'
        )
        Set-Content -LiteralPath $sp -Value $defaults -Encoding ASCII
    }

    # 皮肤登录 jar
    $agentSrc = $null
    foreach ($cand in @('D:\WDSJ\PCL\authlib-injector.jar', 'D:\MCServer\authlib-injector.jar', 'D:\MCSpark\authlib-injector.jar')) {
        if (Test-Path -LiteralPath $cand) { $agentSrc = $cand; break }
    }
    if ($agentSrc) {
        Copy-Item -LiteralPath $agentSrc -Destination (Join-Path $DestDir 'authlib-injector.jar') -Force
    }

    $script:serverDir = $DestDir
    $script:txtServerDir.Text = $DestDir
    Load-QuickConfigFromServer
    if (-not $script:javaPath -or -not (Test-Path -LiteralPath $script:javaPath)) {
        Find-Java21 | Out-Null
        $script:txtJava.Text = $script:javaPath
    }
    # frp 自动发现
    if (Test-Path -LiteralPath (Join-Path $DestDir 'frpc.exe')) {
        $script:frpcExe = Join-Path $DestDir 'frpc.exe'
        $script:txtFrpcExe.Text = $script:frpcExe
        if (Test-Path -LiteralPath (Join-Path $DestDir 'frpc.toml')) {
            $script:frpcCfg = Join-Path $DestDir 'frpc.toml'
            $script:txtFrpcCfg.Text = $script:frpcCfg
        }
    }
    $script:serverDir = $DestDir
    Write-RunBat -ServerDir $DestDir | Out-Null
    Save-Settings
    Refresh-ServerCombo
    Set-UiStatus '部署完成！'
    [System.Windows.Forms.MessageBox]::Show('部署完成！服务器目录: ' + $DestDir, '完成', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Find-FrpcExe {
    $candidates = @(
        'D:\MCSpark\frpc.exe',
        'D:\MCServer\frpc.exe',
        'D:\MC\frpc.exe'
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Auto-MatchFrpForServerDir {
    if (-not $script:serverDir) { return }
    $dirExe = Join-Path $script:serverDir 'frpc.exe'
    $dirCfg = Join-Path $script:serverDir 'frpc.toml'
    if (Test-Path -LiteralPath $dirExe) {
        $script:frpcExe = $dirExe
        if ($script:txtFrpcExe) { $script:txtFrpcExe.Text = $dirExe }
    } else {
        $fallback = Find-FrpcExe
        if ($fallback) {
            $script:frpcExe = $fallback
            if ($script:txtFrpcExe) { $script:txtFrpcExe.Text = $fallback }
        }
    }
    if (Test-Path -LiteralPath $dirCfg) {
        $script:frpcCfg = $dirCfg
        if ($script:txtFrpcCfg) { $script:txtFrpcCfg.Text = $dirCfg }
    }
}

function Add-ServerProfile {
    param([string]$Dir)
    if (-not $Dir) { return }
    if (-not $script:serverProfiles.ContainsKey($Dir)) {
        $script:serverProfiles[$Dir] = @{
            name        = [System.IO.Path]::GetFileName($Dir.TrimEnd('\'))
            javaPath    = $script:javaPath
            maxMem      = $script:maxMem
            authMode    = $script:authMode
            skinStation = $script:skinStation
            authUrl     = $script:authUrl
            frpcExe     = $script:frpcExe
            frpcCfg     = $script:frpcCfg
        }
    }
}

function Apply-ServerProfile {
    param([string]$Dir)
    if (-not $Dir -or -not $script:serverProfiles.ContainsKey($Dir)) { return }
    $p = $script:serverProfiles[$Dir]
    if ($p.javaPath) {
        $script:javaPath = $p.javaPath
        if ($script:txtJava) { $script:txtJava.Text = $p.javaPath }
    }
    if ($p.maxMem -and $script:numMem) {
        $script:maxMem = [Math]::Max(1, [Math]::Min(16, [int]$p.maxMem))
        $script:numMem.Value = $script:maxMem
    }
    if ($p.authMode -in @('premium', 'thirdparty')) {
        $script:authMode = $p.authMode
        if ($script:comboAuthMode) { $script:comboAuthMode.SelectedIndex = if ($p.authMode -eq 'premium') { 0 } else { 1 } }
    }
    if ($p.skinStation) {
        $script:skinStation = $p.skinStation
        if ($script:comboSkin -and $script:comboSkin.Items.Contains($p.skinStation)) { $script:comboSkin.SelectedItem = $p.skinStation }
    }
    if ($p.authUrl) {
        $script:authUrl = $p.authUrl
        if ($script:txtAuthUrl) { $script:txtAuthUrl.Text = $p.authUrl }
    }
    if ($p.frpcExe) {
        $script:frpcExe = $p.frpcExe
        if ($script:txtFrpcExe) { $script:txtFrpcExe.Text = $p.frpcExe }
    }
    if ($p.frpcCfg) {
        $script:frpcCfg = $p.frpcCfg
        if ($script:txtFrpcCfg) { $script:txtFrpcCfg.Text = $p.frpcCfg }
    }
}

function Refresh-ServerCombo {
    if (-not $script:comboServers) { return }
    $current = $script:serverDir
    $script:comboServers.Items.Clear()
    foreach ($dir in $script:serverProfiles.Keys) {
        $label = $dir
        if ($script:serverProfiles[$dir].name) {
            $label = $script:serverProfiles[$dir].name + '  (' + $dir + ')'
        }
        $script:comboServers.Items.Add($label) | Out-Null
    }
    if ($current -and $script:serverProfiles.ContainsKey($current)) {
        $label = $current
        if ($script:serverProfiles[$current].name) {
            $label = $script:serverProfiles[$current].name + '  (' + $current + ')'
        }
        $idx = $script:comboServers.Items.IndexOf($label)
        if ($idx -ge 0) { $script:comboServers.SelectedIndex = $idx }
    }
}

function Write-FrpcConfig {
    param([string]$Path, [string]$ServerIp, [int]$ServerPort, [string]$Token, [int]$GamePort, [int]$VoicePort)
    $lines = @(
        "serverAddr = `"$ServerIp`""
        "serverPort = $ServerPort"
        "auth.token = `"$Token`""
        ''
        '[[proxies]]'
        'name = "mc-tcp"'
        'type = "tcp"'
        'localIP = "127.0.0.1"'
        "localPort = $GamePort"
        "remotePort = $GamePort"
        ''
        '[[proxies]]'
        'name = "mc-voice-udp"'
        'type = "udp"'
        'localIP = "127.0.0.1"'
        "localPort = $VoicePort"
        "remotePort = $VoicePort"
    )
    Set-Content -LiteralPath $Path -Value $lines -Encoding ASCII
}

function Sync-FrpcGamePort {
    param([int]$Port)
    $cfg = $script:frpcCfg
    if (-not $cfg -and $script:serverDir) { $cfg = Join-Path $script:serverDir 'frpc.toml' }
    if (-not $cfg -or -not (Test-Path -LiteralPath $cfg)) { return $false }
    $lines = @(Get-Content -LiteralPath $cfg -Encoding UTF8)
    $inTcp = $false
    $changed = $false
    $newLines = @()
    foreach ($line in $lines) {
        if ($line -match '^\s*\[\[proxies\]\]') {
            $inTcp = $false
            $newLines += $line
            continue
        }
        if ($line -match '^\s*name\s*=\s*"mc-tcp"') {
            $inTcp = $true
            $newLines += $line
            continue
        }
        if ($line -match '^\s*name\s*=\s*"') { $inTcp = $false }
        if ($inTcp -and $line -match '^\s*localPort\s*=') {
            $newLines += "localPort = $Port"
            $changed = $true
            continue
        }
        if ($inTcp -and $line -match '^\s*remotePort\s*=') {
            $newLines += "remotePort = $Port"
            $changed = $true
            continue
        }
        $newLines += $line
    }
    if ($changed) { Set-Content -LiteralPath $cfg -Value $newLines -Encoding ASCII }
    return $changed
}

function Get-FrpcPorts {
    $cfg = $script:frpcCfg
    if (-not $cfg -and $script:serverDir) { $cfg = Join-Path $script:serverDir 'frpc.toml' }
    $frpPort = 7000
    $voicePort = 24454
    if ($cfg -and (Test-Path -LiteralPath $cfg)) {
        $lines = @(Get-Content -LiteralPath $cfg -Encoding UTF8)
        $inVoice = $false
        foreach ($line in $lines) {
            if ($line -match '^\s*\[\[proxies\]\]') { $inVoice = $false; continue }
            if ($line -match '^\s*name\s*=\s*"mc-voice-udp"') { $inVoice = $true; continue }
            if ($line -match '^\s*name\s*=\s*"') { $inVoice = $false }
            if ($line -match '^\s*serverPort\s*=\s*(\d+)') { $frpPort = [int]$matches[1] }
            if ($inVoice -and $line -match '^\s*localPort\s*=\s*(\d+)') { $voicePort = [int]$matches[1] }
        }
    }
    return @{ FrpPort = $frpPort; VoicePort = $voicePort }
}

function Update-FrpcServerPort {
    param([int]$Port)
    $cfg = $script:frpcCfg
    if (-not $cfg -and $script:serverDir) { $cfg = Join-Path $script:serverDir 'frpc.toml' }
    if (-not $cfg -or -not (Test-Path -LiteralPath $cfg)) { return $false }
    $lines = @(Get-Content -LiteralPath $cfg -Encoding UTF8)
    $changed = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*serverPort\s*=') {
            $lines[$i] = "serverPort = $Port"
            $changed = $true
            break
        }
    }
    if ($changed) { Set-Content -LiteralPath $cfg -Value $lines -Encoding ASCII }
    return $changed
}

function Update-VoicePort {
    param([int]$Port)
    $msgs = @()
    $cfg = $script:frpcCfg
    if (-not $cfg -and $script:serverDir) { $cfg = Join-Path $script:serverDir 'frpc.toml' }
    if ($cfg -and (Test-Path -LiteralPath $cfg)) {
        $lines = @(Get-Content -LiteralPath $cfg -Encoding UTF8)
        $inVoice = $false
        $changed = $false
        $newLines = @()
        foreach ($line in $lines) {
            if ($line -match '^\s*\[\[proxies\]\]') { $inVoice = $false; $newLines += $line; continue }
            if ($line -match '^\s*name\s*=\s*"mc-voice-udp"') { $inVoice = $true; $newLines += $line; continue }
            if ($line -match '^\s*name\s*=\s*"') { $inVoice = $false }
            if ($inVoice -and $line -match '^\s*localPort\s*=') { $newLines += "localPort = $Port"; $changed = $true; continue }
            if ($inVoice -and $line -match '^\s*remotePort\s*=') { $newLines += "remotePort = $Port"; $changed = $true; continue }
            $newLines += $line
        }
        if ($changed) {
            Set-Content -LiteralPath $cfg -Value $newLines -Encoding ASCII
            $msgs += "frpc.toml 语音转发已改为 $Port"
        }
    }
    if ($script:serverDir) {
        $vc = Join-Path $script:serverDir 'config\voicechat\voicechat-server.properties'
        if (Test-Path -LiteralPath $vc) {
            $vlines = @(Get-Content -LiteralPath $vc -Encoding UTF8)
            $vchanged = $false
            for ($i = 0; $i -lt $vlines.Count; $i++) {
                if ($vlines[$i] -match '^\s*port\s*=') {
                    $vlines[$i] = "port=$Port"
                    $vchanged = $true
                    break
                }
            }
            if ($vchanged) {
                Set-Content -LiteralPath $vc -Value $vlines -Encoding UTF8
                $msgs += "voicechat-server.properties 已改为 $Port"
            }
        } else {
            $msgs += '未找到 config\voicechat\voicechat-server.properties（仅同步了 frpc.toml，语音模组端口需自行确认）'
        }
    }
    if ($msgs.Count -eq 0) { $msgs += '未找到 frpc.toml，未做任何修改' }
    return ($msgs -join "`r`n")
}

function Get-FreshFrpToken {
    # 创建服务器时自动填写的 frp 认证密码：
    # 优先用已保存的密码，其次用 SSH 安装 frps 时用的密码，最后用 install-frps.sh 的默认值
    if ($script:frpToken) { return $script:frpToken }
    if ($script:sshToken) { return $script:sshToken }
    return 'trainwolf2026'
}

function Ensure-FreshFrpTokenField {
    if (-not $script:txtFToken) { return }
    if ([string]::IsNullOrWhiteSpace($script:txtFToken.Text)) {
        $script:txtFToken.Text = Get-FreshFrpToken
    }
}

function Deploy-FromScratch {
    param([string]$ZipPath, [string]$DestDir, [bool]$UseFrp, [string]$FrpIp, [string]$FrpPort, [string]$FrpToken, [int]$GamePort, [int]$VoicePort)

    if (-not $ZipPath -or -not (Test-Path -LiteralPath $ZipPath)) {
        [System.Windows.Forms.MessageBox]::Show('请先选择服务器压缩包。', '从零部署', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    if (-not $DestDir) {
        [System.Windows.Forms.MessageBox]::Show('请填写安装目录。', '从零部署', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    # 1. 确认 Minecraft 版本
    $mcVer = $script:txtFMcVersion.Text.Trim()
    if (-not $mcVer) {
        Add-Type -AssemblyName Microsoft.VisualBasic
        $mcVer = [Microsoft.VisualBasic.Interaction]::InputBox('请输入 Minecraft 版本（例如 1.20.1 / 1.21.1）：' + "`r`n将自动匹配对应 Java（1.17~1.20.4 用 17，1.20.5+ / 1.21 用 21，1.16 及以下用 8）。", 'Minecraft 版本', $script:freshMcVersion)
        if (-not $mcVer) { return }
        $script:txtFMcVersion.Text = $mcVer.Trim()
    }
    $mcVer = $mcVer.Trim()
    $script:freshMcVersion = $mcVer

    # 2. 匹配 / 下载对应 Java
    $major = Get-RequiredJavaMajor -McVersion $mcVer
    $useJava = $null
    if ($script:javaPath -and (Test-Path -LiteralPath $script:javaPath)) {
        $v = (& $script:javaPath -version 2>&1 | Out-String)
        if ($v -match (Get-JavaVersionPattern -Major $major)) { $useJava = $script:javaPath }
    }
    if (-not $useJava) { $useJava = Find-JavaByMajor -Major $major }
    if (-not $useJava) {
        $r = [System.Windows.Forms.MessageBox]::Show("未找到 Java $major，需要下载安装（Adoptium 官方源，约 40MB）。`r`n要现在下载吗？", 'Java', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($r -eq [System.Windows.Forms.DialogResult]::Yes) { $useJava = Install-JavaByMajor -Major $major }
    }
    if (-not $useJava) {
        [System.Windows.Forms.MessageBox]::Show("未找到 Java $major，无法部署。请先安装 Java $major 或手动选择 java.exe。", '从零部署', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    $script:javaPath = $useJava
    $script:javaMap[$DestDir] = $useJava
    Save-Settings

    # 3. 部署（解压、EULA、默认配置、皮肤登录文件）
    Deploy-Server -ZipPath $ZipPath -DestDir $DestDir
    if (-not $script:serverDir -or -not (Test-Path -LiteralPath (Join-Path $script:serverDir 'server.properties'))) { return }

    # 4. 设置端口
    Update-PropertyFile -FilePath (Join-Path $script:serverDir 'server.properties') -Changes @{
        'server-port' = "$GamePort"
        'enable-rcon' = 'true'
        'rcon.port'   = '25575'
    }
    Load-QuickConfigFromServer

    # 5. 内网穿透配置
    if ($UseFrp) {
        if (-not $FrpToken) { $FrpToken = Get-FreshFrpToken }
        if (-not $FrpIp -or -not $FrpPort) {
            [System.Windows.Forms.MessageBox]::Show('已启用穿透但没填云服务器 IP/端口，请补上。', '从零部署', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        $frpcExe = Find-FrpcExe
        if (-not $frpcExe) {
            [System.Windows.Forms.MessageBox]::Show('找不到 frpc.exe（D:\MCSpark 或 D:\MCServer 里没有），无法配置穿透。', '从零部署', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        Copy-Item -LiteralPath $frpcExe -Destination (Join-Path $script:serverDir 'frpc.exe') -Force
        Write-FrpcConfig -Path (Join-Path $script:serverDir 'frpc.toml') -ServerIp $FrpIp -ServerPort ([int]$FrpPort) -Token $FrpToken -GamePort $GamePort -VoicePort $VoicePort
        $script:frpcExe = Join-Path $script:serverDir 'frpc.exe'
        $script:frpcCfg = Join-Path $script:serverDir 'frpc.toml'
        $script:txtFrpcExe.Text = $script:frpcExe
        $script:txtFrpcCfg.Text = $script:frpcCfg
        Save-Settings
    }

    $doneMsg = "从零部署完成！`r`n服务器目录: $DestDir"
    if ($UseFrp) {
        $doneMsg += "`r`n玩家连接地址: $FrpIp`r`n端口: $GamePort（TCP） / $VoicePort（UDP 语音）"
    }
    $doneMsg += "`r`n`r`n服务器和穿透未自动启动，请到[总览启动]页手动启动。"
    if ($UseFrp) {
        $doneMsg += "`r`n`r`n⚠ 请确认云服务器已放行这些端口（ufw + 腾讯云安全组）：frp端口 $FrpPort、游戏端口 $GamePort、语音端口 $VoicePort。`r`n语音端口需与服务器 config\voicechat 里的配置一致（默认 24454）。"
    }
    [System.Windows.Forms.MessageBox]::Show($doneMsg, '从零部署', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

# ---------------- 界面构建 ----------------
function New-MainForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'MC 服务器管理器 ' + $script:appVersion
    $form.Size = [System.Drawing.Size]::new(1000, 700)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $form.Font = $font

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
    $form.Controls.Add($tabs)

    # ---------- 从零部署页 ----------
    $tabFresh = New-Object System.Windows.Forms.TabPage
    $tabFresh.Text = '从零部署'
    $tabs.TabPages.Add($tabFresh)
    $panelFresh = New-Object System.Windows.Forms.Panel
    $panelFresh.Dock = [System.Windows.Forms.DockStyle]::Fill
    $panelFresh.AutoScroll = $true
    $tabFresh.Controls.Add($panelFresh)


    $y = 24
    $lblFZip = New-Object System.Windows.Forms.Label
    $lblFZip.Text = '服务器压缩包:'
    $lblFZip.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblFZip.Size = [System.Drawing.Size]::new(100, 22)
    $panelFresh.Controls.Add($lblFZip)
    $script:txtFZip = New-Object System.Windows.Forms.TextBox
    $script:txtFZip.Location = [System.Drawing.Point]::new(125, $y)
    $script:txtFZip.Size = [System.Drawing.Size]::new(520, 22)
    $panelFresh.Controls.Add($script:txtFZip)
    $btnFZip = New-Object System.Windows.Forms.Button
    $btnFZip.Text = '选择...'
    $btnFZip.Location = [System.Drawing.Point]::new(655, $y - 1)
    $btnFZip.Size = [System.Drawing.Size]::new(80, 26)
    $panelFresh.Controls.Add($btnFZip)
    $y += 36

    $lblFDir = New-Object System.Windows.Forms.Label
    $lblFDir.Text = '安装目录:'
    $lblFDir.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblFDir.Size = [System.Drawing.Size]::new(100, 22)
    $panelFresh.Controls.Add($lblFDir)
    $script:txtFDir = New-Object System.Windows.Forms.TextBox
    $script:txtFDir.Location = [System.Drawing.Point]::new(125, $y)
    $script:txtFDir.Size = [System.Drawing.Size]::new(520, 22)
    $panelFresh.Controls.Add($script:txtFDir)
    $btnFDir = New-Object System.Windows.Forms.Button
    $btnFDir.Text = '选择...'
    $btnFDir.Location = [System.Drawing.Point]::new(655, $y - 1)
    $btnFDir.Size = [System.Drawing.Size]::new(80, 26)
    $panelFresh.Controls.Add($btnFDir)
    $y += 40

    $lblFMc = New-Object System.Windows.Forms.Label
    $lblFMc.Text = 'Minecraft 版本:'
    $lblFMc.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblFMc.Size = [System.Drawing.Size]::new(110, 22)
    $panelFresh.Controls.Add($lblFMc)
    $script:txtFMcVersion = New-Object System.Windows.Forms.TextBox
    $script:txtFMcVersion.Location = [System.Drawing.Point]::new(135, $y)
    $script:txtFMcVersion.Size = [System.Drawing.Size]::new(120, 22)
    $panelFresh.Controls.Add($script:txtFMcVersion)
    $script:lblFJavaMatch = New-Object System.Windows.Forms.Label
    $script:lblFJavaMatch.Text = '输入后自动匹配对应 Java'
    $script:lblFJavaMatch.Location = [System.Drawing.Point]::new(270, $y + 3)
    $script:lblFJavaMatch.Size = [System.Drawing.Size]::new(420, 22)
    $script:lblFJavaMatch.ForeColor = [System.Drawing.Color]::Gray
    $panelFresh.Controls.Add($script:lblFJavaMatch)
    $y += 34

    $lblFJava = New-Object System.Windows.Forms.Label
    $lblFJava.Text = 'Java:'
    $lblFJava.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblFJava.Size = [System.Drawing.Size]::new(100, 22)
    $panelFresh.Controls.Add($lblFJava)
    $script:lblFJavaStatus = New-Object System.Windows.Forms.Label
    $script:lblFJavaStatus.Text = '未检测'
    $script:lblFJavaStatus.Location = [System.Drawing.Point]::new(125, $y + 3)
    $script:lblFJavaStatus.Size = [System.Drawing.Size]::new(300, 22)
    $script:lblFJavaStatus.ForeColor = [System.Drawing.Color]::Gray
    $panelFresh.Controls.Add($script:lblFJavaStatus)
    $btnFFindJava = New-Object System.Windows.Forms.Button
    $btnFFindJava.Text = '自动查找'
    $btnFFindJava.Location = [System.Drawing.Point]::new(435, $y - 1)
    $btnFFindJava.Size = [System.Drawing.Size]::new(90, 26)
    $panelFresh.Controls.Add($btnFFindJava)
    $script:btnFDownloadJava = New-Object System.Windows.Forms.Button
    $script:btnFDownloadJava.Text = '下载安装'
    $script:btnFDownloadJava.Location = [System.Drawing.Point]::new(535, $y - 1)
    $script:btnFDownloadJava.Size = [System.Drawing.Size]::new(90, 26)
    $panelFresh.Controls.Add($script:btnFDownloadJava)
    $script:btnFJavaFile = New-Object System.Windows.Forms.Button
    $script:btnFJavaFile.Text = '选择文件...'
    $script:btnFJavaFile.Location = [System.Drawing.Point]::new(635, $y - 1)
    $script:btnFJavaFile.Size = [System.Drawing.Size]::new(100, 26)
    $panelFresh.Controls.Add($script:btnFJavaFile)
    $y += 42

    $lblFJavaDir = New-Object System.Windows.Forms.Label
    $lblFJavaDir.Text = 'Java 安装目录:'
    $lblFJavaDir.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblFJavaDir.Size = [System.Drawing.Size]::new(110, 22)
    $panelFresh.Controls.Add($lblFJavaDir)
    $script:txtFJavaInstallDir = New-Object System.Windows.Forms.TextBox
    $script:txtFJavaInstallDir.Location = [System.Drawing.Point]::new(135, $y)
    $script:txtFJavaInstallDir.Size = [System.Drawing.Size]::new(400, 22)
    $panelFresh.Controls.Add($script:txtFJavaInstallDir)
    $btnFJavaDir = New-Object System.Windows.Forms.Button
    $btnFJavaDir.Text = '选择...'
    $btnFJavaDir.Location = [System.Drawing.Point]::new(545, $y - 1)
    $btnFJavaDir.Size = [System.Drawing.Size]::new(80, 26)
    $panelFresh.Controls.Add($btnFJavaDir)
    $y += 36

    $lblFFrp = New-Object System.Windows.Forms.Label
    $lblFFrp.Text = '内网穿透配置:'
    $lblFFrp.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblFFrp.Size = [System.Drawing.Size]::new(100, 22)
    $lblFFrp.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
    $panelFresh.Controls.Add($lblFFrp)
    $y += 32

    $lblFIp = New-Object System.Windows.Forms.Label
    $lblFIp.Text = '云服务器IP:'
    $lblFIp.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblFIp.Size = [System.Drawing.Size]::new(100, 22)
    $panelFresh.Controls.Add($lblFIp)
    $script:txtFIp = New-Object System.Windows.Forms.TextBox
    $script:txtFIp.Location = [System.Drawing.Point]::new(125, $y)
    $script:txtFIp.Size = [System.Drawing.Size]::new(180, 22)
    $panelFresh.Controls.Add($script:txtFIp)
    $lblFFrpPort = New-Object System.Windows.Forms.Label
    $lblFFrpPort.Text = 'frp端口:'
    $lblFFrpPort.Location = [System.Drawing.Point]::new(320, $y + 3)
    $lblFFrpPort.Size = [System.Drawing.Size]::new(70, 22)
    $panelFresh.Controls.Add($lblFFrpPort)
    $script:txtFFrpPort = New-Object System.Windows.Forms.TextBox
    $script:txtFFrpPort.Text = '7000'
    $script:txtFFrpPort.Location = [System.Drawing.Point]::new(395, $y)
    $script:txtFFrpPort.Size = [System.Drawing.Size]::new(70, 22)
    $panelFresh.Controls.Add($script:txtFFrpPort)
    $lblFToken = New-Object System.Windows.Forms.Label
    $lblFToken.Text = '认证密码:'
    $lblFToken.Location = [System.Drawing.Point]::new(480, $y + 3)
    $lblFToken.Size = [System.Drawing.Size]::new(70, 22)
    $panelFresh.Controls.Add($lblFToken)
    $script:txtFToken = New-Object System.Windows.Forms.TextBox
    $script:txtFToken.Location = [System.Drawing.Point]::new(555, $y)
    $script:txtFToken.Size = [System.Drawing.Size]::new(180, 22)
    $panelFresh.Controls.Add($script:txtFToken)
    $y += 34

    $lblFGamePort = New-Object System.Windows.Forms.Label
    $lblFGamePort.Text = '游戏端口:'
    $lblFGamePort.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblFGamePort.Size = [System.Drawing.Size]::new(100, 22)
    $panelFresh.Controls.Add($lblFGamePort)
    $script:txtFGamePort = New-Object System.Windows.Forms.TextBox
    $script:txtFGamePort.Text = '25565'
    $script:txtFGamePort.Location = [System.Drawing.Point]::new(125, $y)
    $script:txtFGamePort.Size = [System.Drawing.Size]::new(70, 22)
    $panelFresh.Controls.Add($script:txtFGamePort)
    $lblFVoicePort = New-Object System.Windows.Forms.Label
    $lblFVoicePort.Text = '语音端口:'
    $lblFVoicePort.Location = [System.Drawing.Point]::new(220, $y + 3)
    $lblFVoicePort.Size = [System.Drawing.Size]::new(70, 22)
    $panelFresh.Controls.Add($lblFVoicePort)
    $script:txtFVoicePort = New-Object System.Windows.Forms.TextBox
    $script:txtFVoicePort.Text = '24454'
    $script:txtFVoicePort.Location = [System.Drawing.Point]::new(295, $y)
    $script:txtFVoicePort.Size = [System.Drawing.Size]::new(70, 22)
    $panelFresh.Controls.Add($script:txtFVoicePort)
    $script:chkFUseFrp = New-Object System.Windows.Forms.CheckBox
    $script:chkFUseFrp.Text = '启用内网穿透'
    $script:chkFUseFrp.Checked = $true
    $script:chkFUseFrp.Location = [System.Drawing.Point]::new(395, $y + 2)
    $script:chkFUseFrp.Size = [System.Drawing.Size]::new(130, 24)
    $panelFresh.Controls.Add($script:chkFUseFrp)
    $y += 46

    $btnFullDeploy = New-Object System.Windows.Forms.Button
    $btnFullDeploy.Text = '一键部署'
    $btnFullDeploy.Location = [System.Drawing.Point]::new(125, $y)
    $btnFullDeploy.Size = [System.Drawing.Size]::new(200, 40)
    $btnFullDeploy.BackColor = [System.Drawing.Color]::FromArgb(220, 240, 220)
    $btnFullDeploy.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
    $panelFresh.Controls.Add($btnFullDeploy)
    $y += 54

    $lblFreshTip = New-Object System.Windows.Forms.Label
    $lblFreshTip.Text = '流程：解压压缩包 → 同意 EULA → 生成默认配置 → 复制皮肤登录 → 生成 frpc 穿透配置。' + "`r`n" + '部署完成后请在“总览启动”页手动启动服务器和穿透。' + "`r`n" + '玩家连接地址 = 云服务器IP:游戏端口。' + "`r`n" + '⚠ 请在云服务器端放行以下端口的 TCP/UDP（ufw 和腾讯云安全组）：frp端口、游戏端口、语音端口。' + "`r`n" + '语音端口默认 24454，若改过需同步修改服务器 config\voicechat 配置。'
    $lblFreshTip.Location = [System.Drawing.Point]::new(20, $y)
    $lblFreshTip.Size = [System.Drawing.Size]::new(840, 46)
    $lblFreshTip.ForeColor = [System.Drawing.Color]::Gray
    $panelFresh.Controls.Add($lblFreshTip)
    $y += 56

    # ---------- 总览页 ----------
    $tabMain = New-Object System.Windows.Forms.TabPage
    $tabMain.Text = '总览 / 启动'
    $tabs.TabPages.Add($tabMain)

    $y = 20
    $lblServers = New-Object System.Windows.Forms.Label
    $lblServers.Text = '服务器:'
    $lblServers.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblServers.Size = [System.Drawing.Size]::new(90, 22)
    $tabMain.Controls.Add($lblServers)
    $script:comboServers = New-Object System.Windows.Forms.ComboBox
    $script:comboServers.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $script:comboServers.Location = [System.Drawing.Point]::new(115, $y)
    $script:comboServers.Size = [System.Drawing.Size]::new(520, 24)
    $tabMain.Controls.Add($script:comboServers)
    $btnAddServer = New-Object System.Windows.Forms.Button
    $btnAddServer.Text = '添加当前目录'
    $btnAddServer.Location = [System.Drawing.Point]::new(645, $y - 1)
    $btnAddServer.Size = [System.Drawing.Size]::new(180, 26)
    $tabMain.Controls.Add($btnAddServer)
    $y += 32

    $lblServerDir = New-Object System.Windows.Forms.Label
    $lblServerDir.Text = '服务器目录:'
    $lblServerDir.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblServerDir.Size = [System.Drawing.Size]::new(90, 22)
    $tabMain.Controls.Add($lblServerDir)
    $script:txtServerDir = New-Object System.Windows.Forms.TextBox
    $script:txtServerDir.Location = [System.Drawing.Point]::new(115, $y)
    $script:txtServerDir.Size = [System.Drawing.Size]::new(520, 22)
    $tabMain.Controls.Add($script:txtServerDir)
    $btnBrowseDir = New-Object System.Windows.Forms.Button
    $btnBrowseDir.Text = '选择...'
    $btnBrowseDir.Location = [System.Drawing.Point]::new(645, $y - 1)
    $btnBrowseDir.Size = [System.Drawing.Size]::new(80, 26)
    $tabMain.Controls.Add($btnBrowseDir)
    $btnOpenDir = New-Object System.Windows.Forms.Button
    $btnOpenDir.Text = '打开文件夹'
    $btnOpenDir.Location = [System.Drawing.Point]::new(735, $y - 1)
    $btnOpenDir.Size = [System.Drawing.Size]::new(90, 26)
    $tabMain.Controls.Add($btnOpenDir)
    $y += 36

    $script:lblJava = New-Object System.Windows.Forms.Label
    $script:lblJava.Text = 'Java:'
    $script:lblJava.Location = [System.Drawing.Point]::new(20, $y + 3)
    $script:lblJava.Size = [System.Drawing.Size]::new(90, 22)
    $tabMain.Controls.Add($script:lblJava)
    $script:txtJava = New-Object System.Windows.Forms.TextBox
    $script:txtJava.Location = [System.Drawing.Point]::new(115, $y)
    $script:txtJava.Size = [System.Drawing.Size]::new(520, 22)
    $tabMain.Controls.Add($script:txtJava)
    $btnBrowseJava = New-Object System.Windows.Forms.Button
    $btnBrowseJava.Text = '选择...'
    $btnBrowseJava.Location = [System.Drawing.Point]::new(645, $y - 1)
    $btnBrowseJava.Size = [System.Drawing.Size]::new(80, 26)
    $tabMain.Controls.Add($btnBrowseJava)
    $btnFindJava = New-Object System.Windows.Forms.Button
    $btnFindJava.Text = '自动查找'
    $btnFindJava.Location = [System.Drawing.Point]::new(735, $y - 1)
    $btnFindJava.Size = [System.Drawing.Size]::new(90, 26)
    $tabMain.Controls.Add($btnFindJava)
    $y += 36

    $script:btnDownloadJava = New-Object System.Windows.Forms.Button
    $script:btnDownloadJava.Text = '下载 Java'
    $script:btnDownloadJava.Location = [System.Drawing.Point]::new(115, $y)
    $script:btnDownloadJava.Size = [System.Drawing.Size]::new(300, 28)
    $tabMain.Controls.Add($script:btnDownloadJava)
    $y += 42

    $lblMem = New-Object System.Windows.Forms.Label
    $lblMem.Text = '内存 (GB):'
    $lblMem.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblMem.Size = [System.Drawing.Size]::new(90, 22)
    $tabMain.Controls.Add($lblMem)
    $script:numMem = New-Object System.Windows.Forms.NumericUpDown
    $script:numMem.Minimum = 1
    $script:numMem.Maximum = 16
    $script:numMem.Value = $script:maxMem
    $script:numMem.Location = [System.Drawing.Point]::new(115, $y)
    $script:numMem.Size = [System.Drawing.Size]::new(80, 22)
    $tabMain.Controls.Add($script:numMem)
    $y += 36

    $lblAuthMode = New-Object System.Windows.Forms.Label
    $lblAuthMode.Text = '登录方式:'
    $lblAuthMode.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblAuthMode.Size = [System.Drawing.Size]::new(90, 22)
    $tabMain.Controls.Add($lblAuthMode)
    $script:comboAuthMode = New-Object System.Windows.Forms.ComboBox
    $script:comboAuthMode.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $script:comboAuthMode.Items.AddRange(@('官方登录', '第三方登录'))
    $script:comboAuthMode.Location = [System.Drawing.Point]::new(115, $y)
    $script:comboAuthMode.Size = [System.Drawing.Size]::new(280, 24)
    $tabMain.Controls.Add($script:comboAuthMode)
    $y += 32

    $lblSkin = New-Object System.Windows.Forms.Label
    $lblSkin.Text = '第三方方式:'
    $lblSkin.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblSkin.Size = [System.Drawing.Size]::new(90, 22)
    $tabMain.Controls.Add($lblSkin)
    $script:comboSkin = New-Object System.Windows.Forms.ComboBox
    $script:comboSkin.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $script:comboSkin.Items.AddRange(@('离线模式', '红石皮肤站', 'LittleSkin', '自定义'))
    $script:comboSkin.Location = [System.Drawing.Point]::new(115, $y)
    $script:comboSkin.Size = [System.Drawing.Size]::new(280, 24)
    $tabMain.Controls.Add($script:comboSkin)
    $y += 32

    $lblAuth = New-Object System.Windows.Forms.Label
    $lblAuth.Text = '外置登录地址:'
    $lblAuth.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblAuth.Size = [System.Drawing.Size]::new(90, 22)
    $tabMain.Controls.Add($lblAuth)
    $script:txtAuthUrl = New-Object System.Windows.Forms.TextBox
    $script:txtAuthUrl.Location = [System.Drawing.Point]::new(115, $y)
    $script:txtAuthUrl.Size = [System.Drawing.Size]::new(520, 22)
    $tabMain.Controls.Add($script:txtAuthUrl)
    $btnGenBat = New-Object System.Windows.Forms.Button
    $btnGenBat.Text = '生成 run.bat'
    $btnGenBat.Location = [System.Drawing.Point]::new(645, $y - 1)
    $btnGenBat.Size = [System.Drawing.Size]::new(180, 26)
    $tabMain.Controls.Add($btnGenBat)
    $y += 40

    $lblPorts = New-Object System.Windows.Forms.Label
    $lblPorts.Text = '端口设置:'
    $lblPorts.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblPorts.Size = [System.Drawing.Size]::new(70, 22)
    $tabMain.Controls.Add($lblPorts)
    $lblGamePort = New-Object System.Windows.Forms.Label
    $lblGamePort.Text = '游戏:'
    $lblGamePort.Location = [System.Drawing.Point]::new(95, $y + 3)
    $lblGamePort.Size = [System.Drawing.Size]::new(40, 22)
    $tabMain.Controls.Add($lblGamePort)
    $script:txtGamePort = New-Object System.Windows.Forms.TextBox
    $script:txtGamePort.Text = '25565'
    $script:txtGamePort.Location = [System.Drawing.Point]::new(135, $y)
    $script:txtGamePort.Size = [System.Drawing.Size]::new(60, 22)
    $tabMain.Controls.Add($script:txtGamePort)
    $lblFrpPort = New-Object System.Windows.Forms.Label
    $lblFrpPort.Text = 'frp:'
    $lblFrpPort.Location = [System.Drawing.Point]::new(210, $y + 3)
    $lblFrpPort.Size = [System.Drawing.Size]::new(40, 22)
    $tabMain.Controls.Add($lblFrpPort)
    $script:txtFrpPort = New-Object System.Windows.Forms.TextBox
    $script:txtFrpPort.Text = '7000'
    $script:txtFrpPort.Location = [System.Drawing.Point]::new(250, $y)
    $script:txtFrpPort.Size = [System.Drawing.Size]::new(60, 22)
    $tabMain.Controls.Add($script:txtFrpPort)
    $lblVoicePort = New-Object System.Windows.Forms.Label
    $lblVoicePort.Text = '语音:'
    $lblVoicePort.Location = [System.Drawing.Point]::new(325, $y + 3)
    $lblVoicePort.Size = [System.Drawing.Size]::new(40, 22)
    $tabMain.Controls.Add($lblVoicePort)
    $script:txtVoicePort = New-Object System.Windows.Forms.TextBox
    $script:txtVoicePort.Text = '24454'
    $script:txtVoicePort.Location = [System.Drawing.Point]::new(365, $y)
    $script:txtVoicePort.Size = [System.Drawing.Size]::new(60, 22)
    $tabMain.Controls.Add($script:txtVoicePort)
    $btnSavePorts = New-Object System.Windows.Forms.Button
    $btnSavePorts.Text = '保存端口'
    $btnSavePorts.Location = [System.Drawing.Point]::new(445, $y - 1)
    $btnSavePorts.Size = [System.Drawing.Size]::new(100, 26)
    $tabMain.Controls.Add($btnSavePorts)
    $lblPortsTip = New-Object System.Windows.Forms.Label
    $lblPortsTip.Text = '保存后需重启服务器与穿透；frp 端口需同步云服务器 frps.toml'
    $lblPortsTip.Location = [System.Drawing.Point]::new(555, $y + 3)
    $lblPortsTip.Size = [System.Drawing.Size]::new(420, 22)
    $lblPortsTip.ForeColor = [System.Drawing.Color]::Gray
    $tabMain.Controls.Add($lblPortsTip)
    $y += 40

    $lblTunnel = New-Object System.Windows.Forms.Label
    $lblTunnel.Text = '内网穿透:'
    $lblTunnel.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblTunnel.Size = [System.Drawing.Size]::new(70, 22)
    $tabMain.Controls.Add($lblTunnel)
    $script:txtTunnelIp = New-Object System.Windows.Forms.TextBox
    $script:txtTunnelIp.ReadOnly = $true
    $script:txtTunnelIp.Location = [System.Drawing.Point]::new(95, $y)
    $script:txtTunnelIp.Size = [System.Drawing.Size]::new(140, 22)
    $tabMain.Controls.Add($script:txtTunnelIp)
    $btnStartTunnel = New-Object System.Windows.Forms.Button
    $btnStartTunnel.Text = '启动穿透'
    $btnStartTunnel.Location = [System.Drawing.Point]::new(245, $y - 1)
    $btnStartTunnel.Size = [System.Drawing.Size]::new(90, 26)
    $tabMain.Controls.Add($btnStartTunnel)
    $btnStopTunnel = New-Object System.Windows.Forms.Button
    $btnStopTunnel.Text = '停止穿透'
    $btnStopTunnel.Location = [System.Drawing.Point]::new(345, $y - 1)
    $btnStopTunnel.Size = [System.Drawing.Size]::new(90, 26)
    $tabMain.Controls.Add($btnStopTunnel)
    $script:lblTunnelState = New-Object System.Windows.Forms.Label
    $script:lblTunnelState.Location = [System.Drawing.Point]::new(445, $y + 3)
    $script:lblTunnelState.Size = [System.Drawing.Size]::new(460, 22)
    $script:lblTunnelState.ForeColor = [System.Drawing.Color]::Gray
    $tabMain.Controls.Add($script:lblTunnelState)
    $y += 36

    $btnStart = New-Object System.Windows.Forms.Button
    $btnStart.Text = '启动服务器'
    $btnStart.Location = [System.Drawing.Point]::new(115, $y)
    $btnStart.Size = [System.Drawing.Size]::new(130, 34)
    $btnStart.BackColor = [System.Drawing.Color]::FromArgb(220, 240, 220)
    $tabMain.Controls.Add($btnStart)
    $btnStop = New-Object System.Windows.Forms.Button
    $btnStop.Text = '停止服务器'
    $btnStop.Location = [System.Drawing.Point]::new(255, $y)
    $btnStop.Size = [System.Drawing.Size]::new(130, 34)
    $tabMain.Controls.Add($btnStop)
    $btnRestart = New-Object System.Windows.Forms.Button
    $btnRestart.Text = '重启服务器'
    $btnRestart.Location = [System.Drawing.Point]::new(395, $y)
    $btnRestart.Size = [System.Drawing.Size]::new(130, 34)
    $tabMain.Controls.Add($btnRestart)
    $btnStatus = New-Object System.Windows.Forms.Button
    $btnStatus.Text = '查询运行状态'
    $btnStatus.Location = [System.Drawing.Point]::new(535, $y)
    $btnStatus.Size = [System.Drawing.Size]::new(150, 34)
    $tabMain.Controls.Add($btnStatus)
    $y += 48

    $lblTip = New-Object System.Windows.Forms.Label
    $lblTip.Text = '提示：选好服务器目录和 Java 后点"启动服务器"，等待控制台出现 Done (...) 即可。' + "`r`n" + '服务器和游戏可以在同一台电脑运行；玩家连接地址由内网穿透页的 frpc 决定。'
    $lblTip.Location = [System.Drawing.Point]::new(20, $y)
    $lblTip.Size = [System.Drawing.Size]::new(820, 40)
    $lblTip.ForeColor = [System.Drawing.Color]::Gray
    $tabMain.Controls.Add($lblTip)

    # ---------- 控制台页 ----------
    $tabConsole = New-Object System.Windows.Forms.TabPage
    $tabConsole.Text = '控制台'
    $tabs.TabPages.Add($tabConsole)

    $script:txtConsole = New-Object System.Windows.Forms.TextBox
    $script:txtConsole.Multiline = $true
    $script:txtConsole.ReadOnly = $true
    $script:txtConsole.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $script:txtConsole.WordWrap = $false
    $script:txtConsole.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:txtConsole.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $script:txtConsole.ForeColor = [System.Drawing.Color]::White
    $script:txtConsole.Font = New-Object System.Drawing.Font('Consolas', 9)
    $tabConsole.Controls.Add($script:txtConsole)

    $panelCmd = New-Object System.Windows.Forms.Panel
    $panelCmd.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $panelCmd.Height = 40
    $tabConsole.Controls.Add($panelCmd)

    $lblCmd = New-Object System.Windows.Forms.Label
    $lblCmd.Text = '指令:'
    $lblCmd.Location = [System.Drawing.Point]::new(10, 10)
    $lblCmd.Size = [System.Drawing.Size]::new(50, 22)
    $panelCmd.Controls.Add($lblCmd)
    $script:txtCmd = New-Object System.Windows.Forms.TextBox
    $script:txtCmd.Location = [System.Drawing.Point]::new(60, 8)
    $script:txtCmd.Size = [System.Drawing.Size]::new(560, 22)
    $panelCmd.Controls.Add($script:txtCmd)
    $btnSend = New-Object System.Windows.Forms.Button
    $btnSend.Text = '发送 (RCON)'
    $btnSend.Location = [System.Drawing.Point]::new(630, 6)
    $btnSend.Size = [System.Drawing.Size]::new(110, 26)
    $panelCmd.Controls.Add($btnSend)
    $btnClearConsole = New-Object System.Windows.Forms.Button
    $btnClearConsole.Text = '清空'
    $btnClearConsole.Location = [System.Drawing.Point]::new(750, 6)
    $btnClearConsole.Size = [System.Drawing.Size]::new(70, 26)
    $panelCmd.Controls.Add($btnClearConsole)

    # ---------- 快速配置页 ----------
    $tabConfig = New-Object System.Windows.Forms.TabPage
    $tabConfig.Text = '快速配置'
    $tabs.TabPages.Add($tabConfig)
    $panelConfig = New-Object System.Windows.Forms.Panel
    $panelConfig.Dock = [System.Windows.Forms.DockStyle]::Fill
    $panelConfig.AutoScroll = $true
    $tabConfig.Controls.Add($panelConfig)

    $y = 24
    $lblDiff = New-Object System.Windows.Forms.Label
    $lblDiff.Text = '难度:'
    $lblDiff.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblDiff.Size = [System.Drawing.Size]::new(110, 22)
    $panelConfig.Controls.Add($lblDiff)
    $script:comboDiff = New-Object System.Windows.Forms.ComboBox
    $script:comboDiff.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    @('peaceful','easy','normal','hard') | ForEach-Object { [void]$script:comboDiff.Items.Add($_) }
    $script:comboDiff.Location = [System.Drawing.Point]::new(135, $y)
    $script:comboDiff.Size = [System.Drawing.Size]::new(140, 22)
    $panelConfig.Controls.Add($script:comboDiff)
    $y += 34

    $lblGm = New-Object System.Windows.Forms.Label
    $lblGm.Text = '游戏模式:'
    $lblGm.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblGm.Size = [System.Drawing.Size]::new(110, 22)
    $panelConfig.Controls.Add($lblGm)
    $script:comboGm = New-Object System.Windows.Forms.ComboBox
    $script:comboGm.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    @('survival','creative','adventure','spectator') | ForEach-Object { [void]$script:comboGm.Items.Add($_) }
    $script:comboGm.Location = [System.Drawing.Point]::new(135, $y)
    $script:comboGm.Size = [System.Drawing.Size]::new(140, 22)
    $panelConfig.Controls.Add($script:comboGm)
    $y += 34

    $lblMotd = New-Object System.Windows.Forms.Label
    $lblMotd.Text = 'MOTD 公告:'
    $lblMotd.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblMotd.Size = [System.Drawing.Size]::new(110, 22)
    $panelConfig.Controls.Add($lblMotd)
    $script:txtMotd = New-Object System.Windows.Forms.TextBox
    $script:txtMotd.Location = [System.Drawing.Point]::new(135, $y)
    $script:txtMotd.Size = [System.Drawing.Size]::new(500, 22)
    $panelConfig.Controls.Add($script:txtMotd)
    $y += 34

    $lblMaxPlayers = New-Object System.Windows.Forms.Label
    $lblMaxPlayers.Text = '最大玩家数:'
    $lblMaxPlayers.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblMaxPlayers.Size = [System.Drawing.Size]::new(110, 22)
    $panelConfig.Controls.Add($lblMaxPlayers)
    $script:txtMaxPlayers = New-Object System.Windows.Forms.TextBox
    $script:txtMaxPlayers.Location = [System.Drawing.Point]::new(135, $y)
    $script:txtMaxPlayers.Size = [System.Drawing.Size]::new(140, 22)
    $panelConfig.Controls.Add($script:txtMaxPlayers)
    $y += 34

    $script:chkPvp = New-Object System.Windows.Forms.CheckBox
    $script:chkPvp.Text = '开启 PVP'
    $script:chkPvp.Location = [System.Drawing.Point]::new(135, $y)
    $script:chkPvp.Size = [System.Drawing.Size]::new(130, 24)
    $panelConfig.Controls.Add($script:chkPvp)
    $script:chkWhitelist = New-Object System.Windows.Forms.CheckBox
    $script:chkWhitelist.Text = '开启白名单'
    $script:chkWhitelist.Location = [System.Drawing.Point]::new(285, $y)
    $script:chkWhitelist.Size = [System.Drawing.Size]::new(130, 24)
    $panelConfig.Controls.Add($script:chkWhitelist)
    $y += 30
    $script:chkForce = New-Object System.Windows.Forms.CheckBox
    $script:chkForce.Text = '强制游戏模式'
    $script:chkForce.Location = [System.Drawing.Point]::new(135, $y)
    $script:chkForce.Size = [System.Drawing.Size]::new(130, 24)
    $panelConfig.Controls.Add($script:chkForce)
    $script:chkCmdBlock = New-Object System.Windows.Forms.CheckBox
    $script:chkCmdBlock.Text = '启用命令方块'
    $script:chkCmdBlock.Location = [System.Drawing.Point]::new(285, $y)
    $script:chkCmdBlock.Size = [System.Drawing.Size]::new(130, 24)
    $panelConfig.Controls.Add($script:chkCmdBlock)
    $y += 30
    $script:chkOnline = New-Object System.Windows.Forms.CheckBox
    $script:chkOnline.Text = '在线验证 (online-mode)'
    $script:chkOnline.Location = [System.Drawing.Point]::new(135, $y)
    $script:chkOnline.Size = [System.Drawing.Size]::new(180, 24)
    $panelConfig.Controls.Add($script:chkOnline)
    $y += 40

    $btnSaveConfig = New-Object System.Windows.Forms.Button
    $btnSaveConfig.Text = '保存配置'
    $btnSaveConfig.Location = [System.Drawing.Point]::new(135, $y)
    $btnSaveConfig.Size = [System.Drawing.Size]::new(130, 32)
    $panelConfig.Controls.Add($btnSaveConfig)
    $btnEditProps = New-Object System.Windows.Forms.Button
    $btnEditProps.Text = '用记事本编辑 server.properties'
    $btnEditProps.Location = [System.Drawing.Point]::new(280, $y)
    $btnEditProps.Size = [System.Drawing.Size]::new(230, 32)
    $panelConfig.Controls.Add($btnEditProps)
    $y += 44
    $lblConfigTip = New-Object System.Windows.Forms.Label
    $lblConfigTip.Text = '提示：配置保存后需要重启服务器才生效；修改"服务器端口"会自动同步 frpc.toml（需重启穿透，玩家地址变为 云服务器IP:新端口）。'
    $lblConfigTip.Location = [System.Drawing.Point]::new(20, $y)
    $lblConfigTip.Size = [System.Drawing.Size]::new(600, 22)
    $lblConfigTip.ForeColor = [System.Drawing.Color]::Gray
    $panelConfig.Controls.Add($lblConfigTip)

    $y += 12
    $lblMore = New-Object System.Windows.Forms.Label
    $lblMore.Text = '更多设置（下方可滚动）:'
    $lblMore.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblMore.Size = [System.Drawing.Size]::new(200, 22)
    $lblMore.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
    $panelConfig.Controls.Add($lblMore)
    $y += 34

    $script:txtViewDist = New-Object System.Windows.Forms.TextBox
    $lblViewDist = New-Object System.Windows.Forms.Label
    $lblViewDist.Text = '视距:'
    $lblViewDist.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblViewDist.Size = [System.Drawing.Size]::new(110, 22)
    $script:txtViewDist.Location = [System.Drawing.Point]::new(135, $y)
    $script:txtViewDist.Size = [System.Drawing.Size]::new(160, 22)
    $panelConfig.Controls.Add($lblViewDist)
    $panelConfig.Controls.Add($script:txtViewDist)
    $lblSimDist = New-Object System.Windows.Forms.Label
    $lblSimDist.Text = '模拟距离:'
    $lblSimDist.Location = [System.Drawing.Point]::new(480, $y + 3)
    $lblSimDist.Size = [System.Drawing.Size]::new(110, 22)
    $script:txtSimDist = New-Object System.Windows.Forms.TextBox
    $script:txtSimDist.Location = [System.Drawing.Point]::new(595, $y)
    $script:txtSimDist.Size = [System.Drawing.Size]::new(160, 22)
    $panelConfig.Controls.Add($lblSimDist)
    $panelConfig.Controls.Add($script:txtSimDist)
    $y += 34

    $lblSpawnProtect = New-Object System.Windows.Forms.Label
    $lblSpawnProtect.Text = '出生点保护:'
    $lblSpawnProtect.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblSpawnProtect.Size = [System.Drawing.Size]::new(110, 22)
    $script:txtSpawnProtect = New-Object System.Windows.Forms.TextBox
    $script:txtSpawnProtect.Location = [System.Drawing.Point]::new(135, $y)
    $script:txtSpawnProtect.Size = [System.Drawing.Size]::new(160, 22)
    $panelConfig.Controls.Add($lblSpawnProtect)
    $panelConfig.Controls.Add($script:txtSpawnProtect)
    $lblIdleTimeout = New-Object System.Windows.Forms.Label
    $lblIdleTimeout.Text = '挂机踢出(秒):'
    $lblIdleTimeout.Location = [System.Drawing.Point]::new(480, $y + 3)
    $lblIdleTimeout.Size = [System.Drawing.Size]::new(110, 22)
    $script:txtIdleTimeout = New-Object System.Windows.Forms.TextBox
    $script:txtIdleTimeout.Location = [System.Drawing.Point]::new(595, $y)
    $script:txtIdleTimeout.Size = [System.Drawing.Size]::new(160, 22)
    $panelConfig.Controls.Add($lblIdleTimeout)
    $panelConfig.Controls.Add($script:txtIdleTimeout)
    $y += 34

    $lblMaxTickTime = New-Object System.Windows.Forms.Label
    $lblMaxTickTime.Text = '最大tick时间:'
    $lblMaxTickTime.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblMaxTickTime.Size = [System.Drawing.Size]::new(110, 22)
    $script:txtMaxTickTime = New-Object System.Windows.Forms.TextBox
    $script:txtMaxTickTime.Location = [System.Drawing.Point]::new(135, $y)
    $script:txtMaxTickTime.Size = [System.Drawing.Size]::new(160, 22)
    $panelConfig.Controls.Add($lblMaxTickTime)
    $panelConfig.Controls.Add($script:txtMaxTickTime)
    $lblMaxWorldSize = New-Object System.Windows.Forms.Label
    $lblMaxWorldSize.Text = '最大世界大小:'
    $lblMaxWorldSize.Location = [System.Drawing.Point]::new(480, $y + 3)
    $lblMaxWorldSize.Size = [System.Drawing.Size]::new(110, 22)
    $script:txtMaxWorldSize = New-Object System.Windows.Forms.TextBox
    $script:txtMaxWorldSize.Location = [System.Drawing.Point]::new(595, $y)
    $script:txtMaxWorldSize.Size = [System.Drawing.Size]::new(160, 22)
    $panelConfig.Controls.Add($lblMaxWorldSize)
    $panelConfig.Controls.Add($script:txtMaxWorldSize)
    $y += 34

    $lblNetCompress = New-Object System.Windows.Forms.Label
    $lblNetCompress.Text = '网络压缩阈值:'
    $lblNetCompress.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblNetCompress.Size = [System.Drawing.Size]::new(110, 22)
    $script:txtNetCompress = New-Object System.Windows.Forms.TextBox
    $script:txtNetCompress.Location = [System.Drawing.Point]::new(135, $y)
    $script:txtNetCompress.Size = [System.Drawing.Size]::new(160, 22)
    $panelConfig.Controls.Add($lblNetCompress)
    $panelConfig.Controls.Add($script:txtNetCompress)
    $lblOpLevel = New-Object System.Windows.Forms.Label
    $lblOpLevel.Text = 'OP权限等级:'
    $lblOpLevel.Location = [System.Drawing.Point]::new(480, $y + 3)
    $lblOpLevel.Size = [System.Drawing.Size]::new(110, 22)
    $script:txtOpLevel = New-Object System.Windows.Forms.TextBox
    $script:txtOpLevel.Location = [System.Drawing.Point]::new(595, $y)
    $script:txtOpLevel.Size = [System.Drawing.Size]::new(160, 22)
    $panelConfig.Controls.Add($lblOpLevel)
    $panelConfig.Controls.Add($script:txtOpLevel)
    $y += 34

    $lblFuncLevel = New-Object System.Windows.Forms.Label
    $lblFuncLevel.Text = '功能权限等级:'
    $lblFuncLevel.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblFuncLevel.Size = [System.Drawing.Size]::new(110, 22)
    $script:txtFuncLevel = New-Object System.Windows.Forms.TextBox
    $script:txtFuncLevel.Location = [System.Drawing.Point]::new(135, $y)
    $script:txtFuncLevel.Size = [System.Drawing.Size]::new(160, 22)
    $panelConfig.Controls.Add($lblFuncLevel)
    $panelConfig.Controls.Add($script:txtFuncLevel)
    $lblEntBroadcast = New-Object System.Windows.Forms.Label
    $lblEntBroadcast.Text = '实体广播范围%:'
    $lblEntBroadcast.Location = [System.Drawing.Point]::new(480, $y + 3)
    $lblEntBroadcast.Size = [System.Drawing.Size]::new(110, 22)
    $script:txtEntBroadcast = New-Object System.Windows.Forms.TextBox
    $script:txtEntBroadcast.Location = [System.Drawing.Point]::new(595, $y)
    $script:txtEntBroadcast.Size = [System.Drawing.Size]::new(160, 22)
    $panelConfig.Controls.Add($lblEntBroadcast)
    $panelConfig.Controls.Add($script:txtEntBroadcast)
    $y += 34

    $lblLevelName = New-Object System.Windows.Forms.Label
    $lblLevelName.Text = '地图名称:'
    $lblLevelName.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblLevelName.Size = [System.Drawing.Size]::new(110, 22)
    $script:txtLevelName = New-Object System.Windows.Forms.TextBox
    $script:txtLevelName.Location = [System.Drawing.Point]::new(135, $y)
    $script:txtLevelName.Size = [System.Drawing.Size]::new(160, 22)
    $panelConfig.Controls.Add($lblLevelName)
    $panelConfig.Controls.Add($script:txtLevelName)
    $lblLevelSeed = New-Object System.Windows.Forms.Label
    $lblLevelSeed.Text = '世界种子:'
    $lblLevelSeed.Location = [System.Drawing.Point]::new(480, $y + 3)
    $lblLevelSeed.Size = [System.Drawing.Size]::new(110, 22)
    $script:txtLevelSeed = New-Object System.Windows.Forms.TextBox
    $script:txtLevelSeed.Location = [System.Drawing.Point]::new(595, $y)
    $script:txtLevelSeed.Size = [System.Drawing.Size]::new(160, 22)
    $panelConfig.Controls.Add($lblLevelSeed)
    $panelConfig.Controls.Add($script:txtLevelSeed)
    $y += 34

    $lblLevelType = New-Object System.Windows.Forms.Label
    $lblLevelType.Text = '世界类型:'
    $lblLevelType.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblLevelType.Size = [System.Drawing.Size]::new(110, 22)
    $script:txtLevelType = New-Object System.Windows.Forms.TextBox
    $script:txtLevelType.Location = [System.Drawing.Point]::new(135, $y)
    $script:txtLevelType.Size = [System.Drawing.Size]::new(160, 22)
    $panelConfig.Controls.Add($lblLevelType)
    $panelConfig.Controls.Add($script:txtLevelType)
    $y += 40

    $script:chkAllowFlight = New-Object System.Windows.Forms.CheckBox
    $script:chkAllowFlight.Text = '允许飞行'
    $script:chkAllowFlight.Location = [System.Drawing.Point]::new(135, $y)
    $script:chkAllowFlight.Size = [System.Drawing.Size]::new(130, 24)
    $panelConfig.Controls.Add($script:chkAllowFlight)
    $script:chkSpawnAnimals = New-Object System.Windows.Forms.CheckBox
    $script:chkSpawnAnimals.Text = '生成动物'
    $script:chkSpawnAnimals.Location = [System.Drawing.Point]::new(285, $y)
    $script:chkSpawnAnimals.Size = [System.Drawing.Size]::new(130, 24)
    $panelConfig.Controls.Add($script:chkSpawnAnimals)
    $y += 30
    $script:chkSpawnMonsters = New-Object System.Windows.Forms.CheckBox
    $script:chkSpawnMonsters.Text = '生成怪物'
    $script:chkSpawnMonsters.Location = [System.Drawing.Point]::new(135, $y)
    $script:chkSpawnMonsters.Size = [System.Drawing.Size]::new(130, 24)
    $panelConfig.Controls.Add($script:chkSpawnMonsters)
    $script:chkSpawnNpcs = New-Object System.Windows.Forms.CheckBox
    $script:chkSpawnNpcs.Text = '生成NPC'
    $script:chkSpawnNpcs.Location = [System.Drawing.Point]::new(285, $y)
    $script:chkSpawnNpcs.Size = [System.Drawing.Size]::new(130, 24)
    $panelConfig.Controls.Add($script:chkSpawnNpcs)
    $y += 30
    $script:chkHardcore = New-Object System.Windows.Forms.CheckBox
    $script:chkHardcore.Text = '极限模式'
    $script:chkHardcore.Location = [System.Drawing.Point]::new(135, $y)
    $script:chkHardcore.Size = [System.Drawing.Size]::new(130, 24)
    $panelConfig.Controls.Add($script:chkHardcore)
    $script:chkGenStructures = New-Object System.Windows.Forms.CheckBox
    $script:chkGenStructures.Text = '生成结构'
    $script:chkGenStructures.Location = [System.Drawing.Point]::new(285, $y)
    $script:chkGenStructures.Size = [System.Drawing.Size]::new(130, 24)
    $panelConfig.Controls.Add($script:chkGenStructures)
    $y += 30
    $script:chkAllowNether = New-Object System.Windows.Forms.CheckBox
    $script:chkAllowNether.Text = '允许下界'
    $script:chkAllowNether.Location = [System.Drawing.Point]::new(135, $y)
    $script:chkAllowNether.Size = [System.Drawing.Size]::new(130, 24)
    $panelConfig.Controls.Add($script:chkAllowNether)
    $script:chkEnforceWhitelist = New-Object System.Windows.Forms.CheckBox
    $script:chkEnforceWhitelist.Text = '强制白名单'
    $script:chkEnforceWhitelist.Location = [System.Drawing.Point]::new(285, $y)
    $script:chkEnforceWhitelist.Size = [System.Drawing.Size]::new(130, 24)
    $panelConfig.Controls.Add($script:chkEnforceWhitelist)
    $y += 30
    $script:chkEnableStatus = New-Object System.Windows.Forms.CheckBox
    $script:chkEnableStatus.Text = '服务器状态'
    $script:chkEnableStatus.Location = [System.Drawing.Point]::new(135, $y)
    $script:chkEnableStatus.Size = [System.Drawing.Size]::new(130, 24)
    $panelConfig.Controls.Add($script:chkEnableStatus)
    $script:chkEnableQuery = New-Object System.Windows.Forms.CheckBox
    $script:chkEnableQuery.Text = '查询协议'
    $script:chkEnableQuery.Location = [System.Drawing.Point]::new(285, $y)
    $script:chkEnableQuery.Size = [System.Drawing.Size]::new(130, 24)
    $panelConfig.Controls.Add($script:chkEnableQuery)
    $y += 30
    $script:chkSyncChunkWrites = New-Object System.Windows.Forms.CheckBox
    $script:chkSyncChunkWrites.Text = '同步区块写入'
    $script:chkSyncChunkWrites.Location = [System.Drawing.Point]::new(135, $y)
    $script:chkSyncChunkWrites.Size = [System.Drawing.Size]::new(130, 24)
    $panelConfig.Controls.Add($script:chkSyncChunkWrites)
    $script:chkHideOnline = New-Object System.Windows.Forms.CheckBox
    $script:chkHideOnline.Text = '隐藏在线玩家'
    $script:chkHideOnline.Location = [System.Drawing.Point]::new(285, $y)
    $script:chkHideOnline.Size = [System.Drawing.Size]::new(130, 24)
    $panelConfig.Controls.Add($script:chkHideOnline)
    $y += 30
    $script:chkLogIps = New-Object System.Windows.Forms.CheckBox
    $script:chkLogIps.Text = '记录IP'
    $script:chkLogIps.Location = [System.Drawing.Point]::new(135, $y)
    $script:chkLogIps.Size = [System.Drawing.Size]::new(130, 24)
    $panelConfig.Controls.Add($script:chkLogIps)
    $script:chkBroadcastOps = New-Object System.Windows.Forms.CheckBox
    $script:chkBroadcastOps.Text = '控制台广播给OP'
    $script:chkBroadcastOps.Location = [System.Drawing.Point]::new(285, $y)
    $script:chkBroadcastOps.Size = [System.Drawing.Size]::new(150, 24)
    $panelConfig.Controls.Add($script:chkBroadcastOps)
    $y += 36

    $lblMoreTip = New-Object System.Windows.Forms.Label
    $lblMoreTip.Text = '提示：世界种子/世界类型只对新生成的存档生效；地图名称改动前先备份。'
    $lblMoreTip.Location = [System.Drawing.Point]::new(20, $y)
    $lblMoreTip.Size = [System.Drawing.Size]::new(760, 22)
    $lblMoreTip.ForeColor = [System.Drawing.Color]::Gray
    $panelConfig.Controls.Add($lblMoreTip)

    # ---------- 玩家页 ----------
    $tabPlayers = New-Object System.Windows.Forms.TabPage
    $tabPlayers.Text = '玩家管理'
    $tabs.TabPages.Add($tabPlayers)

    $script:lstPlayers = New-Object System.Windows.Forms.ListBox
    $script:lstPlayers.Dock = [System.Windows.Forms.DockStyle]::Fill
    $tabPlayers.Controls.Add($script:lstPlayers)

    $panelPlayers = New-Object System.Windows.Forms.Panel
    $panelPlayers.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $panelPlayers.Height = 120
    $tabPlayers.Controls.Add($panelPlayers)

    $lblPlayerName = New-Object System.Windows.Forms.Label
    $lblPlayerName.Text = '玩家ID:'
    $lblPlayerName.Location = [System.Drawing.Point]::new(10, 12)
    $lblPlayerName.Size = [System.Drawing.Size]::new(60, 22)
    $panelPlayers.Controls.Add($lblPlayerName)
    $script:txtPlayer = New-Object System.Windows.Forms.TextBox
    $script:txtPlayer.Location = [System.Drawing.Point]::new(75, 10)
    $script:txtPlayer.Size = [System.Drawing.Size]::new(200, 22)
    $panelPlayers.Controls.Add($script:txtPlayer)
    $btnAddPlayer = New-Object System.Windows.Forms.Button
    $btnAddPlayer.Text = '加白名单'
    $btnAddPlayer.Location = [System.Drawing.Point]::new(285, 8)
    $btnAddPlayer.Size = [System.Drawing.Size]::new(100, 26)
    $panelPlayers.Controls.Add($btnAddPlayer)
    $btnRemovePlayer = New-Object System.Windows.Forms.Button
    $btnRemovePlayer.Text = '移除白名单'
    $btnRemovePlayer.Location = [System.Drawing.Point]::new(395, 8)
    $btnRemovePlayer.Size = [System.Drawing.Size]::new(100, 26)
    $panelPlayers.Controls.Add($btnRemovePlayer)
    $btnOp = New-Object System.Windows.Forms.Button
    $btnOp.Text = '设为 OP'
    $btnOp.Location = [System.Drawing.Point]::new(505, 8)
    $btnOp.Size = [System.Drawing.Size]::new(100, 26)
    $panelPlayers.Controls.Add($btnOp)
    $btnDeop = New-Object System.Windows.Forms.Button
    $btnDeop.Text = '取消 OP'
    $btnDeop.Location = [System.Drawing.Point]::new(615, 8)
    $btnDeop.Size = [System.Drawing.Size]::new(100, 26)
    $panelPlayers.Controls.Add($btnDeop)
    $btnRefreshPlayers = New-Object System.Windows.Forms.Button
    $btnRefreshPlayers.Text = '刷新'
    $btnRefreshPlayers.Location = [System.Drawing.Point]::new(725, 8)
    $btnRefreshPlayers.Size = [System.Drawing.Size]::new(70, 26)
    $panelPlayers.Controls.Add($btnRefreshPlayers)
    $btnEditWhitelist = New-Object System.Windows.Forms.Button
    $btnEditWhitelist.Text = '编辑 whitelist.json'
    $btnEditWhitelist.Location = [System.Drawing.Point]::new(75, 46)
    $btnEditWhitelist.Size = [System.Drawing.Size]::new(160, 26)
    $panelPlayers.Controls.Add($btnEditWhitelist)
    $btnEditOps = New-Object System.Windows.Forms.Button
    $btnEditOps.Text = '编辑 ops.json'
    $btnEditOps.Location = [System.Drawing.Point]::new(245, 46)
    $btnEditOps.Size = [System.Drawing.Size]::new(150, 26)
    $panelPlayers.Controls.Add($btnEditOps)
    $script:lblPlayersHint = New-Object System.Windows.Forms.Label
    $script:lblPlayersHint.Location = [System.Drawing.Point]::new(10, 84)
    $script:lblPlayersHint.Size = [System.Drawing.Size]::new(800, 26)
    $script:lblPlayersHint.ForeColor = [System.Drawing.Color]::Gray
    $panelPlayers.Controls.Add($script:lblPlayersHint)

    # ---------- 模组页 ----------
    $tabMods = New-Object System.Windows.Forms.TabPage
    $tabMods.Text = '模组管理'
    $tabs.TabPages.Add($tabMods)

    $script:lstMods = New-Object System.Windows.Forms.ListBox
    $script:lstMods.Dock = [System.Windows.Forms.DockStyle]::Fill
    $tabMods.Controls.Add($script:lstMods)

    $panelMods = New-Object System.Windows.Forms.Panel
    $panelMods.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $panelMods.Height = 46
    $tabMods.Controls.Add($panelMods)
    $btnToggleMod = New-Object System.Windows.Forms.Button
    $btnToggleMod.Text = '启用 / 禁用'
    $btnToggleMod.Location = [System.Drawing.Point]::new(75, 10)
    $btnToggleMod.Size = [System.Drawing.Size]::new(120, 26)
    $panelMods.Controls.Add($btnToggleMod)
    $btnDeleteMod = New-Object System.Windows.Forms.Button
    $btnDeleteMod.Text = '删除模组'
    $btnDeleteMod.Location = [System.Drawing.Point]::new(205, 10)
    $btnDeleteMod.Size = [System.Drawing.Size]::new(120, 26)
    $panelMods.Controls.Add($btnDeleteMod)
    $btnRefreshMods = New-Object System.Windows.Forms.Button
    $btnRefreshMods.Text = '刷新'
    $btnRefreshMods.Location = [System.Drawing.Point]::new(335, 10)
    $btnRefreshMods.Size = [System.Drawing.Size]::new(80, 26)
    $panelMods.Controls.Add($btnRefreshMods)
    $lblModsTip = New-Object System.Windows.Forms.Label
    $lblModsTip.Text = '禁用 = 重命名为 .jar.disabled（不删除，可随时恢复）。改完模组记得重启服务器。'
    $lblModsTip.Location = [System.Drawing.Point]::new(430, 13)
    $lblModsTip.Size = [System.Drawing.Size]::new(500, 22)
    $lblModsTip.ForeColor = [System.Drawing.Color]::Gray
    $panelMods.Controls.Add($lblModsTip)

    # ---------- 穿透页 ----------
    $tabFrp = New-Object System.Windows.Forms.TabPage
    $tabFrp.Text = '内网穿透 (frp)'
    $tabs.TabPages.Add($tabFrp)

    $txtFrpLog = New-Object System.Windows.Forms.TextBox
    $txtFrpLog.Multiline = $true
    $txtFrpLog.ReadOnly = $true
    $txtFrpLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $txtFrpLog.WordWrap = $false
    $txtFrpLog.Dock = [System.Windows.Forms.DockStyle]::Fill
    $txtFrpLog.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $txtFrpLog.ForeColor = [System.Drawing.Color]::White
    $txtFrpLog.Font = New-Object System.Drawing.Font('Consolas', 9)
    $script:txtFrpc = $txtFrpLog
    $tabFrp.Controls.Add($txtFrpLog)

    $panelFrp = New-Object System.Windows.Forms.Panel
    $panelFrp.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $panelFrp.Height = 110
    $tabFrp.Controls.Add($panelFrp)

    $lblFrpcExe = New-Object System.Windows.Forms.Label
    $lblFrpcExe.Text = 'frpc.exe:'
    $lblFrpcExe.Location = [System.Drawing.Point]::new(10, 12)
    $lblFrpcExe.Size = [System.Drawing.Size]::new(80, 22)
    $panelFrp.Controls.Add($lblFrpcExe)
    $script:txtFrpcExe = New-Object System.Windows.Forms.TextBox
    $script:txtFrpcExe.Location = [System.Drawing.Point]::new(95, 10)
    $script:txtFrpcExe.Size = [System.Drawing.Size]::new(520, 22)
    $panelFrp.Controls.Add($script:txtFrpcExe)
    $btnBrowseFrpcExe = New-Object System.Windows.Forms.Button
    $btnBrowseFrpcExe.Text = '选择...'
    $btnBrowseFrpcExe.Location = [System.Drawing.Point]::new(625, 8)
    $btnBrowseFrpcExe.Size = [System.Drawing.Size]::new(80, 26)
    $panelFrp.Controls.Add($btnBrowseFrpcExe)
    $lblFrpcCfg = New-Object System.Windows.Forms.Label
    $lblFrpcCfg.Text = 'frpc.toml:'
    $lblFrpcCfg.Location = [System.Drawing.Point]::new(10, 48)
    $lblFrpcCfg.Size = [System.Drawing.Size]::new(80, 22)
    $panelFrp.Controls.Add($lblFrpcCfg)
    $script:txtFrpcCfg = New-Object System.Windows.Forms.TextBox
    $script:txtFrpcCfg.Location = [System.Drawing.Point]::new(95, 46)
    $script:txtFrpcCfg.Size = [System.Drawing.Size]::new(520, 22)
    $panelFrp.Controls.Add($script:txtFrpcCfg)
    $btnBrowseFrpcCfg = New-Object System.Windows.Forms.Button
    $btnBrowseFrpcCfg.Text = '选择...'
    $btnBrowseFrpcCfg.Location = [System.Drawing.Point]::new(625, 44)
    $btnBrowseFrpcCfg.Size = [System.Drawing.Size]::new(80, 26)
    $panelFrp.Controls.Add($btnBrowseFrpcCfg)
    $btnFrpStart = New-Object System.Windows.Forms.Button
    $btnFrpStart.Text = '启动穿透'
    $btnFrpStart.Location = [System.Drawing.Point]::new(95, 78)
    $btnFrpStart.Size = [System.Drawing.Size]::new(110, 28)
    $panelFrp.Controls.Add($btnFrpStart)
    $btnFrpStop = New-Object System.Windows.Forms.Button
    $btnFrpStop.Text = '停止穿透'
    $btnFrpStop.Location = [System.Drawing.Point]::new(215, 78)
    $btnFrpStop.Size = [System.Drawing.Size]::new(110, 28)
    $panelFrp.Controls.Add($btnFrpStop)
    $lblFrpTip = New-Object System.Windows.Forms.Label
    $lblFrpTip.Text = 'frpc.toml 示例：serverAddr=云服务器IP, serverPort=7000, 下面 [[proxies]] 转发 25565 等端口'
    $lblFrpTip.Location = [System.Drawing.Point]::new(340, 82)
    $lblFrpTip.Size = [System.Drawing.Size]::new(550, 22)
    $lblFrpTip.ForeColor = [System.Drawing.Color]::Gray
    $panelFrp.Controls.Add($lblFrpTip)

    # ---------- 发送脚本页 ----------
    $tabSsh = New-Object System.Windows.Forms.TabPage
    $tabSsh.Text = '发送脚本到服务器'
    $tabs.TabPages.Add($tabSsh)

    $y = 30
    $lblSshIp = New-Object System.Windows.Forms.Label
    $lblSshIp.Text = '服务器IP:'
    $lblSshIp.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblSshIp.Size = [System.Drawing.Size]::new(110, 22)
    $tabSsh.Controls.Add($lblSshIp)
    $script:txtSshIp = New-Object System.Windows.Forms.TextBox
    $script:txtSshIp.Location = [System.Drawing.Point]::new(135, $y)
    $script:txtSshIp.Size = [System.Drawing.Size]::new(200, 22)
    $tabSsh.Controls.Add($script:txtSshIp)
    $lblSshUser = New-Object System.Windows.Forms.Label
    $lblSshUser.Text = '用户名:'
    $lblSshUser.Location = [System.Drawing.Point]::new(360, $y + 3)
    $lblSshUser.Size = [System.Drawing.Size]::new(70, 22)
    $tabSsh.Controls.Add($lblSshUser)
    $script:txtSshUser = New-Object System.Windows.Forms.TextBox
    $script:txtSshUser.Location = [System.Drawing.Point]::new(435, $y)
    $script:txtSshUser.Size = [System.Drawing.Size]::new(120, 22)
    $tabSsh.Controls.Add($script:txtSshUser)
    $y += 36

    $lblSshScript = New-Object System.Windows.Forms.Label
    $lblSshScript.Text = '脚本文件:'
    $lblSshScript.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblSshScript.Size = [System.Drawing.Size]::new(110, 22)
    $tabSsh.Controls.Add($lblSshScript)
    $script:txtSshScript = New-Object System.Windows.Forms.TextBox
    $script:txtSshScript.Location = [System.Drawing.Point]::new(135, $y)
    $script:txtSshScript.Size = [System.Drawing.Size]::new(400, 22)
    $tabSsh.Controls.Add($script:txtSshScript)
    $btnSshScript = New-Object System.Windows.Forms.Button
    $btnSshScript.Text = '选择...'
    $btnSshScript.Location = [System.Drawing.Point]::new(545, $y - 1)
    $btnSshScript.Size = [System.Drawing.Size]::new(80, 26)
    $tabSsh.Controls.Add($btnSshScript)
    $y += 36

    $lblSshRemote = New-Object System.Windows.Forms.Label
    $lblSshRemote.Text = '远端目录:'
    $lblSshRemote.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblSshRemote.Size = [System.Drawing.Size]::new(110, 22)
    $tabSsh.Controls.Add($lblSshRemote)
    $script:txtSshRemote = New-Object System.Windows.Forms.TextBox
    $script:txtSshRemote.Location = [System.Drawing.Point]::new(135, $y)
    $script:txtSshRemote.Size = [System.Drawing.Size]::new(200, 22)
    $tabSsh.Controls.Add($script:txtSshRemote)
    $lblSshRemoteHint = New-Object System.Windows.Forms.Label
    $lblSshRemoteHint.Text = '留空则上传到主目录 ~/'
    $lblSshRemoteHint.Location = [System.Drawing.Point]::new(345, $y + 3)
    $lblSshRemoteHint.Size = [System.Drawing.Size]::new(300, 22)
    $lblSshRemoteHint.ForeColor = [System.Drawing.Color]::Gray
    $tabSsh.Controls.Add($lblSshRemoteHint)
    $y += 36

    $lblSshToken = New-Object System.Windows.Forms.Label
    $lblSshToken.Text = 'frp 认证密码:'
    $lblSshToken.Location = [System.Drawing.Point]::new(20, $y + 3)
    $lblSshToken.Size = [System.Drawing.Size]::new(110, 22)
    $tabSsh.Controls.Add($lblSshToken)
    $script:txtSshToken = New-Object System.Windows.Forms.TextBox
    $script:txtSshToken.Location = [System.Drawing.Point]::new(135, $y)
    $script:txtSshToken.Size = [System.Drawing.Size]::new(200, 22)
    $tabSsh.Controls.Add($script:txtSshToken)
    $lblSshTokenHint = New-Object System.Windows.Forms.Label
    $lblSshTokenHint.Text = '执行 install-frps.sh 时用作 frps 认证密码（需和本地 frpc.toml 一致）'
    $lblSshTokenHint.Location = [System.Drawing.Point]::new(345, $y + 3)
    $lblSshTokenHint.Size = [System.Drawing.Size]::new(460, 22)
    $lblSshTokenHint.ForeColor = [System.Drawing.Color]::Gray
    $tabSsh.Controls.Add($lblSshTokenHint)
    $y += 40

    $btnSshUpload = New-Object System.Windows.Forms.Button
    $btnSshUpload.Text = '上传脚本'
    $btnSshUpload.Location = [System.Drawing.Point]::new(135, $y)
    $btnSshUpload.Size = [System.Drawing.Size]::new(130, 34)
    $tabSsh.Controls.Add($btnSshUpload)
    $btnSshExec = New-Object System.Windows.Forms.Button
    $btnSshExec.Text = '上传并执行'
    $btnSshExec.Location = [System.Drawing.Point]::new(280, $y)
    $btnSshExec.Size = [System.Drawing.Size]::new(150, 34)
    $tabSsh.Controls.Add($btnSshExec)
    $y += 48

    $lblSshTip = New-Object System.Windows.Forms.Label
    $lblSshTip.Text = '提示：点击后会弹出黑色窗口，在窗口里输入服务器 SSH 密码即可完成传输（执行 sudo 命令时再输一次密码）。' + "`r`n" + '传输的是 scp（OpenSSH 自带）。上方"frp 认证密码"仅在"上传并执行 install-frps.sh"时自动传给脚本作为 frps 的认证 token。'
    $lblSshTip.Location = [System.Drawing.Point]::new(20, $y)
    $lblSshTip.Size = [System.Drawing.Size]::new(800, 46)
    $lblSshTip.ForeColor = [System.Drawing.Color]::Gray
    $tabSsh.Controls.Add($lblSshTip)

    # ---------- 底部状态栏 ----------
    $panelStatus = New-Object System.Windows.Forms.FlowLayoutPanel
    $panelStatus.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $panelStatus.Height = 28
    $panelStatus.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $panelStatus.WrapContents = $false
    $panelStatus.Padding = [System.Windows.Forms.Padding]::new(6, 3, 0, 0)
    $lblServerPrefix = New-Object System.Windows.Forms.Label
    $lblServerPrefix.AutoSize = $true
    $lblServerPrefix.Text = '服务器'
    $panelStatus.Controls.Add($lblServerPrefix)
    $script:lblServerState = New-Object System.Windows.Forms.Label
    $script:lblServerState.AutoSize = $true
    $script:lblServerState.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
    $script:lblServerState.Text = '[未运行]'
    $script:lblServerState.ForeColor = [System.Drawing.Color]::Gray
    $panelStatus.Controls.Add($script:lblServerState)
    $lblFrpcPrefix = New-Object System.Windows.Forms.Label
    $lblFrpcPrefix.AutoSize = $true
    $lblFrpcPrefix.Text = ' | frpc'
    $panelStatus.Controls.Add($lblFrpcPrefix)
    $script:lblFrpcState = New-Object System.Windows.Forms.Label
    $script:lblFrpcState.AutoSize = $true
    $script:lblFrpcState.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
    $script:lblFrpcState.Text = '[未运行]'
    $script:lblFrpcState.ForeColor = [System.Drawing.Color]::Gray
    $panelStatus.Controls.Add($script:lblFrpcState)
    $script:lblStatus = New-Object System.Windows.Forms.Label
    $script:lblStatus.AutoSize = $true
    $script:lblStatus.Text = '就绪'
    $panelStatus.Controls.Add($script:lblStatus)
    $form.Controls.Add($panelStatus)

    # ================= 事件 =================
    $btnBrowseDir.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = '选择 Minecraft 服务器目录'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:serverDir = $dlg.SelectedPath
            $script:txtServerDir.Text = $dlg.SelectedPath
            Save-Settings
            if ($script:lstPlayers) { Refresh-PlayerList }
            if ($script:lstMods) { Refresh-ModList }
            if ($script:comboDiff) { Load-QuickConfigFromServer }
            if ($script:txtJava) { Match-JavaForServerDir }
        }
    })
    $btnOpenDir.Add_Click({
        if ($script:serverDir -and (Test-Path -LiteralPath $script:serverDir)) {
            Start-Process explorer.exe -ArgumentList $script:serverDir
        } else {
            [System.Windows.Forms.MessageBox]::Show('请先选择服务器目录。', '提示') | Out-Null
        }
    })
    $btnBrowseJava.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = 'java.exe|java.exe'
        $dlg.Title = '选择 java.exe'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:javaPath = $dlg.FileName
            $script:txtJava.Text = $dlg.FileName
            Save-Settings
        }
    })
    $btnFindJava.Add_Click({
        $major = $null
        if ($script:serverDir) {
            $mcVer = Get-McVersionFromServerDir -Dir $script:serverDir
            if ($mcVer) { $major = Get-RequiredJavaMajor -McVersion $mcVer }
        }
        if (-not $major -and $script:txtFMcVersion) {
            $mcVer = $script:txtFMcVersion.Text.Trim()
            if ($mcVer) { $major = Get-RequiredJavaMajor -McVersion $mcVer }
        }
        Set-UiStatus '正在查找匹配的 Java...'
        $found = if ($major) { Find-JavaByMajor -Major $major } else { $null }
        if ($found) {
            $script:javaPath = $found
            $script:txtJava.Text = $found
            Set-UiStatus "已找到匹配的 Java $major"
        } else {
            $msg = if ($major) { "没有找到 Java $major，请点下载安装或手动选择。" } else { '请先填写服务器目录或 Minecraft 版本。' }
            [System.Windows.Forms.MessageBox]::Show($msg, '提示') | Out-Null
            Set-UiStatus '未找到匹配的 Java'
        }
        Save-Settings
    })
    $script:btnDownloadJava.Add_Click({
        $result = Download-NeededJava
        if ($result) {
            $script:txtJava.Text = $result
            [System.Windows.Forms.MessageBox]::Show('Java 安装完成: ' + $result, '完成') | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show('安装失败，请手动下载对应 Java。', '错误') | Out-Null
        }
        Save-Settings
    })
    $script:txtServerDir.Add_TextChanged({
        $script:serverDir = $script:txtServerDir.Text
        if ($script:txtJava) { Match-JavaForServerDir }
        if ($script:txtFrpcExe) { Auto-MatchFrpForServerDir }
        if ($script:serverDir -and -not $script:switchingServer) {
            Add-ServerProfile -Dir $script:serverDir
            Refresh-ServerCombo
        }
        Save-Settings
    })
    $script:txtServerDir.Add_LostFocus({
        if ($script:lstPlayers) { Refresh-PlayerList }
        if ($script:lstMods) { Refresh-ModList }
        if ($script:comboDiff) { Load-QuickConfigFromServer }
    })
    $script:comboServers.Add_SelectedIndexChanged({
        $sel = [string]$script:comboServers.SelectedItem
        if (-not $sel) { return }
        $dir = $sel
        if ($sel -match '\((.+)\)\s*$') { $dir = $matches[1].Trim() }
        if (-not $dir -or $dir -eq $script:serverDir) { return }
        $script:switchingServer = $true
        $script:txtServerDir.Text = $dir
        $script:serverDir = $dir
        Apply-ServerProfile -Dir $dir
        if ($script:txtJava) { Match-JavaForServerDir }
        if ($script:lstPlayers) { Refresh-PlayerList }
        if ($script:lstMods) { Refresh-ModList }
        if ($script:comboDiff) { Load-QuickConfigFromServer }
        $script:switchingServer = $false
        Save-Settings
    })
    $btnAddServer.Add_Click({
        if (-not $script:serverDir) {
            [System.Windows.Forms.MessageBox]::Show('请先填写服务器目录。', '提示') | Out-Null
            return
        }
        Add-ServerProfile -Dir $script:serverDir
        Refresh-ServerCombo
        Save-Settings
        [System.Windows.Forms.MessageBox]::Show('已添加: ' + $script:serverDir, '完成') | Out-Null
    })
    $script:txtJava.Add_TextChanged({
        $script:javaPath = $script:txtJava.Text
        if ($script:lblFJavaStatus) { $script:lblFJavaStatus.Text = if ($script:javaPath) { "已设置: $script:javaPath" } else { '未检测' } }
    })
    $script:numMem.Add_ValueChanged({ $script:maxMem = [int]$script:numMem.Value })
    $script:comboAuthMode.Add_SelectedIndexChanged({
        $script:authMode = switch ($script:comboAuthMode.SelectedIndex) {
            0 { 'premium' }
            default { 'thirdparty' }
        }
        $script:useAuth = ($script:authMode -eq 'thirdparty')
        if ($script:authMode -eq 'premium' -and $script:comboSkin -and $script:comboSkin.Items.Contains('离线模式')) {
            $script:comboSkin.SelectedItem = '离线模式'
            $script:skinStation = '离线模式'
        }
        if ($script:comboSkin) { $script:comboSkin.Enabled = ($script:authMode -eq 'thirdparty') }
        if ($script:txtAuthUrl) { $script:txtAuthUrl.Enabled = ($script:authMode -eq 'thirdparty') }
        if ($script:btnGenBat) { $script:btnGenBat.Enabled = $true }
        if ($script:chkOnline) {
            $script:chkOnline.Checked = ($script:authMode -eq 'premium' -or ($script:authMode -eq 'thirdparty' -and $script:skinStation -ne '离线模式'))
        }
        Sync-AuthToServerProps
        Save-Settings
    })
    $script:comboSkin.Add_SelectedIndexChanged({
        $script:skinStation = [string]$script:comboSkin.SelectedItem
        if ($script:skinStation -ne '自定义' -and $script:skinStation -ne '离线模式') {
            $script:authUrl = Get-SkinStationUrl -Name $script:skinStation
            $script:txtAuthUrl.Text = $script:authUrl
        } elseif ($script:skinStation -eq '离线模式') {
            $script:authUrl = ''
            $script:txtAuthUrl.Text = ''
        }
        if ($script:txtAuthUrl) { $script:txtAuthUrl.Enabled = ($script:skinStation -eq '自定义') }
        if ($script:chkOnline) {
            $script:chkOnline.Checked = ($script:authMode -eq 'premium' -or ($script:authMode -eq 'thirdparty' -and $script:skinStation -ne '离线模式'))
        }
        Sync-AuthToServerProps
        Save-Settings
    })
    $script:txtAuthUrl.Add_TextChanged({
        $script:authUrl = $script:txtAuthUrl.Text
        if ($script:comboSkin -and $script:comboSkin.SelectedItem -and [string]$script:comboSkin.SelectedItem -ne '自定义' -and [string]$script:comboSkin.SelectedItem -ne '离线模式') {
            $auto = Get-SkinStationNameFromUrl -Url $script:authUrl
            if ($auto -ne '自定义' -and $auto -ne '离线模式') {
                $script:skinStation = $auto
                $script:comboSkin.SelectedItem = $auto
            }
        }
        Save-Settings
    })
    $btnGenBat.Add_Click({
        if (-not $script:serverDir -or -not (Test-Path -LiteralPath $script:serverDir)) {
            [System.Windows.Forms.MessageBox]::Show('请先选择服务器目录。', '提示') | Out-Null
            return
        }
        $batPath = Write-RunBat -ServerDir $script:serverDir
        if ($batPath -and -not ($batPath -is [string] -and $batPath.StartsWith('ERR:'))) {
            [System.Windows.Forms.MessageBox]::Show('已生成: ' + $batPath + "`r`n登录方式: " + $script:comboAuthMode.SelectedItem, '完成', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } elseif ($batPath -is [string] -and $batPath.StartsWith('ERR:')) {
            [System.Windows.Forms.MessageBox]::Show('生成失败（可能是 run.bat 被占用或无权限）: ' + $batPath.Substring(4), '错误') | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show('生成失败：目录里没有可识别的服务端启动文件（server.jar / fabric / forge / neoforge）。', '错误') | Out-Null
        }
    })
    $script:txtMaxPlayers.Add_TextChanged({
        $v = 12
        try { $v = [int]$script:txtMaxPlayers.Text.Trim() } catch { }
        $script:maxPlayers = $v
        Save-Settings
    })
    $script:txtFZip.Add_TextChanged({ $script:freshZip = $script:txtFZip.Text; Save-Settings })
    $script:txtFDir.Add_TextChanged({ $script:freshDir = $script:txtFDir.Text; Save-Settings })
    $script:txtFIp.Add_TextChanged({ $script:frpIp = $script:txtFIp.Text; Save-Settings })
    $script:txtFFrpPort.Add_TextChanged({ $script:frpPort = $script:txtFFrpPort.Text; Save-Settings })
    $script:txtFToken.Add_TextChanged({ $script:frpToken = $script:txtFToken.Text; Save-Settings })
    $script:chkFUseFrp.Add_CheckedChanged({
        if ($script:chkFUseFrp.Checked) { Ensure-FreshFrpTokenField }
    })
    $script:txtFGamePort.Add_TextChanged({ $script:gamePort = $script:txtFGamePort.Text; Save-Settings })
    $script:txtFVoicePort.Add_TextChanged({ $script:voicePort = $script:txtFVoicePort.Text; Save-Settings })
    $btnStart.Add_Click({ Start-MCServer })
    $btnStop.Add_Click({ Stop-MCServer })
    $btnRestart.Add_Click({
        Stop-MCServer
        Start-MCServer
    })
    $btnStatus.Add_Click({
        $lines = @(Get-RunningOverview)
        [System.Windows.Forms.MessageBox]::Show(($lines -join "`r`n"), '运行状态', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        foreach ($l in $lines) {
            $script:txtConsole.AppendText("`r`n[状态] $l")
        }
    })

    $btnFZip.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = '压缩包 (*.zip)|*.zip'
        $dlg.Title = '选择服务器压缩包'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:txtFZip.Text = $dlg.FileName
        }
    })
    $btnFDir.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = '选择安装目录'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:txtFDir.Text = $dlg.SelectedPath
        }
    })
    $btnFFindJava.Add_Click({
        $mcVer = $script:txtFMcVersion.Text.Trim()
        if (-not $mcVer) {
            [System.Windows.Forms.MessageBox]::Show('请先填写 Minecraft 版本。', '提示') | Out-Null
            return
        }
        $major = Get-RequiredJavaMajor -McVersion $mcVer
        Set-UiStatus "正在查找 Java $major..."
        $found = Find-JavaByMajor -Major $major
        if ($found) {
            $script:javaPath = $found
            $script:txtJava.Text = $found
            $script:lblFJavaStatus.Text = "已找到: $found"
            Set-UiStatus "已找到 Java $major"
        } else {
            $script:lblFJavaStatus.Text = "未找到 Java $major"
            [System.Windows.Forms.MessageBox]::Show("未找到 Java $major，请点`"下载安装`"或手动选择 java.exe。", '提示') | Out-Null
            Set-UiStatus "未找到 Java $major"
        }
        Save-Settings
    })
    $btnFDownloadJava.Add_Click({
        $result = Download-NeededJava
        if ($result) {
            $script:txtJava.Text = $result
            $script:lblFJavaStatus.Text = "已安装: $result"
            [System.Windows.Forms.MessageBox]::Show('Java 安装完成。', '完成') | Out-Null
        } else {
            $script:lblFJavaStatus.Text = '安装失败'
            [System.Windows.Forms.MessageBox]::Show('Java 安装失败，请手动下载。', '错误') | Out-Null
        }
        Save-Settings
    })
    $script:btnFJavaFile.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = '选择 java.exe'
        $dlg.Filter = 'Java 可执行文件 (java.exe)|java.exe|所有文件 (*.*)|*.*'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:javaPath = $dlg.FileName
            $script:txtJava.Text = $dlg.FileName
            $script:lblFJavaStatus.Text = "已选择: $($dlg.FileName)"
            $mcVer = $script:txtFMcVersion.Text.Trim()
            if ($mcVer) {
                $major = Get-RequiredJavaMajor -McVersion $mcVer
                try {
                    $v = (& $dlg.FileName -version 2>&1 | Out-String)
                    if ($v -match 'version "(\d+)') {
                        $verMajor = [int]$matches[1]
                        if ($verMajor -ne $major) {
                            [System.Windows.Forms.MessageBox]::Show("注意：该 Java 是 $verMajor 版，当前 MC 版本需要 Java $major，可能无法启动。", '提示') | Out-Null
                        }
                    }
                } catch { }
            }
            Save-Settings
        }
    })
    $btnFJavaDir.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = '选择 Java 安装目录'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:txtFJavaInstallDir.Text = $dlg.SelectedPath
        }
    })
    $script:txtFJavaInstallDir.Add_TextChanged({
        $script:javaInstallDir = $script:txtFJavaInstallDir.Text.Trim()
        Save-Settings
    })
    $script:txtFMcVersion.Add_LostFocus({
        $script:freshMcVersion = $script:txtFMcVersion.Text.Trim()
        Match-JavaForVersion
    })
    $btnFullDeploy.Add_Click({
        $gamePort = 25565
        $voicePort = 24454
        try { $gamePort = [int]$script:txtFGamePort.Text.Trim() } catch { }
        try { $voicePort = [int]$script:txtFVoicePort.Text.Trim() } catch { }
        Deploy-FromScratch -ZipPath $script:txtFZip.Text -DestDir $script:txtFDir.Text -UseFrp $script:chkFUseFrp.Checked -FrpIp $script:txtFIp.Text -FrpPort $script:txtFFrpPort.Text.Trim() -FrpToken $script:txtFToken.Text -GamePort $gamePort -VoicePort $voicePort
    })
    $btnSend.Add_Click({
        $cmd = $script:txtCmd.Text.Trim()
        if (-not $cmd) { return }
        $result = Send-RconFireForget -Command $cmd
        if ($result) {
            $script:txtConsole.AppendText("`r`n> $cmd`r`n[发送失败] $result`r`n")
        } else {
            $script:txtConsole.AppendText("`r`n> $cmd`r`n[已发送，服务器处理中，结果见上方日志]`r`n")
        }
        $script:txtCmd.Clear()
        $script:txtCmd.Focus()
    })
    $script:txtCmd.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $btnSend.PerformClick()
            $_.SuppressKeyPress = $true
        }
    })
    $btnClearConsole.Add_Click({
        $script:txtConsole.Clear()
        $script:consolePos = 0
    })

    $btnSaveConfig.Add_Click({
        if (-not $script:serverDir -or -not (Test-Path -LiteralPath (Join-Path $script:serverDir 'server.properties'))) {
            [System.Windows.Forms.MessageBox]::Show('请先选择包含 server.properties 的服务器目录。', '提示') | Out-Null
            return
        }
        $changes = @{
            'difficulty'       = $script:comboDiff.SelectedItem
            'gamemode'         = $script:comboGm.SelectedItem
            'motd'             = $script:txtMotd.Text.Trim()
            'max-players'      = $script:txtMaxPlayers.Text.Trim()
            'pvp'              = if ($script:chkPvp.Checked) { 'true' } else { 'false' }
            'white-list'       = if ($script:chkWhitelist.Checked) { 'true' } else { 'false' }
            'force-gamemode'   = if ($script:chkForce.Checked) { 'true' } else { 'false' }
            'enable-command-block' = if ($script:chkCmdBlock.Checked) { 'true' } else { 'false' }
            'online-mode'      = if ($script:chkOnline.Checked) { 'true' } else { 'false' }
            'view-distance'    = $script:txtViewDist.Text.Trim()
            'simulation-distance' = $script:txtSimDist.Text.Trim()
            'spawn-protection' = $script:txtSpawnProtect.Text.Trim()
            'player-idle-timeout' = $script:txtIdleTimeout.Text.Trim()
            'max-tick-time'    = $script:txtMaxTickTime.Text.Trim()
            'max-world-size'   = $script:txtMaxWorldSize.Text.Trim()
            'network-compression-threshold' = $script:txtNetCompress.Text.Trim()
            'op-permission-level' = $script:txtOpLevel.Text.Trim()
            'function-permission-level' = $script:txtFuncLevel.Text.Trim()
            'entity-broadcast-range-percentage' = $script:txtEntBroadcast.Text.Trim()
            'level-name'       = $script:txtLevelName.Text.Trim()
            'level-seed'       = $script:txtLevelSeed.Text.Trim()
            'level-type'       = $script:txtLevelType.Text.Trim()
            'allow-flight'     = if ($script:chkAllowFlight.Checked) { 'true' } else { 'false' }
            'spawn-animals'    = if ($script:chkSpawnAnimals.Checked) { 'true' } else { 'false' }
            'spawn-monsters'   = if ($script:chkSpawnMonsters.Checked) { 'true' } else { 'false' }
            'spawn-npcs'       = if ($script:chkSpawnNpcs.Checked) { 'true' } else { 'false' }
            'hardcore'         = if ($script:chkHardcore.Checked) { 'true' } else { 'false' }
            'generate-structures' = if ($script:chkGenStructures.Checked) { 'true' } else { 'false' }
            'allow-nether'     = if ($script:chkAllowNether.Checked) { 'true' } else { 'false' }
            'enforce-whitelist' = if ($script:chkEnforceWhitelist.Checked) { 'true' } else { 'false' }
            'enable-status'    = if ($script:chkEnableStatus.Checked) { 'true' } else { 'false' }
            'enable-query'     = if ($script:chkEnableQuery.Checked) { 'true' } else { 'false' }
            'sync-chunk-writes' = if ($script:chkSyncChunkWrites.Checked) { 'true' } else { 'false' }
            'hide-online-players' = if ($script:chkHideOnline.Checked) { 'true' } else { 'false' }
            'log-ips'          = if ($script:chkLogIps.Checked) { 'true' } else { 'false' }
            'broadcast-console-to-ops' = if ($script:chkBroadcastOps.Checked) { 'true' } else { 'false' }
        }
        Update-PropertyFile -FilePath (Join-Path $script:serverDir 'server.properties') -Changes $changes
        [System.Windows.Forms.MessageBox]::Show('配置已保存，重启服务器后生效。（端口请到"总览 / 启动"页修改）', '完成') | Out-Null
        Save-Settings
    })
    $btnEditProps.Add_Click({
        $p = Join-Path $script:serverDir 'server.properties'
        if (Test-Path -LiteralPath $p) { Start-Process notepad.exe -ArgumentList $p }
        else { [System.Windows.Forms.MessageBox]::Show('找不到 server.properties。', '提示') | Out-Null }
    })

    $btnAddPlayer.Add_Click({
        $name = $script:txtPlayer.Text.Trim()
        if (-not $name) {
            [System.Windows.Forms.MessageBox]::Show('请先输入玩家ID。', '加白名单', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }
        $result = Invoke-WhitelistAdd -Name $name
        $script:txtPlayer.Clear()
        Refresh-PlayerList
        if ($result) {
            [System.Windows.Forms.MessageBox]::Show($result, '加白名单', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show("已把 $name 加入白名单（服务器已确认）。", '加白名单') | Out-Null
        }
    })
    $btnRemovePlayer.Add_Click({
        $name = $script:txtPlayer.Text.Trim()
        if (-not $name) { $sel = $script:lstPlayers.SelectedItem; if ($sel) { $name = ($sel -replace ' \[OP\]\s*$', '') } }
        if (-not $name) {
            [System.Windows.Forms.MessageBox]::Show('请先选择或输入玩家ID。', '移除白名单', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }
        $result = Invoke-WhitelistRemove -Name $name
        $script:txtPlayer.Clear()
        Refresh-PlayerList
        if ($result) {
            [System.Windows.Forms.MessageBox]::Show($result, '移除白名单', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show("已完成：$name 已移出白名单（文件已改，指令已发，服务器处理中）。", '移除白名单') | Out-Null
        }
    })
    $btnOp.Add_Click({
        $name = $script:txtPlayer.Text.Trim()
        if (-not $name) { $sel = $script:lstPlayers.SelectedItem; if ($sel) { $name = ($sel -replace ' \[OP\]\s*$', '') } }
        if (-not $name) {
            [System.Windows.Forms.MessageBox]::Show('请先选择或输入玩家ID。', '设为 OP', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }
        $result = Invoke-OpChange -Name $name -MakeOp $true
        Refresh-PlayerList
        if ($result) {
            [System.Windows.Forms.MessageBox]::Show($result, '设为 OP', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show("已完成：$name 的 OP 已更新（文件已改，指令已发，服务器处理中）。", '设为 OP') | Out-Null
        }
    })
    $btnDeop.Add_Click({
        $name = $script:txtPlayer.Text.Trim()
        if (-not $name) { $sel = $script:lstPlayers.SelectedItem; if ($sel) { $name = ($sel -replace ' \[OP\]\s*$', '') } }
        if (-not $name) {
            [System.Windows.Forms.MessageBox]::Show('请先选择或输入玩家ID。', '取消 OP', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }
        $result = Invoke-OpChange -Name $name -MakeOp $false
        Refresh-PlayerList
        if ($result) {
            [System.Windows.Forms.MessageBox]::Show($result, '取消 OP', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show("已完成：$name 的管理员已取消（文件已改，指令已发，服务器处理中）。", '取消 OP') | Out-Null
        }
    })
    $btnRefreshPlayers.Add_Click({ Refresh-PlayerList })
    $script:lstPlayers.Add_SelectedIndexChanged({
        $sel = $script:lstPlayers.SelectedItem
        if ($sel) { $script:txtPlayer.Text = ($sel -replace ' \[OP\]\s*$', '') }
    })
    $btnEditWhitelist.Add_Click({
        $p = Join-Path $script:serverDir 'whitelist.json'
        if (Test-Path -LiteralPath $p) { Start-Process notepad.exe -ArgumentList $p }
        else { [System.Windows.Forms.MessageBox]::Show('找不到 whitelist.json。', '提示') | Out-Null }
    })
    $btnEditOps.Add_Click({
        $p = Join-Path $script:serverDir 'ops.json'
        if (Test-Path -LiteralPath $p) { Start-Process notepad.exe -ArgumentList $p }
        else { [System.Windows.Forms.MessageBox]::Show('找不到 ops.json。', '提示') | Out-Null }
    })

    $btnToggleMod.Add_Click({
        $idx = $script:lstMods.SelectedIndex
        if ($idx -lt 0 -or $idx -ge $script:modItems.Count) {
            [System.Windows.Forms.MessageBox]::Show('请先选择一个模组。', '提示') | Out-Null
            return
        }
        $item = $script:modItems[$idx]
        if ($item.Disabled) {
            $newName = $item.Name -replace '\.jar\.disabled$', '.jar'
            Rename-Item -LiteralPath $item.Path -NewName $newName
        } else {
            Rename-Item -LiteralPath $item.Path -NewName ($item.Name + '.disabled')
        }
        Refresh-ModList
    })
    $btnDeleteMod.Add_Click({
        $idx = $script:lstMods.SelectedIndex
        if ($idx -lt 0 -or $idx -ge $script:modItems.Count) { return }
        $item = $script:modItems[$idx]
        $r = [System.Windows.Forms.MessageBox]::Show('确定删除模组吗？' + "`r`n" + $item.Name, '确认删除', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
            Remove-Item -LiteralPath $item.Path -Force
            Refresh-ModList
        }
    })
    $btnRefreshMods.Add_Click({ Refresh-ModList })

    $btnBrowseFrpcExe.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = 'frpc.exe|frpc.exe'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:frpcExe = $dlg.FileName
            $script:txtFrpcExe.Text = $dlg.FileName
            Save-Settings
        }
    })
    $btnBrowseFrpcCfg.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = 'frpc 配置 (*.toml;*.ini)|*.toml;*.ini'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:frpcCfg = $dlg.FileName
            $script:txtFrpcCfg.Text = $dlg.FileName
            Save-Settings
        }
    })
    $script:txtFrpcExe.Add_TextChanged({ $script:frpcExe = $script:txtFrpcExe.Text })
    $script:txtFrpcCfg.Add_TextChanged({
        $script:frpcCfg = $script:txtFrpcCfg.Text
        if ($script:txtFrpPort) {
            $p = Get-FrpcPorts
            $script:txtFrpPort.Text = "$($p.FrpPort)"
            $script:txtVoicePort.Text = "$($p.VoicePort)"
        }
    })
    $btnFrpStart.Add_Click({ Start-Frpc })
    $btnFrpStop.Add_Click({ Stop-Frpc })
    $btnSavePorts.Add_Click({
        if (-not $script:serverDir) {
            [System.Windows.Forms.MessageBox]::Show('请先在总览页选择服务器目录。', '提示') | Out-Null
            return
        }
        $gamePort = 0
        $frpPort = 0
        $voicePort = 0
        try { $gamePort = [int]$script:txtGamePort.Text.Trim() } catch { }
        try { $frpPort = [int]$script:txtFrpPort.Text.Trim() } catch { }
        try { $voicePort = [int]$script:txtVoicePort.Text.Trim() } catch { }
        if ($gamePort -le 0 -or $gamePort -gt 65535 -or $frpPort -le 0 -or $frpPort -gt 65535 -or $voicePort -le 0 -or $voicePort -gt 65535) {
            [System.Windows.Forms.MessageBox]::Show('端口必须是 1~65535 的数字。', '提示') | Out-Null
            return
        }
        $msgs = @()
        # 游戏端口：server.properties + frpc.toml mc-tcp
        $oldGame = Get-ServerPort
        if ($gamePort -ne $oldGame) {
            Update-PropertyFile -FilePath (Join-Path $script:serverDir 'server.properties') -Changes @{ 'server-port' = "$gamePort" }
            if (Sync-FrpcGamePort -Port $gamePort) {
                $msgs += "游戏端口已改为 $gamePort（server.properties + frpc.toml 已同步）"
            } else {
                $msgs += "游戏端口已改为 $gamePort（未找到 frpc.toml，穿透未同步）"
            }
        }
        # frp 端口：frpc.toml serverPort
        $oldPorts = Get-FrpcPorts
        if ($frpPort -ne $oldPorts.FrpPort) {
            if (Update-FrpcServerPort -Port $frpPort) {
                $msgs += "frp 端口已改为 $frpPort（frpc.toml）"
            } else {
                $msgs += 'frp 端口修改失败（未找到 frpc.toml）'
            }
        }
        # 语音端口：frpc.toml mc-voice-udp + voicechat 配置
        if ($voicePort -ne $oldPorts.VoicePort) {
            $msgs += Update-VoicePort -Port $voicePort
        }
        if ($msgs.Count -eq 0) { $msgs += '端口没有变化' }
        $msgs += "注意：frp 端口需同步修改云服务器 /opt/frps/frps.toml 的 bindPort = $frpPort，并执行 systemctl restart frps，否则本地改了连不上。"
        $msgs += '语音端口改动后需重启服务器和穿透。'
        [System.Windows.Forms.MessageBox]::Show(($msgs -join "`r`n"), '端口配置', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        Save-Settings
    })
    $btnStartTunnel.Add_Click({
        Start-Frpc
        Update-TunnelView
    })
    $btnStopTunnel.Add_Click({
        Stop-Frpc
        Update-TunnelView
    })

    $btnSshScript.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = '脚本 (*.sh;*.ps1;*.bat)|*.sh;*.ps1;*.bat|所有文件 (*.*)|*.*'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:txtSshScript.Text = $dlg.FileName
        }
    })
    $script:txtSshIp.Add_TextChanged({ $script:sshIp = $script:txtSshIp.Text; Save-Settings })
    $script:txtSshUser.Add_TextChanged({ $script:sshUser = $script:txtSshUser.Text; Save-Settings })
    $script:txtSshScript.Add_TextChanged({ $script:sshScript = $script:txtSshScript.Text; Save-Settings })
    $script:txtSshRemote.Add_TextChanged({ $script:sshRemote = $script:txtSshRemote.Text; Save-Settings })
    $script:txtSshToken.Add_TextChanged({
        $script:sshToken = $script:txtSshToken.Text
        if ($script:txtFToken -and [string]::IsNullOrWhiteSpace($script:txtFToken.Text)) {
            $script:txtFToken.Text = $script:sshToken
        }
        Save-Settings
    })

    function Invoke-SshAction {
        param([bool]$Exec)
        $scp = Get-SshTool 'scp'
        $ssh = Get-SshTool 'ssh'
        $ip = $script:txtSshIp.Text.Trim()
        $user = $script:txtSshUser.Text.Trim()
        $scriptPath = $script:txtSshScript.Text.Trim()
        $remote = $script:txtSshRemote.Text.Trim()
        if (-not $remote) { $remote = '~/' }
        if (-not $scp) {
            [System.Windows.Forms.MessageBox]::Show('未找到 scp.exe（Windows OpenSSH），无法上传。', '错误') | Out-Null
            return
        }
        if (-not $ip -or -not $user) {
            [System.Windows.Forms.MessageBox]::Show('请填写服务器IP和用户名。', '提示') | Out-Null
            return
        }
        if (-not $scriptPath -or -not (Test-Path -LiteralPath $scriptPath)) {
            [System.Windows.Forms.MessageBox]::Show('请选择要上传的脚本文件。', '提示') | Out-Null
            return
        }
        if ($remote -notmatch '/$') { $remote += '/' }
        $target = "$user@$ip`:$remote"
        $cmdLine = '"' + $scp + '" "' + $scriptPath + '" "' + $target + '"'
        if ($Exec) {
            $name = Split-Path -Leaf $scriptPath
            $remotePath = $remote + $name
            $envPrefix = ''
            if ($script:sshToken) {
                $envPrefix = 'FRPS_TOKEN=' + $script:sshToken + ' '
            }
            $cmdLine += ' && "' + $ssh + '" "' + "$user@$ip" + '" "' + $envPrefix + 'sudo bash ' + $remotePath + '"'
        }
        $cmdLine += ' & pause'
        Start-Process cmd.exe -ArgumentList @('/c', $cmdLine)
    }
    $btnSshUpload.Add_Click({ Invoke-SshAction -Exec $false })
    $btnSshExec.Add_Click({ Invoke-SshAction -Exec $true })

    # 定时器：轮询日志和状态
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 400
    $timer.Add_Tick({
        Update-ConsoleView
        Update-FrpcView
        Update-TunnelView
        Update-StatusBar
    })
    $timer.Start()

    return $form
}

# ---------------- 主流程 ----------------
if ($SmokeTest) {
    return
}

Load-Settings
$form = New-MainForm

# 载入设置到控件
$script:txtServerDir.Text = $script:serverDir
$script:txtJava.Text = $script:javaPath
if (-not $script:javaInstallDir) { $script:javaInstallDir = Get-DefaultJavaInstallDir }
$script:txtFJavaInstallDir.Text = $script:javaInstallDir
$script:txtSshIp.Text = $script:sshIp
$script:txtSshUser.Text = $script:sshUser
$script:txtSshScript.Text = $script:sshScript
$script:txtSshRemote.Text = $script:sshRemote
$script:txtSshToken.Text = $script:sshToken
$script:numMem.Value = [Math]::Max(1, [Math]::Min(16, $script:maxMem))
$script:comboAuthMode.SelectedIndex = switch ($script:authMode) {
    'premium' { 0 }
    default   { 1 }
}
if ($script:authMode -eq 'premium') {
    $script:skinStation = '离线模式'
} else {
    $script:skinStation = Get-SkinStationNameFromUrl -Url $script:authUrl
}
if ($script:comboSkin.Items.Contains($script:skinStation)) { $script:comboSkin.SelectedItem = $script:skinStation }
$script:txtAuthUrl.Text = $script:authUrl
if ($script:comboSkin) { $script:comboSkin.Enabled = ($script:authMode -eq 'thirdparty') }
if ($script:txtAuthUrl) { $script:txtAuthUrl.Enabled = ($script:authMode -eq 'thirdparty' -and $script:skinStation -eq '自定义') }
$script:txtFrpcExe.Text = $script:frpcExe
$script:txtFrpcCfg.Text = $script:frpcCfg
$script:txtFZip.Text = $script:freshZip
$script:txtFDir.Text = $script:freshDir
$script:txtFIp.Text = $script:frpIp
if ($script:frpPort) { $script:txtFFrpPort.Text = $script:frpPort }
$script:txtFToken.Text = $script:frpToken
Ensure-FreshFrpTokenField
if ($script:gamePort) { $script:txtFGamePort.Text = $script:gamePort }
if ($script:voicePort) { $script:txtFVoicePort.Text = $script:voicePort }
$script:txtFMcVersion.Text = $script:freshMcVersion
Match-JavaForVersion
Match-JavaForServerDir
Auto-MatchFrpForServerDir
Refresh-ServerCombo
Load-QuickConfigFromServer
Update-TunnelView
if (-not $script:txtMaxPlayers.Text) { $script:txtMaxPlayers.Text = "$($script:maxPlayers)" }
$existingFrpc = @(Get-FrpcProcesses)
if ($existingFrpc.Count -gt 0 -and -not ($script:frpcProc -and -not $script:frpcProc.HasExited)) {
    $script:frpcProc = $existingFrpc[0]
}
Refresh-PlayerList
Refresh-ModList
Update-StatusBar

if ($UITest) {
    $form.Dispose()
    try {
        if ($AppDir) {
            Set-Content -LiteralPath (Join-Path $AppDir 'uitest-result.txt') -Value 'UITEST OK' -Encoding ASCII
        }
    } catch { }
    return
}

[void]$form.ShowDialog()
