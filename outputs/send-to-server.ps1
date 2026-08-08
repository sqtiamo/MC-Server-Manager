# ============================================================
#  发送脚本到服务器（替代应用内按钮，直接在 PowerShell 窗口运行）
#  用法: powershell -ExecutionPolicy Bypass -File send-to-server.ps1
#  可选参数:
#    -Server  云服务器 IP（默认 1.15.171.18）
#    -User    SSH 用户名（默认 ubuntu）
#    -Script  要上传的脚本（默认本目录 install-frps.sh）
#    -Remote  远端目录（默认 ~/frps-install，自动创建）
#    -Token   frp 认证密码（默认 trainwolf2026）
#    -FrpVersion frp 版本号（默认 0.61.1）
#    -OpenPorts 只放行端口，如 "25565/tcp 24454/udp"（不上传不安装）
#    -AlsoOpenPorts 执行安装后顺便放行的端口，如 "25565/tcp 24454/udp"
#    -NoExec  只上传不执行
#  流程：本机先下载 frp 压缩包（已有则跳过）→ 上传脚本+压缩包 → 服务器解压安装
#  运行后按提示输入 SSH 密码即可（scp 两次、执行 sudo 可能再一次）
# ============================================================
param(
    [string]$Server = '1.15.171.18',
    [string]$User = 'ubuntu',
    [string]$Script = '',
    [string]$Remote = '~/frps-install',
    [string]$Token = 'trainwolf2026',
    [string]$FrpVersion = '0.61.1',
    [string]$OpenPorts = '',
    [string]$AlsoOpenPorts = '',
    [switch]$NoExec
)

$ErrorActionPreference = 'Stop'
if (-not $Script) { $Script = Join-Path $PSScriptRoot 'install-frps.sh' }

Write-Host "==> 检查 SSH 连通性 ($Server`:22) ..."
$r = Test-NetConnection -ComputerName $Server -Port 22 -WarningAction SilentlyContinue
if (-not $r.TcpTestSucceeded) {
    Write-Host "[错误] 连不上 $Server`:22，请检查：云服务器是否开机、安全组是否放行 22、IP 是否填对。" -ForegroundColor Red
    Read-Host "`n按回车退出"
    exit 1
}
Write-Host "[OK] SSH 端口可达" -ForegroundColor Green

if ($OpenPorts.Trim()) {
    $tokens = @($OpenPorts -split '[\s,，、;；]+' | Where-Object { $_ })
    $bad = @($tokens | Where-Object { $_ -notmatch '^\d{1,5}(/(tcp|udp))?$' })
    if ($bad.Count -gt 0) {
        Write-Host "[错误] 端口格式不对: $($bad -join ', ')。示例：25565/tcp 24454/udp" -ForegroundColor Red
        Read-Host "`n按回车退出"
        exit 1
    }
    $remoteCmd = ($tokens | ForEach-Object { "sudo ufw allow $_" }) -join ' && '
    Write-Host "==> 在服务器上放行端口: $($tokens -join ' ') ..."
    & ssh "$User@$Server" $remoteCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[错误] 放行端口失败（退出码 $LASTEXITCODE）" -ForegroundColor Red
        Read-Host "`n按回车退出"
        exit 1
    }
    Write-Host "[完成] 端口已在云服务器 ufw 放行；腾讯云安全组还需在控制台手动放行相同端口" -ForegroundColor Green
    Read-Host "`n按回车退出"
    exit 0
}

if (-not (Test-Path -LiteralPath $Script)) {
    Write-Host "[错误] 找不到脚本文件: $Script" -ForegroundColor Red
    Read-Host "`n按回车退出"
    exit 1
}
$name = Split-Path -Leaf $Script
$remote = $Remote.TrimEnd('/')

