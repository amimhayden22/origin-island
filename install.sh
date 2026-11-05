#!/usr/bin/env bash
# Pasang Origin Island: aplikasi Windows + hook Claude Code di WSL.
# Island hanya berjalan selama WSL hidup: dinyalakan saat terminal WSL / Claude Code dipakai,
# dan keluar sendiri setelah WSL berhenti.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
win_env() { cmd.exe /c "echo %$1%" 2>/dev/null | tr -d '\r'; }

for cmd in python3 powershell.exe cmd.exe wslpath; do
  command -v "$cmd" >/dev/null || { echo "Butuh '$cmd'. Jalankan installer ini dari WSL di Windows." >&2; exit 1; }
done

LOCALAPPDATA_WIN="$(win_env LOCALAPPDATA)"
APPDATA_WIN="$(win_env APPDATA)"
APP_WIN="$LOCALAPPDATA_WIN\\OriginIsland"
APP_WSL="$(wslpath "$LOCALAPPDATA_WIN")/OriginIsland"
OLD_APP_WSL="$(wslpath "$LOCALAPPDATA_WIN")/ClaudeIsland"     # nama versi lama
STARTUP_WSL="$(wslpath "$APPDATA_WIN")/Microsoft/Windows/Start Menu/Programs/Startup"
HOOK_DIR="$HOME/.claude/island"
CRED_WIN="\\\\wsl.localhost\\${WSL_DISTRO_NAME}$(echo "$HOME" | tr '/' '\\')\\.claude\\.credentials.json"
BASHRC="$HOME/.bashrc"

echo "==> Menghentikan Origin Island yang sedang berjalan (bila ada)"
powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { \$_.CommandLine -like '*Island*island.ps1*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" || true
rm -f "$APP_WSL/alive"

echo "==> Menyalin aplikasi ke $APP_WIN"
mkdir -p "$APP_WSL"
# Pindahkan posisi pil dari versi lama (ClaudeIsland) bila ada.
if [[ -d "$OLD_APP_WSL" && ! -f "$APP_WSL/position.json" && -f "$OLD_APP_WSL/position.json" ]]; then
  cp "$OLD_APP_WSL/position.json" "$APP_WSL/"
fi
# PowerShell 5.1 butuh BOM agar membaca file sebagai UTF-8.
{ printf '\xEF\xBB\xBF'; cat "$HERE/windows/island.ps1"; } > "$APP_WSL/island.ps1"
rm -rf "$APP_WSL/sounds" "$APP_WSL/icons"
cp -r "$HERE/sounds" "$APP_WSL/"
mkdir -p "$APP_WSL/icons"
cp "$HERE"/icons/*.svg "$HERE"/icons/*.json "$APP_WSL/icons/"   # ikon + maskot ogin

# config.json: path selalu ditulis ulang; preferensi (suara, durasi notifikasi, dll.) dipertahankan,
# termasuk dari folder versi lama.
python3 - "$APP_WSL/config.json" "$OLD_APP_WSL/config.json" "$CRED_WIN" "$APP_WIN\\events.jsonl" <<'EOF'
import json, os, sys
new_path, old_path, cred, events = sys.argv[1:5]
cfg = {"pollSeconds": 300, "notifySeconds": 8, "sound": True, "hideOnFullscreen": True, "exitWhenWslStops": True}
keep = ("pollSeconds", "notifySeconds", "sound", "soundVolume", "soundDone", "soundAttention",
        "hideOnFullscreen", "exitWhenWslStops")
for p in (old_path, new_path):          # yang baru menang
    if os.path.exists(p):
        try:
            with open(p, encoding="utf-8-sig") as f:
                cfg.update({k: v for k, v in json.load(f).items() if k in keep})
        except (OSError, ValueError):
            pass
cfg["pollSeconds"] = max(300, int(cfg.get("pollSeconds", 300)))
cfg.update(credentialsPath=cred, eventsPath=events)
with open(new_path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
EOF

cat > "$APP_WSL/start-island.vbs" <<EOF
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File ""$APP_WIN\\island.ps1""", 0, False
EOF
sed -i 's/$/\r/' "$APP_WSL/start-island.vbs"

# Sisa versi lama: autostart Windows (membangunkan WSL saat login) & folder ClaudeIsland.
rm -f "$STARTUP_WSL/ClaudeIsland.vbs"
rm -rf "$OLD_APP_WSL"

echo "==> Memasang hook + statusline Claude Code di ~/.claude/settings.json"
mkdir -p "$HOOK_DIR"
cp "$HERE/wsl/island_hook.py" "$HERE/wsl/island_statusline.py" "$HERE/wsl/island_launch.sh" "$HOOK_DIR/"
chmod +x "$HOOK_DIR/island_launch.sh"
python3 "$HERE/wsl/settings_hooks.py" install \
  "$HOOK_DIR/island_hook.py" "$APP_WSL/events.jsonl" \
  "$HOOK_DIR/island_statusline.py" "$APP_WSL/usage.json"

echo "==> Menyalakan island otomatis saat terminal WSL dibuka (~/.bashrc)"
sed -i '/# >>> claude-island >>>/,/# <<< claude-island <<</d; /# >>> origin-island >>>/,/# <<< origin-island <<</d' "$BASHRC"
cat >> "$BASHRC" <<EOF
# >>> origin-island >>>
[ -x "$HOOK_DIR/island_launch.sh" ] && "$HOOK_DIR/island_launch.sh" "$APP_WSL"
# <<< origin-island <<<
EOF

echo "==> Menjalankan Origin Island"
"$HOOK_DIR/island_launch.sh" "$APP_WSL"

echo
echo "Selesai. Origin Island menyala saat WSL/Claude Code dipakai dan berhenti sendiri saat WSL mati."
echo "Buka ulang sesi Claude Code yang sedang berjalan supaya hook & statusline aktif."
