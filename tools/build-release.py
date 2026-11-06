#!/usr/bin/env python3
"""Buat ZIP rilis: python3 tools/build-release.py v1.1.0  (hasil di dist/)."""
import pathlib, sys, zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
CMD = '@echo off\r\nset ORIGIN_ISLAND_TARGET={target}\r\npowershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"\r\npause\r\n'
COMMON = ["install.ps1", "uninstall.ps1", "LICENSE", "windows", "icons", "sounds"]
PACKS = {
    "windows": ("windows", COMMON),
    "windows-wsl": ("wsl", COMMON + ["install.sh", "uninstall.sh", "wsl"]),
}


def files(names):
    for name in names:
        path = ROOT / name
        for f in sorted(path.rglob("*")) if path.is_dir() else [path]:
            if f.is_file() and "__pycache__" not in f.parts and "Zone.Identifier" not in f.name and f.suffix != ".zip":
                yield f


def main():
    version = sys.argv[1]
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    for pack, (target, names) in PACKS.items():
        top = f"origin-island-{pack}-{version}"
        with zipfile.ZipFile(dist / f"{top}.zip", "w", zipfile.ZIP_DEFLATED) as z:
            for f in files(names):
                z.write(f, f"{top}/{f.relative_to(ROOT).as_posix()}")
            z.writestr(f"{top}/Pasang.cmd", CMD.format(target=target))
        print(dist / f"{top}.zip")


if __name__ == "__main__":
    main()
