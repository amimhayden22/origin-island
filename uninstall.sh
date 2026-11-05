#!/usr/bin/env bash
# Hapus Origin Island beserta hook, statusline, dan baris di ~/.bashrc
# (termasuk sisa versi lama bernama ClaudeIsland). Sama dengan tombol "Uninstall" di island.
exec bash "$(cd "$(dirname "$0")" && pwd)/wsl/island_uninstall.sh" "$@"
