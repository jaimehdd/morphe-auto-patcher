#!/usr/bin/env python3
"""Patch decoded Niagram APK resources to use Telegram Premium Star branding.

Updates AndroidManifest.xml default launcher icons to @mipmap/icon_3_launcher
and @mipmap/icon_3_launcher_round, overwrites the underlying default launcher
icon resources (used by LaunchActivity TaskDescription in Recents), sets AppName
to Telegram, and replaces Niagram/Neko/stock notification drawables with the
monochrome white Premium Star.
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
PREMIUM_STAR_PATH = (
    "M25.0339 38.8535L16.4947 44.2223C15.6075 44.7802 14.4361 44.5131 13.8782 43.6258"
    "C13.6038 43.1893 13.5188 42.6601 13.6426 42.1598L15.0264 36.5704"
    "C15.4811 34.7334 16.7041 33.1809 18.3835 32.3088L26.359 28.1671"
    "C26.7894 27.9436 26.9572 27.4137 26.7337 26.9833C26.5595 26.6481 26.1903 26.4617 25.8172 26.5208"
    "L16.9312 27.9261C14.8088 28.2617 12.6463 27.6475 11.0173 26.2465L7.5978 23.3054"
    "C6.8032 22.622 6.71306 21.4239 7.39646 20.6293C7.7225 20.2503 8.18486 20.0153 8.68322 19.9753"
    "L18.8056 19.1622C19.5221 19.1046 20.1443 18.6473 20.4134 17.9809L24.2843 8.39097"
    "C24.6766 7.41912 25.7823 6.94929 26.7542 7.34157C27.232 7.53443 27.6108 7.91321 27.8037 8.39097"
    "L31.6745 17.9809C31.9435 18.6473 32.5659 19.1046 33.2822 19.1622L43.4582 19.9795"
    "C44.5029 20.0634 45.2817 20.9784 45.1978 22.023C45.1582 22.5159 44.9279 22.9737 44.5559 23.2992"
    "L36.7229 30.1527C36.1947 30.6149 35.9647 31.3308 36.125 32.0141L38.5201 42.2261"
    "C38.7594 43.2465 38.1263 44.2677 37.106 44.507C36.6119 44.6228 36.0921 44.536 35.6626 44.2659"
    "L27.054 38.8535C26.4366 38.4654 25.6513 38.4654 25.0339 38.8535Z"
)


def patch_manifest(manifest_path: pathlib.Path) -> tuple[str | None, str | None]:
    """Replace default launcher icon references in AndroidManifest.xml.

    Returns the detected (default_icon_name, default_round_icon_name) without
    the '@mipmap/' prefix so underlying resources can also be replaced.
    """
    text = manifest_path.read_text(encoding="utf-8")
    app_match = re.search(r"<application\b[^>]*>", text, re.DOTALL)
    if not app_match:
        raise RuntimeError("Could not find <application> tag in AndroidManifest.xml")

    app_tag = app_match.group(0)
    icon_match = re.search(r'android:icon="(@mipmap/[^"]+)"', app_tag)
    round_match = re.search(r'android:roundIcon="(@mipmap/[^"]+)"', app_tag)

    old_icon = icon_match.group(1) if icon_match else None
    old_round = round_match.group(1) if round_match else None

    replacements = 0
    for old_val, new_val, label in (
        (old_icon, TARGET_ICON, "icon"),
        (old_round, TARGET_ROUND_ICON, "roundIcon"),
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
    return (
        old_icon.removeprefix("@mipmap/") if old_icon else None,
        old_round.removeprefix("@mipmap/") if old_round else None,
    )


def _replace_mipmap_asset(
    res_root: pathlib.Path, target_name: str, source_png: pathlib.Path, density: str
) -> bool:
    """Replace a raster mipmap asset (png or webp) with source_png."""
    mdir = res_root / f"mipmap-{density}"
    if not mdir.is_dir() or not source_png.is_file():
        return False
    existed = False
    for ext in ("webp", "png"):
        candidate = mdir / f"{target_name}.{ext}"
        if candidate.is_file():
            candidate.unlink()
            existed = True
    if not existed:
        return False
    shutil.copy2(source_png, mdir / f"{target_name}.png")
    return True


def patch_default_launcher_resources(
    res_root: pathlib.Path, default_icon: str | None, default_round: str | None
) -> None:
    """Overwrite the default launcher icon resources (e.g. icon_9_launcher*)
    with Telegram Premium Star assets so TaskDescription (Recents) and in-app
    LauncherIconController.DEFAULT also render the Premium Star.
    """
    anydpi = res_root / "mipmap-anydpi-v26"
    replaced = 0

    if default_icon and default_icon != "icon_3_launcher":
        src_xml = anydpi / "icon_3_launcher.xml"
        dst_xml = anydpi / f"{default_icon}.xml"
        if src_xml.is_file() and dst_xml.is_file():
            shutil.copy2(src_xml, dst_xml)
            replaced += 1

        src_bg = res_root / "drawable" / "icon_3_background_sa.xml"
        if src_bg.is_file():
            for density in DENSITIES:
                for ext in ("webp", "png"):
                    p = res_root / f"mipmap-{density}" / f"{default_icon}_background.{ext}"
                    if p.is_file():
                        p.unlink()
                        replaced += 1
            if anydpi.is_dir():
                shutil.copy2(src_bg, anydpi / f"{default_icon}_background.xml")
                replaced += 1

        for density in DENSITIES:
            mdir = res_root / f"mipmap-{density}"
            if _replace_mipmap_asset(res_root, default_icon, mdir / "icon_3_launcher.png", density):
                replaced += 1
            if _replace_mipmap_asset(
                res_root, f"{default_icon}_foreground", mdir / "icon_3_foreground.png", density
            ):
                replaced += 1

        prefix = default_icon.removesuffix("_launcher")
        mono_xml = res_root / "drawable" / f"{prefix}_monochrome.xml"
        if mono_xml.is_file():
            mono_xml.write_text(
                "<?xml version='1.0' encoding='utf-8' ?>\n"
                '<vector android:height="432.0dp"\n'
                '        android:width="432.0dp"\n'
                '        android:viewportWidth="432.0"\n'
                '        android:viewportHeight="432.0" xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '  <group android:translateX="119.8"\n'
                '         android:translateY="114.8"\n'
                '         android:scaleX="3.7"\n'
                '         android:scaleY="3.7">\n'
                '    <path android:fillColor="#000000"\n'
                f'          android:pathData="{PREMIUM_STAR_PATH}" />\n'
                "  </group>\n"
                "</vector>\n",
                encoding="utf-8",
            )
            replaced += 1

    if default_round and default_round != "icon_3_launcher_round":
        src_rxml = anydpi / "icon_3_launcher_round.xml"
        dst_rxml = anydpi / f"{default_round}.xml"
        if src_rxml.is_file() and dst_rxml.is_file():
            shutil.copy2(src_rxml, dst_rxml)
            replaced += 1
        for density in DENSITIES:
            mdir = res_root / f"mipmap-{density}"
            if _replace_mipmap_asset(
                res_root, default_round, mdir / "icon_3_launcher_round.png", density
            ):
                replaced += 1

    print(f"[+] Replaced {replaced} default launcher / Recents resource asset(s) with Premium Star")


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
        raise RuntimeError('Could not find <string name="AppName"> in strings.xml')

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

    default_icon, default_round = patch_manifest(manifest_path)
    for res_root in res_roots:
        patch_default_launcher_resources(res_root, default_icon, default_round)
        if (res_root / "values" / "strings.xml").is_file():
            patch_app_name(res_root, args.app_name)
        patch_notification_icons(res_root, args.icons_dir)

    return 0


if __name__ == "__main__":
    sys.exit(main())
