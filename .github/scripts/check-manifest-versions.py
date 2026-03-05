#!/usr/bin/env python3
"""
Checks direct-download app versions and validates winget/PSGallery IDs.

Outputs:
  - Prints status for every app checked
  - Writes 'manifest_changed=true' to $GITHUB_OUTPUT if manifest.json was updated
  - Exits 0 on success (warnings don't fail the build)
"""

import json
import os
import re
import sys
import time
from datetime import date
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen

try:
    from jsonpath_ng.ext import parse as jsonpath_parse
    HAS_JSONPATH = True
except ImportError:
    HAS_JSONPATH = False

REPO_ROOT = Path(__file__).parent.parent.parent
MANIFEST_PATH = REPO_ROOT / "manifest.json"
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")

# Delay between GitHub API calls to stay well within rate limits
GITHUB_API_DELAY = 0.15


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def _make_headers(extra=None):
    headers = {"User-Agent": "Loadout-CI/1.0", "Accept": "application/json"}
    if GITHUB_TOKEN:
        headers["Authorization"] = f"Bearer {GITHUB_TOKEN}"
    if extra:
        headers.update(extra)
    return headers


def fetch(url, headers=None, timeout=20):
    """Return (body_str, status_code). Returns (None, status) on error."""
    req = Request(url, headers=headers or {"User-Agent": "Loadout-CI/1.0"})
    try:
        with urlopen(req, timeout=timeout) as r:
            return r.read().decode("utf-8", errors="replace"), r.status
    except URLError as e:
        code = getattr(e, "code", None)
        return None, code
    except Exception as e:
        print(f"  fetch error: {e}", flush=True)
        return None, None


# ---------------------------------------------------------------------------
# Version extraction
# ---------------------------------------------------------------------------

def extract_version(text, method, expression):
    if not method or not expression:
        return None

    if method == "json-path":
        if not HAS_JSONPATH:
            print("  SKIP json-path: jsonpath-ng not installed", flush=True)
            return None
        try:
            data = json.loads(text)
            matches = jsonpath_parse(expression).find(data)
            return str(matches[0].value) if matches else None
        except Exception as e:
            print(f"  json-path error: {e}", flush=True)
            return None

    if method in ("regex", "html-regex"):
        m = re.search(expression, text, re.DOTALL)
        return m.group(1) if m else None

    if method == "github-release":
        try:
            data = json.loads(text)
            tag = data.get("tag_name", "")
            return tag.lstrip("v") if tag else None
        except Exception:
            return None

    print(f"  Unknown versionCheckMethod: {method}", flush=True)
    return None


# ---------------------------------------------------------------------------
# Direct-download version checks
# ---------------------------------------------------------------------------

def check_direct_downloads(apps):
    """
    For each app with directDownload.versionCheckUrl:
      - Fetches the URL, extracts the version
      - If the app has a urlTemplate, computes the new URL and updates manifest if changed

    Returns (changed: bool, warnings: list[str])
    """
    changed = False
    warnings = []

    candidates = [a for a in apps if a.get("directDownload", {}).get("versionCheckUrl")]
    if not candidates:
        print("  (no apps with versionCheckUrl)", flush=True)
        return False, []

    for app in candidates:
        app_id = app["id"]
        dd = app["directDownload"]
        url = dd["versionCheckUrl"]
        method = dd.get("versionCheckMethod", "")
        expression = dd.get("versionCheckExpression", "")

        print(f"  {app_id}: fetching {url[:80]}...", flush=True)
        text, status = fetch(url)
        if text is None:
            warnings.append(f"{app_id}: versionCheckUrl fetch failed (HTTP {status})")
            continue

        version = extract_version(text, method, expression)
        if version is None:
            warnings.append(
                f"{app_id}: could not extract version (method={method}, expr={expression})"
            )
            continue

        url_template = dd.get("urlTemplate", "")
        if url_template:
            new_url = url_template.replace("{version}", version)
            current_url = dd.get("url", "")
            if new_url != current_url:
                print(f"  {app_id}: version {version} -> updating URL", flush=True)
                dd["url"] = new_url
                changed = True
            else:
                print(f"  {app_id}: up to date ({version})", flush=True)
        else:
            print(f"  {app_id}: available version = {version} (static URL, no auto-update)", flush=True)

    return changed, warnings


# ---------------------------------------------------------------------------
# Winget ID validation
# ---------------------------------------------------------------------------

