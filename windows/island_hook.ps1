# Claude Code hook -> Origin Island, untuk Claude Code yang berjalan langsung di Windows.
# Padanan wsl/island_hook.py. Tidak boleh mencetak apa pun ke stdout (output UserPromptSubmit
# masuk ke konteks Claude) dan tidak boleh mengganggu Claude Code bila gagal.
param([Parameter(Mandatory)][string]$Out)
$ErrorActionPreference = 'Stop'
$MaxFile = 256 * 1024
$MaxMsg = 240

function Clean($text) {
    $t = [regex]::Replace([string]$text, '```.*?```', ' [kode] ', 'Singleline')
    $t = [regex]::Replace($t, '[`*#>|]+', '')
    $t = ([regex]::Replace($t, '\s+', ' ')).Trim()
    if ($t.Length -gt $MaxMsg) { $t.Substring(0, $MaxMsg) + [char]0x2026 } else { $t }
}

function Terminal-Kind {
    if ($env:TERM_PROGRAM -eq 'vscode') { return 'vscode' }
    if ($env:WT_SESSION) { return 'wt' }
    'console'
}

# File status sesi (idle/busy/waiting) milik session_id ini.
function Status-File($sessionId) {
    $dir = Join-Path $env:USERPROFILE '.claude\sessions'
    if ($env:CLAUDE_PID) {
        $p = Join-Path $dir "$env:CLAUDE_PID.json"
        if ([IO.File]::Exists($p)) { return $p }
    }
    foreach ($f in [IO.Directory]::GetFiles($dir, '*.json')) {
        if ([IO.File]::ReadAllText($f).Contains($sessionId)) { return $f }
    }
    ''
}

function Append-Line($path, $line) {
    $mode = if ([IO.File]::Exists($path) -and (New-Object IO.FileInfo $path).Length -gt $MaxFile) { 'Create' } else { 'Append' }
    $bytes = (New-Object Text.UTF8Encoding $false).GetBytes($line + "`n")
    # Beberapa sesi bisa menulis bersamaan.
    foreach ($i in 1..8) {
        try {
            $fs = [IO.File]::Open($path, $mode, 'Write', 'ReadWrite')
            try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
            return
        }
        catch [IO.IOException] { Start-Sleep -Milliseconds 25 }
    }
}

try {
    [Console]::InputEncoding = [Text.Encoding]::UTF8
    $data = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $event = [string]$data.hook_event_name
    $cwd = ([string]$data.cwd).TrimEnd('\', '/')
    $rec = [ordered]@{
        ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000
        event = $event
        session = [string]$data.session_id
        project = $(if ($cwd) { Split-Path $cwd -Leaf } else { 'claude' })
        cwd = $cwd
        distro = ''
        term = Terminal-Kind
        transcript = [string]$data.transcript_path
    }
    try { $rec.statusFile = Status-File $rec.session } catch { $rec.statusFile = '' }
    switch ($event) {
        'Stop' { $rec.message = Clean $data.last_assistant_message }
        'Notification' { $rec.message = Clean $data.message; $rec.type = [string]$data.notification_type }
        'UserPromptSubmit' { $rec.message = Clean $data.prompt }
        'StopFailure' {
            $err = if ($data.error) { $data.error } elseif ($data.message) { $data.message } else { $data.reason }
            $rec.message = Clean $(if ($err -is [string]) { $err } elseif ($err) { $err | ConvertTo-Json -Compress } else { '' })
        }
        { $_ -in 'PreToolUse', 'PostToolUseFailure' } { $rec.tool = [string]$data.tool_name }
    }
    Append-Line $Out ($rec | ConvertTo-Json -Compress)

    if ($event -in 'SessionStart', 'UserPromptSubmit') {
        # Nyalakan island bila belum berjalan; island menulis file 'alive' tiap 3 detik.
        $app = Split-Path $Out
        $alive = Join-Path $app 'alive'
        $fresh = [IO.File]::Exists($alive) -and ([datetime]::UtcNow - [IO.File]::GetLastWriteTimeUtc($alive)).TotalSeconds -lt 15
        if (-not $fresh) { Start-Process -FilePath 'wscript.exe' -ArgumentList "`"$(Join-Path $app 'start-island.vbs')`"" -WindowStyle Hidden }
    }
}
catch {}
exit 0
