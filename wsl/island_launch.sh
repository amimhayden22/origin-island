#!/usr/bin/env bash
# Nyalakan Origin Island (Windows) bila belum berjalan. Aman dipanggil berkali-kali:
# dipanggil dari ~/.bashrc (saat terminal WSL dibuka) dan dari hook SessionStart Claude Code.
# Pemakaian: island_launch.sh <folder aplikasi island versi WSL, mis. /mnt/c/Users/x/AppData/Local/OriginIsland>

app="$1"
vbs="$app/start-island.vbs"
alive="$app/alive"
[[ -f "$vbs" ]] || exit 0

# Island menulis file 'alive' tiap 3 detik; kalau masih segar berarti sudah jalan.
if [[ -f "$alive" ]] && (( $(date +%s) - $(stat -c %Y "$alive") < 15 )); then
  exit 0
fi

# Jalankan di latar belakang supaya shell tidak menunggu; cd ke C: agar exe Windows tidak
# mengeluh soal direktori kerja UNC.
( cd /mnt/c && setsid wscript.exe "$(wslpath -w "$vbs")" >/dev/null 2>&1 & )
