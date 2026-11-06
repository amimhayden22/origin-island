# Hapus Origin Island dari Windows: hook & statusline Claude Code, lalu file aplikasi.
# -HooksOnly: hanya melepas hook Windows (dipanggil uninstaller versi WSL).
param([switch]$HooksOnly)
$ErrorActionPreference = 'Continue'
$App = Join-Path $env:LOCALAPPDATA 'OriginIsland'
$Settings = Join-Path $env:USERPROFILE '.claude\settings.json'

Write-Host '==> Melepas hook & statusline Windows'
if (Test-Path -LiteralPath $Settings) {
    $s = Get-Content -Raw -LiteralPath $Settings | ConvertFrom-Json
    if ($s.hooks) {
        foreach ($p in @($s.hooks.PSObject.Properties)) {
            $keep = @($p.Value | Where-Object { -not ($_.hooks | Where-Object { $_.command -like '*island_hook*' }) })
            if ($keep.Count) { $s.hooks | Add-Member $p.Name $keep -Force } else { $s.hooks.PSObject.Properties.Remove($p.Name) }
        }
        if (-not @($s.hooks.PSObject.Properties).Count) { $s.PSObject.Properties.Remove('hooks') }
    }
    if ($s.statusLine -and $s.statusLine.command -like '*island_statusline*') { $s.PSObject.Properties.Remove('statusLine') }
    [IO.File]::WriteAllText($Settings, ($s | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))
}
if ($HooksOnly) { return }

Write-Host '==> Menghentikan Origin Island'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$App\island.ps1*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# Versi WSL ikut terpasang: biarkan uninstaller-nya melepas hook WSL.
$cfgPath = Join-Path $App 'config.json'
$cfg = if (Test-Path -LiteralPath $cfgPath) { Get-Content -Raw -LiteralPath $cfgPath | ConvertFrom-Json }
if ($cfg -and $cfg.distro -and $cfg.hookDir) {
    Write-Host "==> Melepas versi WSL ($($cfg.distro))"
    & wsl.exe -d $cfg.distro -e bash "$($cfg.hookDir)/island_uninstall.sh"
}

Set-Location $env:TEMP   # jangan berada di folder yang akan dihapus
Remove-Item -LiteralPath $App -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'Origin Island sudah dihapus.'
