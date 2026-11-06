#!/usr/bin/env python3
"""Statusline Claude Code -> Origin Island.

Claude Code mengirim data `rate_limits` (dari header respons request-nya sendiri) ke
statusline. Skrip ini menyimpannya ke usage.json milik island, jadi island tidak perlu
memanggil API usage terus-menerus (yang bisa kena rate limit 429).

Juga mencetak satu baris statusline: "<model> · 5j 31% · 7h 32%".
"""
import datetime as dt
import json
import os
import sys
import time

WINDOWS = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"]
RESET_TOLERANCE = 60  # detik; waktu reset dari server bisa sedikit bergeser


def to_iso(value):
    """resets_at bisa berupa epoch (detik/milidetik) atau string ISO."""
    if isinstance(value, (int, float)):
        if value > 1e12:
            value /= 1000
        return dt.datetime.fromtimestamp(value, dt.timezone.utc).isoformat()
    return value


def extract(data):
    limits = data.get("rate_limits") or {}
    usage = {}
    for key in WINDOWS:
        w = limits.get(key)
        if not isinstance(w, dict):
            continue
        pct = w.get("used_percentage", w.get("utilization"))
        if pct is None:
            continue
        usage[key] = {"utilization": float(pct), "resets_at": to_iso(w.get("resets_at"))}
    return usage


def reset_epoch(window):
    try:
        return dt.datetime.fromisoformat(window.get("resets_at")).timestamp()
    except (TypeError, ValueError):
        return None


def merge(usage, last):
    """Tiap sesi hanya tahu kuota dari request terakhirnya, jadi sesi yang idle membawa angka lama.
    Dalam satu jendela reset angkanya hanya naik; jendela yang lebih lama diabaikan."""
    merged = dict(last, **usage)
    for key, new in usage.items():
        old = last.get(key)
        if not isinstance(old, dict):
            continue
        new_reset, old_reset = reset_epoch(new), reset_epoch(old)
        if new_reset is None or old_reset is None:
            continue
        if new_reset < old_reset - RESET_TOLERANCE:
            merged[key] = old
        elif abs(new_reset - old_reset) <= RESET_TOLERANCE and old["utilization"] > new["utilization"]:
            merged[key] = old
    return merged


def save(usage, out):
    """Tulis ke disk Windows hanya bila angkanya berubah (statusline dipanggil sering).
    Mengembalikan angka gabungan semua sesi, termasuk sesi Windows yang menulis file yang sama."""
    try:
        with open(out, encoding="utf-8-sig") as f:
            last = json.load(f)
    except (OSError, ValueError):
        last = {}
    previous = {k: v for k, v in last.items() if k in WINDOWS and isinstance(v, dict)}
    usage = merge(usage, previous)
    # Tetap tulis ulang tiap 5 menit supaya island tahu datanya masih segar.
    if previous == usage and time.time() - last.get("ts", 0) < 300:
        return usage
    record = dict(usage, source="statusline", ts=time.time())
    tmp = out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(record, f)
    os.replace(tmp, out)
    return usage


def main():
    out = sys.argv[sys.argv.index("--out") + 1]
    data = json.load(sys.stdin)
    usage = extract(data)
    if usage:
        try:
            usage = save(usage, out)
        except OSError:
            pass

    parts = []
    model = (data.get("model") or {}).get("display_name")
    if model:
        parts.append(model)
    if "five_hour" in usage:
        parts.append("5j {:.0f}%".format(usage["five_hour"]["utilization"]))
    if "seven_day" in usage:
        parts.append("7h {:.0f}%".format(usage["seven_day"]["utilization"]))
    print(" · ".join(parts))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("")
