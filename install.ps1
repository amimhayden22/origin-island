# Pasang Origin Island untuk Claude Code yang berjalan langsung di Windows (tanpa WSL).
# Dari repo   : powershell -ExecutionPolicy Bypass -File .\install.ps1
# Tanpa Git   : irm https://raw.githubusercontent.com/amimhayden22/origin-island/main/install.ps1 | iex
$ErrorActionPreference = 'Stop'
$Ref = if ($env:ORIGIN_ISLAND_REF) { $env:ORIGIN_ISLAND_REF } else { 'main' }
$Utf8 = New-Object Text.UTF8Encoding $false

function Test-WslCommand($name) {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $false }
    try { $null = wsl.exe -e bash -lc "command -v $name" 2>$null; $LASTEXITCODE -eq 0 } catch { $false }
}

# Dijalankan lewat "irm | iex": belum ada salinan repo, jadi unduh dulu.
$Here = $PSScriptRoot
$download = $null
if (-not $Here -or -not (Test-Path (Join-Path $Here 'windows\island.ps1'))) {
    Write-Host '==> Mengunduh Origin Island'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $download = Join-Path $env:TEMP "origin-island-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $download | Out-Null
    $zip = Join-Path $download 'repo.zip'
    Invoke-WebRequest -UseBasicParsing "https://codeload.github.com/amimhayden22/origin-island/zip/$Ref" -OutFile $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $download
    $Here = (Get-ChildItem -LiteralPath $download -Directory | Select-Object -First 1).FullName
}

