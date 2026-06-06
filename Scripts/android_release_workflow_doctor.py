#!/usr/bin/env python3
"""Validate the Android release GitHub Actions workflow contract."""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "android-release.yml"
EXPECTED_ASSETS = (
    "juicr-${tag}-universal.apk",
    "juicr-${tag}-armeabi-v7a.apk",
    "juicr-${tag}-arm64-v8a.apk",
    "juicr-${tag}-x86_64.apk",
    "juicr-${TAG}-universal.apk",
    "juicr-${TAG}-armeabi-v7a.apk",
    "juicr-${TAG}-arm64-v8a.apk",
    "juicr-${TAG}-x86_64.apk",
)


def require(text: str, needle: str, label: str, failures: list[str]) -> None:
    if needle not in text:
        failures.append(f"missing {label}: {needle}")


def main() -> int:
    if not WORKFLOW.exists():
        print(f"failed: workflow does not exist: {WORKFLOW}")
        return 1

    text = WORKFLOW.read_text(encoding="utf-8")
    failures: list[str] = []

    require(text, "permissions:", "release permissions", failures)
    require(text, "contents: write", "contents write permission", failures)
    require(text, "push:", "tag trigger", failures)
    require(text, 'workflow_dispatch:', "manual trigger", failures)
    require(text, "release_tag:", "manual release tag input", failures)
    require(text, "default: v1.0.1", "current release default tag", failures)
    require(text, "fetch-depth: 0", "full checkout history", failures)
    require(text, "RELEASE_KEYSTORE_BASE64", "keystore secret", failures)
    require(text, "RELEASE_STORE_PASSWORD", "store password secret", failures)
    require(text, "RELEASE_KEY_ALIAS", "key alias secret", failures)
    require(text, "RELEASE_KEY_PASSWORD", "key password secret", failures)
    require(text, "flutter pub get", "Flutter dependency install", failures)
    require(text, "flutter build apk --release", "universal APK build", failures)
    require(text, "--split-per-abi", "split APK build", failures)
    require(text, "--obfuscate", "obfuscated split APK build", failures)
    require(text, "app-armeabi-v7a-release.apk", "armeabi-v7a source APK", failures)
    require(text, "app-arm64-v8a-release.apk", "arm64-v8a source APK", failures)
    require(text, "app-x86_64-release.apk", "x86_64 source APK", failures)
    require(text, "gh release upload", "GitHub release upload", failures)
    require(text, "--clobber", "release asset replacement", failures)

    for asset in EXPECTED_ASSETS:
        require(text, asset, f"expected asset {asset}", failures)

    if failures:
        print("android release workflow doctor failed:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("android release workflow doctor passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
