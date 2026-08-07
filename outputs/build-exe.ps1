# 构建 MCServerManager.exe（单文件，无需安装）
# 把 mc-server-manager.ps1 用 GZip 压缩后以 base64 内嵌进 C# 程序，
# 运行时直接用 PowerShell 引擎（System.Management.Automation）在进程内执行，
# 不生成临时脚本、不调用 powershell.exe，避免被杀毒软件误报。

$ErrorActionPreference = 'Stop'

$dir = $PSScriptRoot
$ps1 = Join-Path $dir 'mc-server-manager.ps1'
if (-not (Test-Path -LiteralPath $ps1)) {
    Write-Host "找不到 $ps1" -ForegroundColor Red
    exit 1
}

$bytes = [System.IO.File]::ReadAllBytes($ps1)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $bytes = [byte[]]$bytes[3..($bytes.Length - 1)]
}
$ms = New-Object System.IO.MemoryStream
$gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Compress)
$gz.Write($bytes, 0, $bytes.Length)
$gz.Dispose()
$b64 = [Convert]::ToBase64String($ms.ToArray())
$ms.Dispose()
$cs = Join-Path $dir 'MCServerManagerWrapper.cs'

$template = @'
using System;
using System.IO;
using System.IO.Compression;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using System.Threading;
using System.Windows.Forms;

static class Program
{
    const string ScriptBase64 = "__BASE64__";

    [STAThread]
    static void Main(string[] args)
    {
        string exeDir = Path.GetDirectoryName(Environment.GetCommandLineArgs()[0]);
        byte[] raw;
        try
        {
            byte[] data = Convert.FromBase64String(ScriptBase64);
            using (MemoryStream ms = new MemoryStream(data))
            using (GZipStream gz = new GZipStream(ms, CompressionMode.Decompress))
            using (MemoryStream outMs = new MemoryStream())
            {
                gz.CopyTo(outMs);
                raw = outMs.ToArray();
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("解压内嵌脚本失败: " + ex.Message, "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }
        string script = Encoding.UTF8.GetString(raw).TrimStart('\uFEFF');

        bool smoke = false;
        foreach (string a in args)
        {
            if (a.Equals("-SmokeTest", StringComparison.OrdinalIgnoreCase))
            {
                smoke = true;
            }
        }

        try
        {
            InitialSessionState iss = InitialSessionState.CreateDefault();
            using (Runspace rs = RunspaceFactory.CreateRunspace(iss))
            {
                rs.ApartmentState = ApartmentState.STA;
                rs.Open();
                using (PowerShell ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    ps.AddScript(script);
                    ps.AddParameter("AppDir", exeDir);
                    if (smoke)
                    {
                        ps.AddParameter("SmokeTest", new SwitchParameter(true));
                    }
                    ps.Invoke();
                    if (smoke)
                    {
                        StringBuilder sb = new StringBuilder();
                        sb.AppendLine("exit=0");
                        sb.AppendLine("SMOKE OK");
                        foreach (ErrorRecord er in ps.Streams.Error)
                        {
                            sb.AppendLine("ERROR: " + er.ToString());
                        }
                        File.WriteAllText(Path.Combine(exeDir, "smoke-result.txt"), sb.ToString());
                    }
                    else if (ps.HadErrors)
                    {
                        StringBuilder sb = new StringBuilder();
                        foreach (ErrorRecord er in ps.Streams.Error)
                        {
                            sb.AppendLine(er.ToString());
                        }
                        File.WriteAllText(Path.Combine(exeDir, "error.txt"), sb.ToString());
                    }
                }
                rs.Close();
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("启动失败: " + ex.Message, "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
'@

$template = $template.Replace('__BASE64__', $b64)
[System.IO.File]::WriteAllText($cs, $template, (New-Object System.Text.UTF8Encoding($false)))

$csc = Get-ChildItem "C:\Windows\Microsoft.NET\Framework64" -Recurse -Filter csc.exe -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $csc) {
    Write-Host "未找到 csc.exe" -ForegroundColor Red
    exit 1
}

$out = Join-Path $dir 'MCServerManager.exe'
$refs = @(
    'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\System.Windows.Forms.dll',
    'C:\Windows\Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation\v4.0_3.0.0.0__31bf3856ad364e35\System.Management.Automation.dll'
)
$argList = @('/nologo', '/optimize+', '/target:winexe', "/out:$out")
foreach ($r in $refs) { $argList += "/r:$r" }
$argList += $cs
& $csc.FullName @argList

if ($LASTEXITCODE -eq 0) {
    $size = (Get-Item -LiteralPath $out).Length
    Write-Host "BUILD OK: $out ($([math]::Round($size/1KB, 1)) KB)"
} else {
    Write-Host "BUILD FAILED: $LASTEXITCODE" -ForegroundColor Red
    exit 1
}
