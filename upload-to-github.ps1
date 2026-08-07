# ============================================================
#  一键上传 MC Server Manager 到 GitHub
#  用法: powershell -ExecutionPolicy Bypass -File upload-to-github.ps1
#  可选参数:
#    -RepoName  仓库名（默认 MC-Server-Manager）
#    -GitHubUser GitHub 用户名（默认 sqtiamo）
#  首次执行会弹出 GitHub 登录窗口（Windows 凭据管理器），登录一次即可。
# ============================================================
param(
    [string]$RepoName = 'MC-Server-Manager',
    [string]$GitHubUser = 'sqtiamo'
)

$ErrorActionPreference = 'Continue'
$repoRoot = $PSScriptRoot
Set-Location -LiteralPath $repoRoot

Write-Host '========== 1/5 准备 Git 仓库 =========='
git config --global --add safe.directory $repoRoot 2>$null
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
    git init 2>$null
    Write-Host '  已初始化 Git 仓库'
} else {
    Write-Host '  仓库已存在，跳过初始化'
}

if (-not (git config user.name)) { git config user.name $GitHubUser }
if (-not (git config user.email)) { git config user.email "$GitHubUser@users.noreply.github.com" }

Write-Host '========== 2/5 添加文件 =========='
$files = @(
    'README.md',
    '.gitignore',
    'upload-to-github.ps1',
    'outputs/mc-server-manager.ps1',
    'outputs/MCServerManagerWrapper.cs',
    'outputs/build-exe.ps1',
    'outputs/install-frps.sh',
    'outputs/deploy-train-werewolf.sh',
    'outputs/setup-local.ps1',
    'outputs/setup-spark.ps1',
    'outputs/apply-server-changes.ps1',
    'outputs/rcon.py',
    'outputs/部署说明.md',
    'outputs/start-manager.bat'
)
git add @($files) 2>$null
Write-Host '  已添加项目文件（服务器压缩包、exe、设置文件等已被排除）'

Write-Host '========== 3/5 提交 =========='
$staged = git diff --cached --name-only
if ($staged) {
    git commit -m "MC Server Manager: 一键部署/启动/管理 Minecraft 服务器（多服务器档案、官方/第三方登录、frp 穿透）" 2>$null
    Write-Host '  已提交'
} else {
    Write-Host '  没有新改动，跳过提交'
}

git branch -M main

Write-Host '========== 4/5 配置远程 =========='
$remoteUrl = "https://github.com/$GitHubUser/$RepoName.git"
$existing = git remote get-url origin 2>$null
if (-not $existing) {
    git remote add origin $remoteUrl 2>$null
    Write-Host "  已添加远程: $remoteUrl"
} elseif ($existing.Trim() -ne $remoteUrl) {
    git remote set-url origin $remoteUrl
    Write-Host "  远程地址已更新为: $remoteUrl（原来是 $existing）"
} else {
    Write-Host "  远程已存在: $existing"
}

Write-Host '========== 5/5 推送到 GitHub =========='
Write-Host "  目标仓库: $remoteUrl"
Write-Host '  如果弹出登录窗口，请用 GitHub 账号登录'
Write-Host "  如果提示仓库不存在，请先到 https://github.com/new 创建（名称: $RepoName）再重试"
git push -u origin main

Write-Host ''
Write-Host "完成！仓库地址: https://github.com/$GitHubUser/$RepoName"
Write-Host '下次修改后重新运行本脚本即可增量更新。'
pause