try {
    $hasClaude = [bool](Get-Command claude -ErrorAction SilentlyContinue) -or (Test-Path "$env:USERPROFILE\.local\bin\claude.exe")
    $claudeInWsl = Test-WslCommand 'claude'

    # Pilihan 1 = hanya sesi Windows; pilihan 2 = sesi Windows dan WSL, dalam satu pil.
    $default = if (-not $hasClaude -and $claudeInWsl) { '2' } else { '1' }
    $choice = switch ($env:ORIGIN_ISLAND_TARGET) { 'windows' { '1' } 'wsl' { '2' } default { $null } }
    if (-not $choice -and [Console]::IsInputRedirected) { $choice = $default }   # mis. dijalankan oleh Claude Code
    while (-not $choice) {
        Write-Host ''
        Write-Host 'Pasang Origin Island untuk:'
        Write-Host '  [1] Windows (direkomendasikan)'
        Write-Host '  [2] Windows + WSL (biasanya untuk programmer)'
        if ($default -eq '2') { Write-Host 'Claude Code terdeteksi di WSL, jadi pilihan 2 yang disarankan.' -ForegroundColor Yellow }
        $answer = (Read-Host "Pilih [$default]").Trim()
        if (-not $answer) { $answer = $default }
        if ($answer -in '1', '2') { $choice = $answer } else { Write-Host 'Ketik 1 atau 2.' -ForegroundColor Yellow }
    }
    if ($choice -eq '2' -and -not (Test-WslCommand 'python3')) {
        Write-Host 'WSL atau python3 di dalamnya tidak ditemukan, jadi hanya versi Windows yang dipasang.' -ForegroundColor Yellow
        $choice = '1'
    }
    if ($choice -eq '1' -and -not $hasClaude) {
        Write-Host '! Claude Code belum terdeteksi di Windows. Hook tetap dipasang dan aktif setelah Claude Code terpasang.' -ForegroundColor Yellow
    }

    $App = Join-Path $env:LOCALAPPDATA 'OriginIsland'
    $HookDir = Join-Path $App 'hooks'
    $ClaudeDir = Join-Path $env:USERPROFILE '.claude'
    $Settings = Join-Path $ClaudeDir 'settings.json'

    Write-Host '==> Menghentikan Origin Island yang sedang berjalan (bila ada)'
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like "*$App\island.ps1*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath (Join-Path $App 'alive') -ErrorAction SilentlyContinue

    Write-Host "==> Menyalin aplikasi ke $App"
    New-Item -ItemType Directory -Force -Path $App, $HookDir, (Join-Path $App 'icons'), (Join-Path $App 'sounds') | Out-Null
    # PowerShell 5.1 butuh BOM agar membaca file sebagai UTF-8.
    [IO.File]::WriteAllText((Join-Path $App 'island.ps1'), [IO.File]::ReadAllText((Join-Path $Here 'windows\island.ps1')), (New-Object Text.UTF8Encoding $true))
    Copy-Item (Join-Path $Here 'uninstall.ps1') $App -Force
    Copy-Item (Join-Path $Here 'windows\island_hook.ps1'), (Join-Path $Here 'windows\island_statusline.ps1') $HookDir -Force
    Copy-Item (Join-Path $Here 'icons\*.svg'), (Join-Path $Here 'icons\*.json') (Join-Path $App 'icons') -Force
    Copy-Item (Join-Path $Here 'sounds\*.mp3') (Join-Path $App 'sounds') -Force

    # config.json: preferensi dipertahankan, termasuk data versi WSL bila keduanya dipasang.
    $cfgPath = Join-Path $App 'config.json'
    $cfg = [ordered]@{ pollSeconds = 300; notifySeconds = 8; sound = $true; hideOnFullscreen = $true; usageApiFallback = $false }
    if (Test-Path -LiteralPath $cfgPath) {
        $old = Get-Content -Raw -LiteralPath $cfgPath | ConvertFrom-Json
        foreach ($p in $old.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
    }
    if (-not $cfg['credentialsPath']) { $cfg['credentialsPath'] = Join-Path $ClaudeDir '.credentials.json' }
    $cfg['eventsPath'] = Join-Path $App 'events.jsonl'
    $cfg['exitWhenWslStops'] = $false      # Claude Code di Windows tidak bergantung pada WSL
    $cfg['nativeInstall'] = $true          # dipakai tombol Uninstall
    [IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json), $Utf8)

    $vbs = "Set sh = CreateObject(`"WScript.Shell`")`r`nsh.Run `"powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"`"$App\island.ps1`"`"`", 0, False`r`n"
    [IO.File]::WriteAllText((Join-Path $App 'start-island.vbs'), $vbs, $Utf8)

    Write-Host "==> Memasang hook + statusline Claude Code di $Settings"
    New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null
    $s = [pscustomobject]@{}
    if (Test-Path -LiteralPath $Settings) {
        $s = Get-Content -Raw -LiteralPath $Settings | ConvertFrom-Json
        Copy-Item -LiteralPath $Settings "$Settings.bak-island" -Force
    }
    if (-not $s.hooks) { $s | Add-Member hooks ([pscustomobject]@{}) -Force }
    $ps = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File'
    $hookCmd = "$ps `"$HookDir\island_hook.ps1`" -Out `"$App\events.jsonl`""
    # Event alat sering sekali: async supaya Claude tidak menunggu PowerShell menyala tiap memakai alat.
    $asyncEvents = 'PreToolUse', 'PostToolUse', 'PostToolUseFailure'
    foreach ($ev in 'SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'Notification', 'Stop', 'StopFailure', 'SessionEnd') {
        $groups = @($s.hooks.$ev | Where-Object { $_ -and -not ($_.hooks | Where-Object { $_.command -like '*island_hook*' }) })
        $h = [ordered]@{ type = 'command'; command = $hookCmd; timeout = 10 }
        if ($ev -in $asyncEvents) { $h.async = $true }
        $groups += [pscustomobject]@{ hooks = @([pscustomobject]$h) }
        $s.hooks | Add-Member $ev $groups -Force
    }
    if ($s.statusLine -and $s.statusLine.command -notlike '*island_statusline*') {
        Write-Host '   ! statusLine sudah dipakai skrip lain, tidak diubah. Kuota tidak tampil.' -ForegroundColor Yellow
    }
    else {
        $s | Add-Member statusLine ([pscustomobject]@{ type = 'command'; command = "$ps `"$HookDir\island_statusline.ps1`" -Out `"$App\usage.json`"" }) -Force
    }
    [IO.File]::WriteAllText($Settings, ($s | ConvertTo-Json -Depth 20), $Utf8)

    Write-Host '==> Menjalankan Origin Island'
    Start-Process -FilePath 'wscript.exe' -ArgumentList "`"$App\start-island.vbs`""

    if ($choice -eq '2') {
        Write-Host '==> Memasang untuk WSL'
        $wslHere = (wsl.exe -e wslpath -a $Here | Out-String).Trim()
        & wsl.exe -e bash "$wslHere/install.sh"
        if ($LASTEXITCODE -ne 0) { Write-Host '! Pemasangan untuk WSL gagal. Versi Windows tetap terpasang.' -ForegroundColor Yellow }
    }

    Write-Host ''
    Write-Host 'Selesai. Origin Island menyala saat Claude Code dipakai.' -ForegroundColor Green
    Write-Host 'Buka ulang sesi Claude Code yang sedang berjalan supaya kuota ikut diperbarui.'
}
finally {
    if ($download) { Remove-Item -LiteralPath $download -Recurse -Force -ErrorAction SilentlyContinue }
}
