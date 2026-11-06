#!/usr/bin/env python3
"""Claude Code hook -> Origin Island (Windows).

Dipanggil oleh Claude Code untuk setiap event yang didaftarkan di settings.json.
Menulis satu baris JSON ke file events yang dibaca aplikasi island di Windows.
Tidak boleh mencetak apa pun ke stdout (output UserPromptSubmit masuk ke konteks).
"""
import json
import os
import re
import subprocess
import sys
import time

MAX_FILE = 256 * 1024
MAX_MSG = 240


def clean(text):
    text = re.sub(r"```.*?```", " [kode] ", text or "", flags=re.S)
    text = re.sub(r"[`*#>|]+", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:MAX_MSG] + ("…" if len(text) > MAX_MSG else "")


def last_assistant_text(transcript_path):
    """Fallback bila hook Stop tidak menyertakan last_assistant_message."""
    if not transcript_path or not os.path.exists(transcript_path):
        return ""
    with open(transcript_path, "rb") as f:
        f.seek(0, 2)
        f.seek(max(0, f.tell() - 200_000))
        lines = f.read().decode("utf-8", "ignore").splitlines()
    for line in reversed(lines):
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if rec.get("type") != "assistant":
            continue
        content = (rec.get("message") or {}).get("content")
        if isinstance(content, str):
            return content
        texts = [c.get("text", "") for c in content or [] if c.get("type") == "text"]
        if any(texts):
            return " ".join(texts)
    return ""


def terminal_kind():
    """Terminal Windows yang menjalankan sesi ini (diwarisi lewat env dari proses claude)."""
    if os.environ.get("TERM_PROGRAM") == "vscode":
        return "vscode"
    if os.environ.get("WT_SESSION"):
        return "wt"
    return ""


def session_tty():
    """pts terminal sesi ini. stdin hook berupa pipe, jadi cari lewat proses induk (claude)."""
    pid = os.getppid()
    while pid > 1:
        with open(f"/proc/{pid}/stat", encoding="utf-8", errors="replace") as f:
            # Nama proses bisa berisi spasi: field setelah ')' = state ppid pgrp session tty_nr
            fields = f.read().rsplit(")", 1)[1].split()
        tty_nr = int(fields[4])
        if os.major(tty_nr) == 136:  # 136 = /dev/pts/*
            return f"/dev/pts/{os.minor(tty_nr)}"
        pid = int(fields[1])
    return ""


def main():
    out = sys.argv[sys.argv.index("--out") + 1]
    data = json.load(sys.stdin)
    event = data.get("hook_event_name", "")
    cwd = (data.get("cwd") or "").rstrip("/")
    rec = {
        "ts": time.time(),
        "event": event,
        "session": data.get("session_id", ""),
        "project": os.path.basename(cwd) or "claude",
        # Supaya island bisa membuka terminal yang benar saat notifikasi diklik.
        "cwd": cwd,
        "distro": os.environ.get("WSL_DISTRO_NAME", ""),
        "term": terminal_kind(),
        # Supaya klik bisa memilih tab yang tepat dan island bisa mendeteksi pembatalan
        # (Claude Code tidak mengirim hook apa pun saat perintah dibatalkan).
        "tty": session_tty(),
        "transcript": data.get("transcript_path", ""),
    }
    if event == "Stop":
        msg = data.get("last_assistant_message") or last_assistant_text(data.get("transcript_path"))
        rec["message"] = clean(msg)
    elif event == "Notification":
        rec["message"] = clean(data.get("message", ""))
        rec["type"] = data.get("notification_type", "")
    elif event == "UserPromptSubmit":
        rec["message"] = clean(data.get("prompt", ""))
    elif event == "StopFailure":
        err = data.get("error") or data.get("message") or data.get("reason") or ""
        rec["message"] = clean(err if isinstance(err, str) else json.dumps(err, ensure_ascii=False))
    elif event in ("PreToolUse", "PostToolUseFailure"):
        rec["tool"] = data.get("tool_name", "")

    os.makedirs(os.path.dirname(out), exist_ok=True)
    mode = "w" if os.path.exists(out) and os.path.getsize(out) > MAX_FILE else "a"
    with open(out, mode, encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    if event in ("SessionStart", "UserPromptSubmit"):
        # Pastikan island menyala (mis. Claude Code dibuka tanpa lewat terminal bash, atau
        # island sempat ditutup/mati). Launcher hanya mengecek file 'alive', jadi murah.
        launcher = os.path.join(os.path.dirname(os.path.abspath(__file__)), "island_launch.sh")
        if os.path.exists(launcher):
            subprocess.Popen(["bash", launcher, os.path.dirname(out)], start_new_session=True,
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # jangan pernah mengganggu Claude Code
    sys.exit(0)
