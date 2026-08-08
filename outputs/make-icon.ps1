# ============================================================
#  生成应用图标 icon.ico（16/32/48/256 多尺寸）
#  源图: 本目录 app-icon.png（把想要的图标图片命名为 app-icon.png 放进来）
#  用法: powershell -ExecutionPolicy Bypass -File make-icon.ps1
#  生成的文件: 本目录 icon.ico（构建 exe 时自动使用）
# ============================================================
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$src = Join-Path $PSScriptRoot 'app-icon.png'
if (-not (Test-Path -LiteralPath $src)) {
    Write-Host "[错误] 找不到源图: $src（请把图标图片命名为 app-icon.png 放到本目录）" -ForegroundColor Red
    exit 1
}

$out = Join-Path $PSScriptRoot 'icon.ico'
$sizes = @(16, 32, 48, 256)
$pngs = New-Object System.Collections.Generic.List[byte[]]

$source = [System.Drawing.Image]::FromFile($src)
try {
    foreach ($sz in $sizes) {
        $bmp = New-Object System.Drawing.Bitmap($sz, $sz, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.DrawImage($source, 0, 0, $sz, $sz)

        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngs.Add($ms.ToArray())
        $ms.Dispose()
        $g.Dispose()
        $bmp.Dispose()
    }
} finally {
    $source.Dispose()
}

$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([UInt16]0)                # reserved
$bw.Write([UInt16]1)                # type: icon
$bw.Write([UInt16]$sizes.Count)     # image count
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $sz = $sizes[$i]
    $data = $pngs[$i]
    $dim = if ($sz -ge 256) { 0 } else { $sz }
    $bw.Write([byte]$dim)
    $bw.Write([byte]$dim)
    $bw.Write([byte]0)              # colors
    $bw.Write([byte]0)              # reserved
    $bw.Write([UInt16]1)            # planes
    $bw.Write([UInt16]32)           # bit count
    $bw.Write([UInt32]$data.Length)
    $bw.Write([UInt32]$offset)
    $offset += $data.Length
}
foreach ($data in $pngs) { $bw.Write($data) }
$bw.Flush()
[System.IO.File]::WriteAllBytes($out, $ms.ToArray())
$bw.Dispose()
$ms.Dispose()

Write-Host "图标已生成: $out ($((Get-Item -LiteralPath $out).Length) 字节)"
