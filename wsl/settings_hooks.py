#!/usr/bin/env python3
"""Tambah/hapus hook + statusline Origin Island di ~/.claude/settings.json
tanpa mengubah setelan lain.

Pemakaian:
  settings_hooks.py install <hook.py> <events.jsonl> <statusline.py> <usage.json>
  settings_hooks.py uninstall
"""
import json
import os
import shutil
import sys

SETTINGS = os.path.expanduser("~/.claude/settings.json")
EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
          "Notification", "Stop", "StopFailure", "SessionEnd"]
HOOK_MARK = "island_hook.py"
STATUS_MARK = "island_statusline.py"


def is_ours(group):
    return any(HOOK_MARK in h.get("command", "") for h in group.get("hooks", []))


def main():
    action = sys.argv[1]
    settings = {}
    if os.path.exists(SETTINGS):
        with open(SETTINGS) as f:
            settings = json.load(f)
        shutil.copy(SETTINGS, SETTINGS + ".bak-island")

    # Hook event
    hooks = settings.setdefault("hooks", {})
    for ev in EVENTS:
        groups = [g for g in hooks.get(ev, []) if not is_ours(g)]
        if action == "install":
            hook, events = sys.argv[2], sys.argv[3]
            groups.append({"hooks": [{
                "type": "command",
                "command": f'python3 "{hook}" --out "{events}"',
                "timeout": 5,
            }]})
        if groups:
            hooks[ev] = groups
        else:
            hooks.pop(ev, None)
    if not hooks:
        settings.pop("hooks")

    # Statusline: sumber kuota tanpa request tambahan. Jangan timpa statusline milik user.
    current = settings.get("statusLine") or {}
    ours = STATUS_MARK in current.get("command", "")
    if action == "install":
        if current and not ours:
            print("   ! statusLine sudah dipakai skrip lain, tidak diubah.")
            print("     Kuota tidak tampil, kecuali \"usageApiFallback\": true di config.json (lihat README).")
        else:
            script, usage = sys.argv[4], sys.argv[5]
            settings["statusLine"] = {
                "type": "command",
                "command": f'python3 "{script}" --out "{usage}"',
            }
    elif ours:
        settings.pop("statusLine")

    with open(SETTINGS, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print(f"   {SETTINGS} diperbarui (cadangan: settings.json.bak-island)")


if __name__ == "__main__":
    main()