$uploadFiles = @($Script)
if (-not $NoExec) {
    # 本机先下载 frp 压缩包（已存在则跳过），避免在服务器上直连 GitHub 下载失败
    $zipName = "frp_${FrpVersion}_linux_amd64.tar.gz"
    $zipPath = Join-Path $PSScriptRoot $zipName
    if (Test-Path -LiteralPath $zipPath) {
        Write-Host "==> 使用本地已下载的 $zipName"
    } else {
        Write-Host "==> 本机下载 $zipName ..."
        $urls = @(
            "https://github.com/fatedier/frp/releases/download/v${FrpVersion}/frp_${FrpVersion}_linux_amd64.tar.gz",
            "https://ghfast.top/https://github.com/fatedier/frp/releases/download/v${FrpVersion}/frp_${FrpVersion}_linux_amd64.tar.gz",
            "https://gh-proxy.com/https://github.com/fatedier/frp/releases/download/v${FrpVersion}/frp_${FrpVersion}_linux_amd64.tar.gz",
            "https://ghproxy.net/https://github.com/fatedier/frp/releases/download/v${FrpVersion}/frp_${FrpVersion}_linux_amd64.tar.gz"
        )
        $downloaded = $false
        foreach ($u in $urls) {
            Write-Host "  尝试: $u"
            try {
                if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
                    & curl.exe -L --fail --progress-bar -o $zipPath $u
                    if ($LASTEXITCODE -eq 0) { $downloaded = $true; break }
                } else {
                    Invoke-WebRequest -Uri $u -OutFile $zipPath -UseBasicParsing
                    $downloaded = $true
                    break
                }
            } catch { }
        }
        if (-not $downloaded) {
            Write-Host "[错误] frp 压缩包下载失败，请手动下载后放到: $zipPath" -ForegroundColor Red
            Read-Host "`n按回车退出"
            exit 1
        }
        if ((Get-Item -LiteralPath $zipPath).Length -lt 10MB) {
            Write-Host "[错误] 下载的文件不完整（小于 10MB），请删除 $zipPath 后重试" -ForegroundColor Red
            Read-Host "`n按回车退出"
            exit 1
        }
    }
    $uploadFiles += $zipPath
}

Write-Host "==> 上传到 $User@$Server 主目录 ..."
foreach ($f in $uploadFiles) {
    Write-Host "  $f"
}
& scp $uploadFiles "$User@$Server`:~/"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[错误] scp 上传失败（退出码 $LASTEXITCODE）" -ForegroundColor Red
    Read-Host "`n按回车退出"
    exit 1
}
if (-not $NoExec) {
    $remoteCmd = "mkdir -p $remote && mv -f ~/$name $remote/ && mv -f ~/$zipName $remote/ && FRPS_TOKEN=$Token sudo bash $remote/$name"
} else {
    $remoteCmd = "mkdir -p $remote && mv -f ~/$name $remote/"
}
if ($AlsoOpenPorts.Trim() -and -not $NoExec) {
    $tokens = @($AlsoOpenPorts -split '[\s,，、;；]+' | Where-Object { $_ })
    foreach ($t in $tokens) { $remoteCmd += ' && sudo ufw allow ' + $t }
}

Write-Host "==> 在服务器上执行 $name ..."
& ssh "$User@$Server" $remoteCmd
if ($LASTEXITCODE -ne 0) {
    Write-Host "[错误] 远程执行失败（退出码 $LASTEXITCODE）" -ForegroundColor Red
    Read-Host "`n按回车退出"
    exit 1
}
if ($NoExec) {
    Write-Host "[完成] 已上传到 $User@$Server`:~/（未执行）" -ForegroundColor Green
} else {
    Write-Host "[完成] 执行完成，frps 已安装并开机自启" -ForegroundColor Green
}

Read-Host "`n按回车退出"
exit 0

# 旧实现保留参考（已不再使用）
<#
& scp "$Script" "$User@$Server`:~/"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[错误] scp 上传失败（退出码 $LASTEXITCODE）" -ForegroundColor Red
    Read-Host "`n按回车退出"
    exit 1
}

if ($NoExec) {
    Write-Host "[完成] 已上传到 $User@$Server`:~/（未执行）" -ForegroundColor Green
} else {
    $remoteCmd = "mkdir -p $remote && mv -f ~/$name $remote/ && FRPS_TOKEN=$Token sudo bash $remote/$name"
    Write-Host "==> 在服务器上执行 $name ..."
    & ssh "$User@$Server" $remoteCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[错误] 远程执行失败（退出码 $LASTEXITCODE）" -ForegroundColor Red
        Read-Host "`n按回车退出"
        exit 1
    }
    Write-Host "[完成] 执行完成，frps 已安装并开机自启" -ForegroundColor Green
}

Read-Host "`n按回车退出"
#>
