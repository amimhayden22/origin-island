# Statusline Claude Code -> Origin Island, untuk Claude Code yang berjalan langsung di Windows.
# Padanan wsl/island_statusline.py: menyimpan rate_limits ke usage.json dan mencetak satu baris
# "<model> - 5j 31% - 7h 32%".
param([Parameter(Mandatory)][string]$Out)
$Windows = 'five_hour', 'seven_day', 'seven_day_opus', 'seven_day_sonnet'
$ResetTolerance = 60   # detik; waktu reset dari server bisa sedikit bergeser

function To-Iso($v) {
    if ($v -is [string] -or $null -eq $v) { return $v }
    $n = [double]$v
    if ($n -gt 1e12) { $n /= 1000 }
    [DateTimeOffset]::FromUnixTimeSeconds([long]$n).ToString("yyyy-MM-dd'T'HH:mm:sszzz")
}
function Reset-Epoch($w) {
    try { [DateTimeOffset]::Parse([string]$w.resets_at).ToUnixTimeSeconds() } catch { $null }
}

try {
    [Console]::InputEncoding = [Text.Encoding]::UTF8
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
    $data = [Console]::In.ReadToEnd() | ConvertFrom-Json

    $usage = [ordered]@{}
    foreach ($k in $Windows) {
        $w = $data.rate_limits.$k
        if (-not $w) { continue }
        $pct = if ($null -ne $w.used_percentage) { $w.used_percentage } else { $w.utilization }
        if ($null -eq $pct) { continue }
        $usage[$k] = [pscustomobject]@{ utilization = [double]$pct; resets_at = To-Iso $w.resets_at }
    }

    if ($usage.Count) {
        $last = $null
        try { $last = [IO.File]::ReadAllText($Out) | ConvertFrom-Json } catch {}
        # Tiap sesi hanya tahu kuota dari request terakhirnya: dalam satu jendela reset angkanya hanya
        # naik, dan jendela yang lebih lama diabaikan (sama dengan versi WSL).
        foreach ($k in $Windows) {
            $old = if ($last) { $last.$k } else { $null }
            if (-not $old) { continue }
            if (-not $usage.Contains($k)) { $usage[$k] = $old; continue }
            $newR = Reset-Epoch $usage[$k]; $oldR = Reset-Epoch $old
            if ($null -eq $newR -or $null -eq $oldR) { continue }
            if ($newR -lt $oldR - $ResetTolerance) { $usage[$k] = $old }
            elseif ([math]::Abs($newR - $oldR) -le $ResetTolerance -and [double]$old.utilization -gt $usage[$k].utilization) { $usage[$k] = $old }
        }
        $sig = { param($o) ($Windows | ForEach-Object { $w = $o.$_; if ($w) { "$_=$($w.utilization)@$($w.resets_at)" } }) -join ';' }
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000
        $same = $last -and (& $sig ([pscustomobject]$usage)) -eq (& $sig $last)
        if (-not $same -or -not $last.ts -or ($now - [double]$last.ts) -ge 300) {
            $rec = [ordered]@{}
            foreach ($k in $usage.Keys) { $rec[$k] = $usage[$k] }
            $rec.source = 'statusline'; $rec.ts = $now
            $tmp = "$Out.$PID.tmp"
            [IO.File]::WriteAllText($tmp, ($rec | ConvertTo-Json -Compress -Depth 4), (New-Object Text.UTF8Encoding $false))
            Move-Item -LiteralPath $tmp -Destination $Out -Force
        }
    }

    $parts = @()
    if ($data.model.display_name) { $parts += [string]$data.model.display_name }
    if ($usage.Contains('five_hour')) { $parts += '5j {0:0}%' -f $usage['five_hour'].utilization }
    if ($usage.Contains('seven_day')) { $parts += '7h {0:0}%' -f $usage['seven_day'].utilization }
    $parts -join " $([char]0xB7) "
}
catch { '' }
exit 0
