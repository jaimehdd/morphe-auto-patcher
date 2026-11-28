#!/usr/bin/env python3
"""Parallel, version-aware CI checker driven by src/targets.json.

Replaces sequential timestamp-based checks with:
  1. Concurrent GitHub Releases API fetching (stdlib only).
  2. Exact patch-version comparison against existing release tags & bodies.
  3. Optional lazy .mpp pre-check for OMIT_PATCH_VERSION multi-app bundles:
     if the target app's compatible version is unchanged, stamps
     `<!-- checked_patch_version: ... -->` on the existing release and skips
     dispatching a matrix job altogether.
  4. Single-pass extraction of Morphe experimental support versions.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

API_BASE = "https://api.github.com"
DEFAULT_ASSET_RE = re.compile(r"(\.jar|\.rvp|\.mpp|\.apk)$")
CHECKED_MARKER_RE = re.compile(r"<!--\s*checked_patch_version:\s*([^\s>]+)\s*-->")
BODY_PATCH_VER_RE = re.compile(r"\*\*Patch Version\*\*:\s*`([^`]+)`")


def _headers(token: str | None) -> dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "morphe-auto-patcher-ci",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def gh_request(
    url: str,
    token: str | None = None,
    method: str = "GET",
    payload: dict[str, Any] | None = None,
    retries: int = 3,
) -> Any:
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    headers = _headers(token)
    if data is not None:
        headers["Content-Type"] = "application/json"

    last_err: Exception | None = None
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                raw = resp.read().decode("utf-8")
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as exc:
            last_err = exc
            if exc.code in (403, 404, 422):
                raise
            time.sleep(attempt * 2)
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            time.sleep(attempt * 2)
    raise RuntimeError(f"GitHub API request failed for {url}: {last_err}")


def download_file(url: str, dest: Path, token: str | None = None, retries: int = 3) -> None:
    headers = {"User-Agent": "morphe-auto-patcher-ci"}
    if token and "api.github.com" in url:
        headers["Authorization"] = f"Bearer {token}"
    last_err: Exception | None = None
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp, dest.open("wb") as out:
                shutil.copyfileobj(resp, out)
            return
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            time.sleep(attempt * 2)
    raise RuntimeError(f"Failed to download {url}: {last_err}")


def fetch_releases(repo: str, token: str | None, per_page: int = 20) -> list[dict[str, Any]]:
    url = f"{API_BASE}/repos/{repo}/releases?per_page={per_page}"
    data = gh_request(url, token=token)
    return data if isinstance(data, list) else []


def select_release(releases: list[dict[str, Any]], tag_mode: str) -> dict[str, Any] | None:
    if not releases:
        return None
    if tag_mode == "latest":
        for rel in releases:
            if not rel.get("draft") and not rel.get("prerelease"):
                return rel
        return None
    if tag_mode == "prerelease":
        for rel in releases:
            if not rel.get("draft"):
                return rel
        return None
    if tag_mode == "all":
        for rel in releases:
            if not rel.get("draft"):
                return rel
        return None
    for rel in releases:
        if rel.get("tag_name") == tag_mode:
            return rel
    return None


def extract_patch_version_from_asset(asset_name: str, tag_name: str = "") -> str:
    name = asset_name[:-9] if asset_name.endswith(".disabled") else asset_name
    if name.endswith(".jar") and "revanced-patches-" in name:
        return name.split("revanced-patches-", 1)[1][:-4]
    if name.endswith(".rvp") and "patches-" in name:
        if "revanced-patches-" in name:
            return name.split("revanced-patches-", 1)[1][:-4]
        return name.split("patches-", 1)[1][:-4]
    if name.endswith(".mpp") and "patches-" in name:
        return name.split("patches-", 1)[1][:-4]
    if name.endswith(".mpp"):
        m = re.search(r"([0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.]+)?)\.mpp$", name)
        if m:
            return m.group(1)
    if name.endswith(".apk") and "NexAlloy-" in name:
        m = re.search(r"v?([0-9]+(?:\.[0-9]+)+)\.apk$", name)
        if m:
            return m.group(1)
    if tag_name:
        return tag_name.lstrip("v")
    return ""


def find_source_asset(
    release: dict[str, Any], tag_mode: str, asset_regex: str | None = None
) -> dict[str, Any] | None:
    pat = re.compile(asset_regex) if asset_regex else DEFAULT_ASSET_RE
    for asset in release.get("assets", []):
        name = asset.get("name", "")
        if name.endswith(".asc"):
            continue
        if tag_mode == "latest" and "dev" in name and not asset_regex:
            continue
        if pat.search(name):
            return asset
    return None


def version_key(ver: str) -> tuple[Any, ...]:
    parts = re.split(r"([0-9]+)", ver)
    key: list[Any] = []
    for p in parts:
        if p.isdigit():
            key.append((0, int(p)))
        elif p:
            key.append((1, p))
    return tuple(key)


def extract_experimental_versions(
    releases: list[dict[str, Any]], release_channel: str = "stable"
) -> dict[str, str]:
    patterns = {
        "youtube_experimental_support": re.compile(
            r"YouTube(?! Music).*experimental(?: support)?.*?([0-9]+(?:\.[0-9]+)+)(?![-\w.])"
        ),
        "youtube_music_experimental_support": re.compile(
            r"YouTube Music.*experimental(?: support)?.*?([0-9]+(?:\.[0-9]+)+)(?![-\w.])"
        ),
        "reddit_experimental_support": re.compile(
            r"Reddit.*experimental(?: support)?.*?([0-9]+(?:\.[0-9]+)+)(?![-\w.])"
        ),
    }
    found: dict[str, str] = {k: "" for k in patterns}

    for rel in releases:
        if rel.get("draft"):
            continue
        tag = rel.get("tag_name", "")
        prerelease = bool(rel.get("prerelease"))
        if release_channel == "stable" and (prerelease or "-dev." in tag):
            continue
        body = rel.get("body") or ""
        for key, pat in patterns.items():
            if found[key]:
                continue
            matches = pat.findall(body)
            if matches:
                found[key] = max(matches, key=version_key)
        if all(found.values()):
            break

    return found


def find_existing_release(
    own_releases: list[dict[str, Any]], asset_regex: str
) -> dict[str, Any] | None:
    pat = re.compile(asset_regex)
    for rel in own_releases:
        for asset in rel.get("assets", []):
            if pat.search(asset.get("name", "")):
                return rel
    return None


def release_has_apk_for_tag(own_releases: list[dict[str, Any]], tag: str) -> dict[str, Any] | None:
    for rel in own_releases:
        if rel.get("tag_name") == tag:
            if any(a.get("name", "").endswith(".apk") for a in rel.get("assets", [])):
                return rel
    return None


def extract_recorded_versions(release: dict[str, Any]) -> tuple[str, str]:
    body = release.get("body") or ""
    checked_m = CHECKED_MARKER_RE.search(body)
    built_m = BODY_PATCH_VER_RE.search(body)
    checked = checked_m.group(1).strip() if checked_m else ""
    built = built_m.group(1).strip() if built_m else ""
    if built == "unknown":
        built = ""
    return checked, built


def stamp_checked_patch_version(
    own_repo: str, release: dict[str, Any], patch_version: str, token: str | None
) -> bool:
    if not token or not own_repo or not patch_version:
        return False
    rel_id = release.get("id")
    if not rel_id:
        return False
    body = release.get("body") or ""
    marker = f"<!-- checked_patch_version: {patch_version} -->"
    if CHECKED_MARKER_RE.search(body):
        new_body = CHECKED_MARKER_RE.sub(marker, body)
    else:
        new_body = f"{body.rstrip()}\n\n{marker}\n" if body.strip() else f"{marker}\n"
    if new_body == body:
        return True
    try:
        gh_request(
            f"{API_BASE}/repos/{own_repo}/releases/{rel_id}",
            token=token,
            method="PATCH",
            payload={"body": new_body},
        )
        release["body"] = new_body
        return True
    except Exception as exc:  # noqa: BLE001
        print(f"  [!] Failed to stamp checked_patch_version on {release.get('tag_name')}: {exc}")
        return False


def detect_compatible_version_from_mpp(
    desktop_jar: Path, mpp_path: Path, package_name: str
) -> str:
    cmd = [
        "java",
        "-jar",
        str(desktop_jar),
        "list-patches",
        "--with-packages",
        "--with-versions",
        "--patches",
        str(mpp_path),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0 or not proc.stdout:
        return ""

    versions: list[str] = []
    found_pkg = False
    in_versions = False
    for raw_line in proc.stdout.splitlines():
        if raw_line.startswith("Index:"):
            if in_versions and versions:
                break
            found_pkg = False
            in_versions = False
            continue
        if "Package name:" in raw_line:
            pkg = raw_line.split("Package name:", 1)[1].strip()
            if pkg == package_name:
                found_pkg = True
            continue
        if "Compatible versions:" in raw_line:
            if found_pkg:
                in_versions = True
            continue
        if in_versions:
            if ":" in raw_line:
                in_versions = False
                continue
            ver = raw_line.strip().lstrip("-").strip()
            if not ver:
                continue
            first = ver.split()[0]
            versions.append(first if re.match(r"^[0-9]+\.", first) else ver)

    if not versions:
        return ""
    return max(versions, key=version_key)


def tag_prefix_for(target: dict[str, Any]) -> str:
    app_name = target["app_name"]
    variant = target.get("variant", "")
    if variant.startswith("hush"):
        return f"{app_name}-hush"
    return app_name


def write_outputs(outputs: dict[str, str], github_output: str | None) -> None:
    if not github_output:
        return
    with open(github_output, "a", encoding="utf-8") as fh:
        for key, value in outputs.items():
            fh.write(f"{key}={value}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Version-aware parallel CI checker")
    parser.add_argument("--manifest", default="src/targets.json")
    parser.add_argument("--repo", default=os.environ.get("repository") or os.environ.get("GITHUB_REPOSITORY", ""))
    parser.add_argument("--mode", choices=["full", "experimental-only"], default="full")
    parser.add_argument("--release-channel", choices=["stable", "all"], default="stable")
    parser.add_argument("--precheck-mpp", action="store_true", help="Inspect .mpp bundles for omit_patch_version targets")
    parser.add_argument("--stamp-skipped", action="store_true", help="Stamp checked_patch_version on skipped releases")
    args = parser.parse_args()

    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or None
    github_output = os.environ.get("GITHUB_OUTPUT")

    manifest_path = Path(args.manifest)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    engine = manifest.get("morphe_engine", {})
    morphe_patches_repo = engine.get("patches_repo", "MorpheApp/morphe-patches")
    morphe_desktop_repo = engine.get("desktop_repo", "MorpheApp/morphe-desktop")

    if args.mode == "experimental-only":
        releases = fetch_releases(morphe_patches_repo, token, per_page=100)
        exp = extract_experimental_versions(releases, release_channel=args.release_channel)
        for k, v in exp.items():
            print(f"  {k}: {v}")
        write_outputs(exp, github_output)
        return 0

    own_repo = args.repo
    if not own_repo:
        print("[-] Missing repository name (--repo or GITHUB_REPOSITORY)", file=sys.stderr)
        return 1

    targets: list[dict[str, Any]] = manifest.get("targets", [])

    # Collect unique repos to fetch concurrently
    repo_pages: dict[str, int] = {
        own_repo: 100,
        morphe_patches_repo: 100,
        morphe_desktop_repo: 10,
    }
    for t in targets:
        for src in t.get("sources", []):
            repo_pages.setdefault(src["repo"], 20)

    releases_cache: dict[str, list[dict[str, Any]]] = {}
    errors: dict[str, str] = {}

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        future_map = {
            pool.submit(fetch_releases, repo, token, per_page): repo
            for repo, per_page in repo_pages.items()
        }
        for fut in concurrent.futures.as_completed(future_map):
            repo = future_map[fut]
            try:
                releases_cache[repo] = fut.result()
            except Exception as exc:  # noqa: BLE001
                errors[repo] = str(exc)
                releases_cache[repo] = []

    if own_repo in errors:
        print(f"[-] Failed to fetch own repository releases ({own_repo}): {errors[own_repo]}", file=sys.stderr)
        return 1

    own_releases = releases_cache[own_repo]
    exp_versions = extract_experimental_versions(
        releases_cache.get(morphe_patches_repo, []),
        release_channel=args.release_channel,
    )

    desktop_rel = select_release(releases_cache.get(morphe_desktop_repo, []), "latest")
    desktop_tag = desktop_rel.get("tag_name", "") if desktop_rel else ""

    morphe_targets: list[str] = []
    community_targets: list[str] = []

    # Lazy temp workspace for .mpp pre-check (created only if needed)
    tmpdir_obj: tempfile.TemporaryDirectory[str] | None = None
    desktop_jar_path: Path | None = None
    java_available = shutil.which("java") is not None

    def ensure_desktop_jar() -> Path | None:
        nonlocal tmpdir_obj, desktop_jar_path
        if desktop_jar_path is not None and desktop_jar_path.exists():
            return desktop_jar_path
        if not java_available or not desktop_rel:
            return None
        jar_asset = None
        for asset in desktop_rel.get("assets", []):
            if asset.get("name", "").endswith(".jar"):
                jar_asset = asset
                break
        if not jar_asset:
            return None
        if tmpdir_obj is None:
            tmpdir_obj = tempfile.TemporaryDirectory(prefix="ci_precheck_")
        dest = Path(tmpdir_obj.name) / jar_asset["name"]
        print(f"[*] Downloading {jar_asset['name']} for .mpp pre-check...")
        download_file(jar_asset["browser_download_url"], dest, token=token)
        desktop_jar_path = dest
        return desktop_jar_path

    try:
        for target in targets:
            tid = target["id"]
            org = target["org"]
            omit_patch_ver = bool(target.get("omit_patch_version", False))
            sources = target.get("sources", [])

            # Resolve upstream patch version across all sources for this target
            src_versions: list[tuple[dict[str, Any], str, dict[str, Any] | None]] = []
            source_failed = False
            for src in sources:
                srepo = src["repo"]
                if srepo in errors:
                    print(f"[!] {tid}: failed to fetch {srepo} ({errors[srepo]}), skipping")
                    source_failed = True
                    break
                ci_mode = src.get("ci_tag_mode") or src.get("tag_mode", "latest")
                rel = select_release(releases_cache.get(srepo, []), ci_mode)
                if not rel:
                    print(f"[!] {tid}: no release found for {srepo} (mode={ci_mode}), skipping")
                    source_failed = True
                    break
                asset = find_source_asset(rel, ci_mode, src.get("asset_regex"))
                if not asset:
                    print(f"[!] {tid}: no matching asset in {srepo} ({rel.get('tag_name')}), skipping")
                    source_failed = True
                    break
                if src.get("asset_regex", "").endswith("\\.apk$"):
                    ver = rel.get("tag_name", "").lstrip("v")
                else:
                    ver = extract_patch_version_from_asset(asset["name"], rel.get("tag_name", ""))
                if not ver:
                    ver = rel.get("tag_name", "").lstrip("v")
                src_versions.append((src, ver, asset))

            if source_failed or not src_versions:
                continue

            if len(src_versions) > 1 and all(s.get("version_prefix") for s, _, _ in src_versions):
                upstream_patch_ver = "-".join(f"{s['version_prefix']}{v}" for s, v, _ in src_versions)
            else:
                upstream_patch_ver = src_versions[-1][1]

            existing = find_existing_release(own_releases, target["asset_regex"])
            if not existing:
                print(f"[+] {tid}: no existing release matching '{target['asset_regex']}' -> BUILD (upstream={upstream_patch_ver})")
                (morphe_targets if org == "Morphe" else community_targets).append(tid)
                continue

            existing_tag = existing.get("tag_name", "")
            checked_ver, built_ver = extract_recorded_versions(existing)

            if upstream_patch_ver == checked_ver or upstream_patch_ver == built_ver:
                print(f"[=] {tid}: up to date (upstream={upstream_patch_ver}, release={existing_tag})")
                continue

            if not omit_patch_ver and existing_tag.endswith(f"-{upstream_patch_ver}"):
                print(f"[=] {tid}: up to date by tag (upstream={upstream_patch_ver}, release={existing_tag})")
                continue

            # Upstream has a newer patch version!
            # For omit_patch_version targets, optionally pre-check .mpp compatible version
            if omit_patch_ver and args.precheck_mpp and len(src_versions) == 1:
                _, _, mpp_asset = src_versions[0]
                if mpp_asset and mpp_asset["name"].endswith(".mpp"):
                    jar = ensure_desktop_jar()
                    if jar is not None and tmpdir_obj is not None:
                        mpp_dest = Path(tmpdir_obj.name) / f"{tid}-{mpp_asset['name']}"
                        try:
                            download_file(mpp_asset["browser_download_url"], mpp_dest, token=token)
                            compat_ver = detect_compatible_version_from_mpp(jar, mpp_dest, target["package"])
                            if compat_ver:
                                expected_tag = f"{tag_prefix_for(target)}-{compat_ver}"
                                matched_rel = release_has_apk_for_tag(own_releases, expected_tag)
                                if matched_rel is not None:
                                    print(
                                        f"[=] {tid}: upstream {upstream_patch_ver} still targets {compat_ver} "
                                        f"({expected_tag} already exists) -> SKIP"
                                    )
                                    if args.stamp_skipped:
                                        if stamp_checked_patch_version(own_repo, matched_rel, upstream_patch_ver, token):
                                            print(f"    Stamped checked_patch_version={upstream_patch_ver} on {expected_tag}")
                                    continue
                                print(
                                    f"[+] {tid}: upstream {upstream_patch_ver} targets NEW app version {compat_ver} "
                                    f"(existing={existing_tag}) -> BUILD"
                                )
                            else:
                                print(
                                    f"[+] {tid}: upstream {upstream_patch_ver} has unpinned target version "
                                    f"(recorded={checked_ver or built_ver or 'none'}) -> BUILD"
                                )
                        except Exception as exc:  # noqa: BLE001
                            print(f"[!] {tid}: .mpp pre-check failed ({exc}), falling back to BUILD")

            print(
                f"[+] {tid}: update detected (upstream={upstream_patch_ver}, "
                f"recorded={checked_ver or built_ver or 'none'}, release={existing_tag}) -> BUILD"
            )
            (morphe_targets if org == "Morphe" else community_targets).append(tid)
    finally:
        if tmpdir_obj is not None:
            tmpdir_obj.cleanup()

    morphe_json = json.dumps(morphe_targets, separators=(",", ":"))
    community_json = json.dumps(community_targets, separators=(",", ":"))

    outputs = {
        "check_morphe": "1" if morphe_targets else "0",
        "morphe_targets": morphe_json,
        "check_morphe_community": "1" if community_targets else "0",
        "community_targets": community_json,
        "morphe_desktop_tag": desktop_tag,
        **exp_versions,
    }

    print("\n=== CI Check Summary ===")
    print(f"Morphe targets ({len(morphe_targets)}): {morphe_json}")
    print(f"Community targets ({len(community_targets)}): {community_json}")
    print(f"Morphe desktop tag: {desktop_tag or 'unknown'}")
    for k, v in exp_versions.items():
        print(f"{k}: {v or 'none'}")

    write_outputs(outputs, github_output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
