#!/usr/bin/env python3
"""Validate Juicr repository setup files."""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


CHECKS: tuple[tuple[str, str, tuple[str, ...]], ...] = (
    (
        ".github/dependabot.yml",
        "Dependabot config",
        (
            'package-ecosystem: "github-actions"',
            'package-ecosystem: "pub"',
            'package-ecosystem: "gradle"',
            'directory: "/Juicr Android"',
            'directory: "/Juicr TV"',
            'target-branch: "dev"',
            "groups:",
            "github-actions:",
            "juicr-android-dart:",
            "juicr-tv-dart:",
            "juicr-android-gradle:",
            "juicr-tv-gradle:",
            "open-pull-requests-limit: 1",
        ),
    ),
    (
        "README.md",
        "README",
        (
            "assets/readme-banner.png",
            "Android CI",
            "Latest release",
            "https://juicr.app",
            "https://www.dmca.com/r/46zzk6z",
            "https://ko-fi.com/xc3fff0e",
            "<h2 align=\"center\">Features</h2>",
            "<h2 align=\"center\">Screenshots</h2>",
            "assets/screenshots/home.png",
            "assets/screenshots/discovery.png",
            "assets/screenshots/library.png",
            "assets/screenshots/details.png",
            "assets/screenshots/add-ons.png",
            "assets/screenshots/metrics.png",
            "<h2 align=\"center\">How To Use</h2>",
            "<h2 align=\"center\">How It Fits Together</h2>",
            "<h2 align=\"center\">Project Structure</h2>",
            "Diagnostics, logs, app UI, exported reports",
        ),
    ),
    (
        ".github/workflows/android-ci.yml",
        "Android CI workflow",
        (
            "name: Android CI",
            "- dev",
            "flutter pub get",
            "flutter analyze --no-fatal-infos --no-fatal-warnings lib",
            "Juicr Android release build",
            "flutter build apk --release",
            "working-directory: Juicr Android",
            "working-directory: Juicr TV",
        ),
    ),
    (
        ".github/PULL_REQUEST_TEMPLATE.md",
        "PR template",
        (
            "## What changed",
            "Juicr Android",
            "Juicr TV",
            "Juicr Web",
            "## Verification",
        ),
    ),
    (
        "CONTRIBUTING.md",
        "contributing branch flow",
        (
            "`dev` is the integration branch",
            "Dependabot opens dependency updates against `dev`",
            "Merge `dev` into `main`",
        ),
    ),
    (
        "RELEASES.md",
        "release branch flow",
        (
            "Merge the verified `dev` branch into `main`",
            "`main` contains the verified `dev` changes",
        ),
    ),
    (
        ".github/ISSUE_TEMPLATE/bug_report.md",
        "bug report template",
        (
            "name: Bug report",
            "App lane",
            "Diagnostics and logs must stay redacted.",
        ),
    ),
    (
        ".github/ISSUE_TEMPLATE/feature_request.md",
        "feature request template",
        (
            "name: Feature request",
            "Juicr",
            "Privacy and safety impact",
        ),
    ),
    (
        ".github/ISSUE_TEMPLATE/config.yml",
        "issue template config",
        (
            "blank_issues_enabled: false",
            "Juicr support",
        ),
    ),
    (
        "CODEOWNERS",
        "CODEOWNERS placeholder",
        (
            "Team Juicr",
            "@Team-Juicr/",
        ),
    ),
    (
        ".github/FUNDING.yml",
        "Funding config",
        (
            "ko_fi: xc3fff0e",
        ),
    ),
)

FORBIDDEN: tuple[tuple[str, str, tuple[str, ...]], ...] = (
    (
        "README.md",
        "README",
        (
            "<h2 align=\"center\">Visual Identity</h2>",
            "Juicr%20Web/icon-512.png",
            "<p align=\"center\"><em>Juicr is an entertainment companion",
            "crowdin",
            "Crowdin",
            "localization",
            "Localization",
            "assets/screenshots/login.png",
            "Juicr Login screen",
        ),
    ),
)


def main() -> int:
    failures: list[str] = []
    for relative_path, label, needles in CHECKS:
        path = ROOT / relative_path
        if not path.exists():
            failures.append(f"{label} is missing: {relative_path}")
            continue
        text = path.read_text(encoding="utf-8")
        for needle in needles:
            if needle not in text:
                failures.append(f"{label} missing expected text: {needle}")

    for relative_path, label, needles in FORBIDDEN:
        path = ROOT / relative_path
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        for needle in needles:
            if needle in text:
                failures.append(f"{label} contains removed README icon marker: {needle}")

    release_doctor = ROOT / "Scripts" / "android_release_workflow_doctor.py"
    if not release_doctor.exists():
        failures.append("release workflow doctor is missing")

    banner = ROOT / "assets" / "readme-banner.png"
    if not banner.exists():
        failures.append("README banner image is missing: assets/readme-banner.png")

    for name in (
        "home.png",
        "discovery.png",
        "library.png",
        "details.png",
        "add-ons.png",
        "metrics.png",
    ):
        screenshot = ROOT / "assets" / "screenshots" / name
        if not screenshot.exists():
            failures.append(f"README screenshot is missing: assets/screenshots/{name}")

    if failures:
        print("repo setup doctor failed:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("repo setup doctor passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
