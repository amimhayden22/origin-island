#!/usr/bin/env bash
# Hapus Origin Island beserta hook, statusline, dan baris di ~/.bashrc
# (termasuk sisa versi lama bernama ClaudeIsland).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
win_env() { cmd.exe /c "echo %$1%" 2>/dev/null | tr -d '\r'; }
LOCAL_WSL="$(wslpath "$(win_env LOCALAPPDATA)")"
STARTUP_WSL="$(wslpath "$(win_env APPDATA)")/Microsoft/Windows/Start Menu/Programs/Startup"

powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { \$_.CommandLine -like '*Island*island.ps1*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" || true
python3 "$HERE/wsl/settings_hooks.py" uninstall
sed -i '/# >>> claude-island >>>/,/# <<< claude-island <<</d; /# >>> origin-island >>>/,/# <<< origin-island <<</d' "$HOME/.bashrc"
rm -f "$STARTUP_WSL/ClaudeIsland.vbs"
rm -rf "$LOCAL_WSL/OriginIsland" "$LOCAL_WSL/ClaudeIsland" "$HOME/.claude/island"
echo "Origin Island sudah dihapus."
