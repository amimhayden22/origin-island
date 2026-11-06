#!/usr/bin/env bash
# Hapus Origin Island sepenuhnya: hook & statusline di ~/.claude/settings.json, blok ~/.bashrc,
# aplikasi Windows, dan skrip di ~/.claude/island.
# Dipanggil oleh ./uninstall.sh (repo) atau tombol "Uninstall" di island (lewat wsl.exe).
# Pemakaian: island_uninstall.sh [folder aplikasi versi WSL]   (default: %LOCALAPPDATA%/OriginIsland)
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
win_env() { cmd.exe /c "echo %$1%" 2>/dev/null | tr -d '\r'; }
LOCAL_WSL="$(wslpath "$(win_env LOCALAPPDATA)")"
APP_WSL="${1:-$LOCAL_WSL/OriginIsland}"
APP_WIN="$(wslpath -w "$APP_WSL")"
STARTUP_WSL="$(wslpath "$(win_env APPDATA)")/Microsoft/Windows/Start Menu/Programs/Startup"
HOOK_DIR="$HOME/.claude/island"

echo "==> Menghentikan island di $APP_WIN"
# Hanya proses yang menjalankan island.ps1 dari folder ini (bukan semua proses PowerShell).
patterns="'*$APP_WIN\\island.ps1*'"
[[ $# -eq 0 ]] && patterns="$patterns, '*ClaudeIsland\\island.ps1*'"   # sisa versi lama
powershell.exe -NoProfile -Command "\$p = @($patterns); Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { \$c = \$_.CommandLine; \$p | Where-Object { \$c -like \$_ } } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" || true
cd /   # jangan berada di folder yang akan dihapus

# Versi Windows ikut terpasang: lepas hook-nya dulu, karena skripnya akan ikut terhapus.
if [[ -f "$APP_WSL/uninstall.ps1" ]]; then
  echo "==> Melepas hook Windows"
  (cd /mnt/c && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$APP_WIN\\uninstall.ps1" -HooksOnly) || echo "   (gagal, lewati)"
fi

echo "==> Menghapus hook & statusline dari ~/.claude/settings.json"
python3 "$HERE/settings_hooks.py" uninstall || echo "   (gagal, lewati)"

echo "==> Menghapus blok autostart dari ~/.bashrc"
[[ -f "$HOME/.bashrc" ]] && sed -i '/# >>> claude-island >>>/,/# <<< claude-island <<</d; /# >>> origin-island >>>/,/# <<< origin-island <<</d' "$HOME/.bashrc"

echo "==> Menghapus file aplikasi"
rm -f "$STARTUP_WSL/ClaudeIsland.vbs"
rm -rf "$APP_WSL"
[[ $# -eq 0 ]] && rm -rf "$LOCAL_WSL/ClaudeIsland"
rm -rf "$HOOK_DIR"

echo "Origin Island sudah dihapus."
