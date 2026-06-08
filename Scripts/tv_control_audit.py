#!/usr/bin/env python3
"""Bounded Juicr TV remote-control audit.

The audit drives Android TV DPAD paths and reads Juicr's debug focus trace from
logcat. It reports focus labels after each key so dead ends, invisible focus,
and stuck routes can be investigated without exposing playback/source details.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DIAGNOSTICS = ROOT / "Diagnostics"
SCREENSHOTS = DIAGNOSTICS / "screenshots"
PACKAGE = "app.juicr.flutter"
FOCUS_RE = re.compile(r"Juicr TV focus trace label=([^ ]+) tab=([^\r\n]+)")
SCREENSHOT_FOCUS_LABELS = {
    "tv-discovery-menu-sort-featured",
    "tv-discovery-menu-apply",
}
SDK_CANDIDATES = (
    Path(os.environ.get("ANDROID_HOME", "")),
    Path(os.environ.get("ANDROID_SDK_ROOT", "")),
    Path.home() / "AppData" / "Local" / "Android" / "Sdk",
)


KEYS = {
    "up": "KEYCODE_DPAD_UP",
    "down": "KEYCODE_DPAD_DOWN",
    "left": "KEYCODE_DPAD_LEFT",
    "right": "KEYCODE_DPAD_RIGHT",
    "center": "KEYCODE_DPAD_CENTER",
    "back": "KEYCODE_BACK",
}


SCENARIOS: dict[str, list[str]] = {
    "home_all_rail_sweeps": [
        # Implemented as an adaptive scenario in main().
        "down",
    ],
    "home_layer_escape": [
        "down",
        "center",
        *["right"] * 4,
        *["left"] * 4,
        "back",
        "left",
        "right",
        "down",
    ],
    "home_edges": [
        "down",
        *["right"] * 10,
        *["left"] * 10,
        *["down"] * 8,
        *["up"] * 8,
        "left",
        "right",
        "left",
        "center",
        "right",
    ],
    "home_zigzag": [
        "down",
        "right",
        "down",
        "right",
        "up",
        "left",
        "down",
        "left",
        "right",
        "up",
        "right",
        "left",
    ],
    "search_escape": [
        "left",
        "up",
        "center",
        "down",
        "right",
        "left",
        "up",
        "down",
        "back",
    ],
    "discovery_grid_edges": [
        "left",
        "down",
        "center",
        "right",
        *["right"] * 18,
        *["left"] * 18,
        *["down"] * 10,
        *["right"] * 10,
        *["left"] * 10,
        *["up"] * 10,
        "left",
        "right",
    ],
    "discovery_filter_dialog": [
        "left",
        "down",
        "center",
        "right",
        "center",
        *["down"] * 6,
        *["up"] * 6,
        "right",
        "left",
        "back",
    ],
    "discovery_filter_scroll": [
        "left",
        "down",
        "center",
        "right",
        "up",
        "up",
        "center",
        *["down"] * 9,
        *["up"] * 9,
        "back",
    ],
    "library_edges": [
        "left",
        "down",
        "down",
        "center",
        "right",
        *["right"] * 18,
        *["left"] * 18,
        *["down"] * 8,
        *["right"] * 8,
        *["left"] * 8,
        *["up"] * 8,
        "left",
        "right",
    ],
    "settings_edges": [
        "left",
        "down",
        "down",
        "down",
        "center",
        "right",
        "left",
        *["down"] * 5,
        *["up"] * 5,
        "right",
        "center",
        "back",
    ],
    "details_overlay_edges": [
        "down",
        "center",
        *["right"] * 6,
        *["left"] * 6,
        *["down"] * 5,
        *["up"] * 5,
        "back",
    ],
}


def tool_path(name: str, relative: str) -> str | None:
    found = shutil.which(name) or shutil.which(f"{name}.exe")
    if found:
        return found
    for sdk in SDK_CANDIDATES:
        if not sdk or not str(sdk):
            continue
        candidate = sdk / relative
        if candidate.exists():
            return str(candidate)
    return None


def run(command: list[str], timeout: int = 30) -> tuple[int, str]:
    try:
        completed = subprocess.run(
            command,
            text=True,
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            check=False,
        )
        return completed.returncode, completed.stdout or ""
    except subprocess.TimeoutExpired as error:
        output = error.stdout or ""
        if isinstance(output, bytes):
            output = output.decode("utf-8", errors="replace")
        return 124, output


def latest_focus(adb: str, device: str) -> tuple[str, str]:
    code, output = run([adb, "-s", device, "logcat", "-d"], timeout=10)
    if code != 0:
        return "logcat_error", "unknown"
    matches = FOCUS_RE.findall(output)
    if not matches:
        return "none", "unknown"
    return matches[-1][0], matches[-1][1].strip()


def is_foreground(adb: str, device: str) -> bool:
    code, output = run([adb, "-s", device, "shell", "dumpsys", "window", "windows"], timeout=10)
    if code != 0:
        return False
    return PACKAGE in output


def screenshot(adb: str, device: str, path: Path) -> bool:
    try:
        completed = subprocess.run(
            [adb, "-s", device, "exec-out", "screencap", "-p"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return False
    if completed.returncode != 0:
        return False
    path.write_bytes(completed.stdout)
    return True


def send_key(adb: str, device: str, key: str) -> tuple[int, str]:
    return run([adb, "-s", device, "shell", "input", "keyevent", key], timeout=10)


def audit_key(
    *,
    adb: str,
    device: str,
    scenario: str,
    stamp: str,
    action: str,
    index: int,
    delay: float,
    last_label: str,
    lines: list[str],
) -> tuple[str, int]:
    key = KEYS[action]
    code, _ = send_key(adb, device, key)
    time.sleep(delay)
    label, tab = latest_focus(adb, device)
    foreground = is_foreground(adb, device)
    changed = label != last_label
    lines.append(
        f"{index:02d} key={action:<6} exit={code} focus={label} tab={tab} "
        f"changed={changed} foreground={foreground}"
    )
    failures = 0
    if code != 0 or not foreground or label == "none":
        failures += 1
        png = SCREENSHOTS / f"tv-control-audit-{scenario}-{stamp}-{index:02d}.png"
        screenshot(adb, device, png)
        lines.append(f"FAIL hard key={action} screenshot={png}")
    elif label in SCREENSHOT_FOCUS_LABELS:
        png = SCREENSHOTS / f"tv-control-audit-focus-{scenario}-{stamp}-{index:02d}.png"
        screenshot(adb, device, png)
        lines.append(f"SHOT focus={label} screenshot={png}")
    return label, failures


def audit_home_rail_sweeps(
    *,
    adb: str,
    device: str,
    stamp: str,
    delay: float,
    lines: list[str],
) -> int:
    failures = 0
    step = 1
    label, _ = latest_focus(adb, device)

    label, count = audit_key(
        adb=adb,
        device=device,
        scenario="home_all_rail_sweeps",
        stamp=stamp,
        action="down",
        index=step,
        delay=delay,
        last_label=label,
        lines=lines,
    )
    failures += count
    step += 1

    for rail in range(1, 6):
        lines.append(f"RAIL {rail} sweep right")
        unchanged = 0
        for _ in range(30):
            previous = label
            label, count = audit_key(
                adb=adb,
                device=device,
                scenario="home_all_rail_sweeps",
                stamp=stamp,
                action="right",
                index=step,
                delay=delay,
                last_label=label,
                lines=lines,
            )
            failures += count
            step += 1
            unchanged = unchanged + 1 if label == previous else 0
            if label.startswith("tv-rail-") and label.endswith("-see-all") or unchanged >= 3:
                break

        lines.append(f"RAIL {rail} sweep left")
        unchanged = 0
        for _ in range(30):
            previous = label
            label, count = audit_key(
                adb=adb,
                device=device,
                scenario="home_all_rail_sweeps",
                stamp=stamp,
                action="left",
                index=step,
                delay=delay,
                last_label=label,
                lines=lines,
            )
            failures += count
            step += 1
            unchanged = unchanged + 1 if label == previous else 0
            first_card = label.startswith("tv-rail-") and label.endswith("-card-0")
            if label in {"tv-page-entry-Home", "tv-nav-Home"} or first_card or unchanged >= 3:
                break

        if label == "tv-nav-Home":
            label, count = audit_key(
                adb=adb,
                device=device,
                scenario="home_all_rail_sweeps",
                stamp=stamp,
                action="right",
                index=step,
                delay=delay,
                last_label=label,
                lines=lines,
            )
            failures += count
            step += 1

        if rail != 5:
            lines.append(f"RAIL {rail} move down")
            label, count = audit_key(
                adb=adb,
                device=device,
                scenario="home_all_rail_sweeps",
                stamp=stamp,
                action="down",
                index=step,
                delay=delay,
                last_label=label,
                lines=lines,
            )
            failures += count
            step += 1

    lines.append("")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit Juicr TV DPAD focus paths.")
    parser.add_argument("--device", default="emulator-5554")
    parser.add_argument("--scenario", choices=sorted(SCENARIOS), action="append")
    parser.add_argument("--delay", type=float, default=0.25)
    parser.add_argument("--launch-wait", type=float, default=8.0)
    args = parser.parse_args()

    adb = tool_path("adb", "platform-tools/adb.exe")
    if adb is None:
        print("FAIL adb not found")
        return 1

    DIAGNOSTICS.mkdir(exist_ok=True)
    SCREENSHOTS.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    report = DIAGNOSTICS / f"tv_control_audit_{stamp}.txt"
    scenario_names = args.scenario or list(SCENARIOS)

    lines = [
        "Juicr TV control audit",
        f"generated={dt.datetime.now().isoformat(timespec='seconds')}",
        "redaction=focus debug labels only",
        f"device={args.device}",
        "",
    ]

    failures = 0
    for scenario in scenario_names:
        lines.append(f"SCENARIO {scenario}")
        run([adb, "-s", args.device, "logcat", "-c"], timeout=10)
        run([adb, "-s", args.device, "shell", "am", "force-stop", PACKAGE], timeout=10)
        run([adb, "-s", args.device, "shell", "monkey", "-p", PACKAGE, "1"], timeout=10)
        time.sleep(args.launch_wait)
        last_label, last_tab = latest_focus(adb, args.device)
        lines.append(f"start focus={last_label} tab={last_tab}")
        if scenario == "home_all_rail_sweeps":
            failures += audit_home_rail_sweeps(
                adb=adb,
                device=args.device,
                stamp=stamp,
                delay=args.delay,
                lines=lines,
            )
            continue
        stagnant = 0
        stagnant_keys: list[str] = []
        seen_labels: set[str] = set()
        for index, action in enumerate(SCENARIOS[scenario], start=1):
            key = KEYS[action]
            code, output = send_key(adb, args.device, key)
            time.sleep(args.delay)
            label, tab = latest_focus(adb, args.device)
            seen_labels.add(label)
            foreground = is_foreground(adb, args.device)
            changed = label != last_label
            if changed:
                stagnant = 0
                stagnant_keys.clear()
            else:
                stagnant += 1
                stagnant_keys.append(action)
            lines.append(
                f"{index:02d} key={action:<6} exit={code} focus={label} tab={tab} "
                f"changed={changed} foreground={foreground}"
            )
            if code != 0 or not foreground or label == "none":
                failures += 1
                png = SCREENSHOTS / f"tv-control-audit-{scenario}-{stamp}-{index:02d}.png"
                screenshot(adb, args.device, png)
                lines.append(f"FAIL hard key={action} screenshot={png}")
            elif label in SCREENSHOT_FOCUS_LABELS:
                png = SCREENSHOTS / f"tv-control-audit-focus-{scenario}-{stamp}-{index:02d}.png"
                screenshot(adb, args.device, png)
                lines.append(f"SHOT focus={label} screenshot={png}")
            if stagnant >= 4 and len(set(stagnant_keys[-4:])) > 1:
                png = SCREENSHOTS / f"tv-control-audit-stall-{scenario}-{stamp}-{index:02d}.png"
                screenshot(adb, args.device, png)
                lines.append(
                    "WARN suspect_stall "
                    f"last_keys={','.join(stagnant_keys[-4:])} screenshot={png}"
                )
                stagnant = 0
                stagnant_keys.clear()
            last_label = label
        if scenario == "discovery_filter_scroll" and "tv-discovery-menu-apply" not in seen_labels:
            failures += 1
            png = SCREENSHOTS / f"tv-control-audit-missing-{scenario}-{stamp}.png"
            screenshot(adb, args.device, png)
            lines.append(
                "FAIL missing_required_focus "
                f"required=tv-discovery-menu-apply screenshot={png}"
            )
        lines.append("")

    report.write_text("\n".join(lines), encoding="utf-8")
    print(f"Report: {report}")
    if failures:
        print(f"FAIL control audit failures={failures}")
        return 1
    print("PASS control audit")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