def winget_id_to_path(winget_id):
    """
    Convert winget IDs to winget-pkgs manifest paths.
    Example:
      Microsoft.VisualStudioCode -> manifests/m/Microsoft/VisualStudioCode
      Python.Python.3            -> manifests/p/Python/Python/3
    """
    parts = winget_id.split(".")
    if len(parts) < 2:
        raise ValueError("wingetId must contain at least one dot")
    publisher = parts[0]
    package = "/".join(parts[1:])
    first = publisher[0].lower()
    return f"manifests/{first}/{publisher}/{package}"


def validate_winget_ids(apps):
    warnings = []
    candidates = [a for a in apps if a.get("wingetId")]
    if not candidates:
        print("  (no winget apps)", flush=True)
        return []

    for app in candidates:
        app_id = app["id"]
        winget_id = app["wingetId"]

        try:
            pkg_path = winget_id_to_path(winget_id)
        except (ValueError, IndexError):
            warnings.append(f"{app_id}: malformed wingetId '{winget_id}'")
            continue

        url = f"https://api.github.com/repos/microsoft/winget-pkgs/contents/{pkg_path}"
        _, status = fetch(url, headers=_make_headers())
        time.sleep(GITHUB_API_DELAY)

        if status == 200:
            print(f"  {app_id} ({winget_id}): OK", flush=True)
        elif status == 404:
            warnings.append(f"{app_id}: wingetId '{winget_id}' not found in winget-pkgs")
            print(f"  {app_id} ({winget_id}): NOT FOUND", flush=True)
        elif status == 403:
            print(f"  {app_id} ({winget_id}): rate limited -- skipping remainder", flush=True)
            break
        else:
            print(f"  {app_id} ({winget_id}): HTTP {status} -- skipping", flush=True)

    return warnings


# ---------------------------------------------------------------------------
# PSGallery module validation
# ---------------------------------------------------------------------------

def validate_psgallery_ids(apps):
    warnings = []
    candidates = [a for a in apps if a.get("psGalleryModule")]
    if not candidates:
        print("  (no PSGallery modules)", flush=True)
        return []

    for app in candidates:
        app_id = app["id"]
        module_id = app["psGalleryModule"]
        url = (
            f"https://www.powershellgallery.com/api/v2/Packages"
            f"?$filter=Id eq '{module_id}' and IsLatestVersion&$select=Id,Version&$top=1"
        )
        text, status = fetch(url, headers={"User-Agent": "Loadout-CI/1.0", "Accept": "application/atom+xml"})
        time.sleep(0.2)

        if status != 200 or text is None:
            print(f"  {app_id} ({module_id}): HTTP {status} -- skipping", flush=True)
            continue

        if "<entry>" in text:
            print(f"  {app_id} ({module_id}): OK", flush=True)
        else:
            warnings.append(f"{app_id}: psGalleryModule '{module_id}' not found in PSGallery")
            print(f"  {app_id} ({module_id}): NOT FOUND", flush=True)

    return warnings


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def set_github_output(key, value):
    output_file = os.environ.get("GITHUB_OUTPUT", "")
    if output_file:
        with open(output_file, "a", encoding="utf-8") as f:
            f.write(f"{key}={value}\n")
    else:
        print(f"[output] {key}={value}", flush=True)


def main():
    with open(MANIFEST_PATH, encoding="utf-8") as f:
        manifest = json.load(f)

    apps = manifest["apps"]
    all_warnings = []
    changed = False

    print("=== Direct Download Version Checks ===", flush=True)
    dd_changed, dd_warnings = check_direct_downloads(apps)
    all_warnings.extend(dd_warnings)
    changed = changed or dd_changed

    print("\n=== Winget ID Validation ===", flush=True)
    winget_warnings = validate_winget_ids(apps)
    all_warnings.extend(winget_warnings)

    print("\n=== PSGallery Module Validation ===", flush=True)
    ps_warnings = validate_psgallery_ids(apps)
    all_warnings.extend(ps_warnings)

    if changed:
        manifest["lastUpdated"] = date.today().isoformat()
        with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2)
            f.write("\n")
        print("\nManifest updated.", flush=True)
        set_github_output("manifest_changed", "true")
    else:
        print("\nNo manifest changes.", flush=True)
        set_github_output("manifest_changed", "false")

    if all_warnings:
        print(f"\n=== Warnings ({len(all_warnings)}) ===", flush=True)
        for w in all_warnings:
            print(f"  WARN: {w}", flush=True)

    # Warnings don't fail the build -- they are surfaced in the run log for human review
    return 0


if __name__ == "__main__":
    sys.exit(main())
