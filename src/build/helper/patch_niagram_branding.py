#!/usr/bin/env python3
"""Patch decoded Niagram APK resources to use Telegram Premium Star branding.

Updates AndroidManifest.xml default launcher icons to @mipmap/icon_3_launcher
and @mipmap/icon_3_launcher_round, sets AppName to Telegram, and replaces
Niagram/Neko/stock notification drawables with the monochrome white Premium Star.
"""

import argparse
import pathlib
import re
import shutil
import sys

TARGET_ICON = "@mipmap/icon_3_launcher"
TARGET_ROUND_ICON = "@mipmap/icon_3_launcher_round"
DENSITIES = ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")
NOTIF_BASENAMES = ("niagramx_notification", "neko_notification", "notification")


def patch_manifest(manifest_path: pathlib.Path) -> None:
    """Replace default launcher icon references in AndroidManifest.xml."""
    text = manifest_path.read_text(encoding="utf-8")
    app_match = re.search(r"<application\b[^>]*>", text, re.DOTALL)
    if not app_match:
        raise RuntimeError("Could not find <application> tag in AndroidManifest.xml")

    app_tag = app_match.group(0)
    icon_match = re.search(r'android:icon="(@mipmap/[^"]+)"', app_tag)
    round_match = re.search(r'android:roundIcon="(@mipmap/[^"]+)"', app_tag)

    replacements = 0
    for old_val, new_val, label in (
        (icon_match.group(1) if icon_match else None, TARGET_ICON, "icon"),
        (round_match.group(1) if round_match else None, TARGET_ROUND_ICON, "roundIcon"),
    ):
        if old_val and old_val != new_val:
            old_quoted = f'"{old_val}"'
            new_quoted = f'"{new_val}"'
            count = text.count(old_quoted)
            text = text.replace(old_quoted, new_quoted)
            replacements += count
            print(f"[+] Manifest {label}: {old_val} -> {new_val} ({count} occurrences)")

    if replacements == 0 and TARGET_ICON not in app_tag:
        raise RuntimeError("Failed to detect or replace default launcher icon in AndroidManifest.xml")

    manifest_path.write_text(text, encoding="utf-8")


def patch_app_name(res_root: pathlib.Path, app_name: str) -> None:
    """Update AppName string in res/values/strings.xml."""
    strings_path = res_root / "values" / "strings.xml"
    if not strings_path.is_file():
        raise RuntimeError(f"Missing strings.xml at {strings_path}")

    text = strings_path.read_text(encoding="utf-8")
    updated, count = re.subn(
        r'(<string\s+name="AppName">)[^<]*(</string>)',
        rf"\g<1>{app_name}\g<2>",
        text,
    )
    if count == 0:
        raise RuntimeError("Could not find <string name=\"AppName\"> in strings.xml")

    strings_path.write_text(updated, encoding="utf-8")
    print(f"[+] Updated AppName -> {app_name}")


def patch_notification_icons(res_root: pathlib.Path, icons_dir: pathlib.Path) -> None:
    """Replace notification bar icon drawables with monochrome Premium Star assets."""
    replaced = 0
    for density in DENSITIES:
        drawable_dir = res_root / f"drawable-{density}"
        if not drawable_dir.is_dir():
            continue
        for base in NOTIF_BASENAMES:
            for ext in ("png", "webp"):
                target = drawable_dir / f"{base}.{ext}"
                if target.is_file():
                    src = icons_dir / f"star_{density}.{ext}"
                    if not src.is_file():
                        raise RuntimeError(f"Missing replacement icon: {src}")
                    shutil.copy2(src, target)
                    replaced += 1

    if replaced == 0:
        raise RuntimeError(f"No notification drawables found to replace under {res_root}")
    print(f"[+] Replaced {replaced} notification drawable asset(s) with Premium Star")


def main() -> int:
    parser = argparse.ArgumentParser(description="Patch decoded Niagram APK resources.")
    parser.add_argument("decoded_dir", type=pathlib.Path, help="APKEditor XML decoded directory")
    parser.add_argument("icons_dir", type=pathlib.Path, help="Directory with star_<density>.{png,webp}")
    parser.add_argument("--app-name", default="Telegram", help="Target launcher app name")
    args = parser.parse_args()

    manifest_path = args.decoded_dir / "AndroidManifest.xml"
    if not manifest_path.is_file():
        raise RuntimeError(f"AndroidManifest.xml not found in {args.decoded_dir}")

    res_roots = sorted((args.decoded_dir / "resources").glob("*/res"))
    if not res_roots:
        raise RuntimeError(f"No resources/*/res directory found in {args.decoded_dir}")

    patch_manifest(manifest_path)
    for res_root in res_roots:
        if (res_root / "values" / "strings.xml").is_file():
            patch_app_name(res_root, args.app_name)
        patch_notification_icons(res_root, args.icons_dir)

    return 0


if __name__ == "__main__":
    sys.exit(main())
