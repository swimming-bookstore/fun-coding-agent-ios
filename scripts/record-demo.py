#!/usr/bin/env python3
"""Drive Fun on the iOS Simulator and record demo/demo.mp4."""

from __future__ import annotations

import json
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WS = Path.home() / "demo"
OPENED = Path.home() / ".local/share/fun/opened.json"
OUT = ROOT / "demo" / "demo.mp4"
RAW = ROOT / "demo" / "raw.mov"
DERIVED = ROOT / ".demo-derived"
APP = DERIVED / "Build" / "Products" / "Release-iphonesimulator" / "Fun.app"
BUNDLE = "dev.fun.ios"
MAX_SEC = 150.0


def die(msg: str) -> None:
    print(msg, file=sys.stderr)
    sys.exit(1)


def sessions_dir(workspace: Path) -> Path:
    cwd = str(workspace)
    safe = "".join("-" if c in "/\\:" or c.isspace() else c for c in cwd.lstrip("/\\"))
    h = 0
    for b in cwd.encode():
        h = (h * 16_777_619) ^ b
        h &= (1 << 64) - 1
    digest = f"{h & 0xFFFFFFFF:08x}"
    data = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    return data / "fun" / "sessions" / f"--{safe}-{digest}--"


def udid() -> str:
    if env := os.environ.get("FUN_DEMO_UDID"):
        return env
    r = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        capture_output=True,
        text=True,
        check=True,
    )
    data = json.loads(r.stdout)
    devices = [
        d
        for runtime, group in data.get("devices", {}).items()
        if "iOS" in runtime
        for d in group
        if d.get("isAvailable") and "iPhone" in d.get("name", "")
    ]
    for d in devices:
        if d.get("state") == "Booted":
            return d["udid"]
    if devices:
        return devices[-1]["udid"]
    die("no iPhone simulator")


def boot(device: str) -> None:
    subprocess.run(["xcrun", "simctl", "boot", device], check=False)
    subprocess.run(["xcrun", "simctl", "bootstatus", device, "-b"], check=True)


def kill_fun(device: str) -> None:
    subprocess.run(["xcrun", "simctl", "terminate", device, BUNDLE], check=False)


def reset_workspace() -> None:
    WS.mkdir(parents=True, exist_ok=True)
    for p in WS.iterdir():
        if p.is_file() or p.is_symlink():
            p.unlink()
        else:
            shutil.rmtree(p)
    d = sessions_dir(WS)
    if d.is_dir():
        shutil.rmtree(d)


def build() -> None:
    env = os.environ.copy()
    env["PATH"] = (
        str(Path.home() / ".cargo/bin")
        + ":/opt/homebrew/bin:/usr/local/bin:"
        + env.get("PATH", "/usr/bin:/bin")
    )
    cmd = [
        "xcodebuild",
        "-project",
        str(ROOT / "ios" / "Fun.xcodeproj"),
        "-scheme",
        "Fun",
        "-configuration",
        "Release",
        "-derivedDataPath",
        str(DERIVED),
        "-sdk",
        "iphonesimulator",
        "ONLY_ACTIVE_ARCH=YES",
        "ARCHS=arm64",
        "EXCLUDED_SOURCE_FILE_NAMES=",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS=FUN_DEMO",
        "build",
    ]
    print(" ".join(cmd), file=sys.stderr)
    subprocess.check_call(cmd, cwd=str(ROOT), env=env)


def app_running(device: str) -> bool:
    ps = subprocess.run(
        ["xcrun", "simctl", "spawn", device, "ps", "aux"],
        capture_output=True,
        text=True,
    )
    return "Fun.app" in (ps.stdout or "")


def main() -> None:
    if not (Path.home() / ".local/share/fun/auth.json").exists():
        die("not logged in — run `fun login`")
    device = udid()
    boot(device)
    kill_fun(device)
    reset_workspace()
    OPENED.parent.mkdir(parents=True, exist_ok=True)
    OPENED.write_text(json.dumps([str(WS)], indent=2) + "\n")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    for p in (OUT, RAW):
        if p.exists():
            p.unlink()
    if os.environ.get("FUN_DEMO_REBUILD") == "1" or not APP.exists():
        build()
    if not APP.exists():
        die(f"missing {APP}")

    subprocess.check_call(["xcrun", "simctl", "install", device, str(APP)])
    rec = subprocess.Popen(
        ["xcrun", "simctl", "io", device, "recordVideo", "--codec=h264", str(RAW)]
    )
    t0 = time.monotonic()
    try:
        subprocess.check_call(
            [
                "xcrun",
                "simctl",
                "launch",
                "-e",
                "FUN_DEMO=1",
                "-e",
                f"FUN_DEMO_FOLDER={WS}",
                device,
                BUNDLE,
            ]
        )
        while time.monotonic() - t0 < MAX_SEC:
            if not app_running(device) and time.monotonic() - t0 > 8:
                break
            time.sleep(0.4)
        rec.send_signal(signal.SIGINT)
        try:
            rec.wait(timeout=8)
        except subprocess.TimeoutExpired:
            rec.kill()
    finally:
        kill_fun(device)
        if rec.poll() is None:
            rec.terminate()

    if not RAW.exists() or RAW.stat().st_size < 20_000:
        die("recording missing")
    if OUT.exists():
        OUT.unlink()
    shutil.copyfile(RAW, OUT)
    RAW.unlink(missing_ok=True)
    print(OUT, OUT.stat().st_size)
    print(f"wrote {OUT} ({time.monotonic() - t0:.1f}s)")


if __name__ == "__main__":
    main()
