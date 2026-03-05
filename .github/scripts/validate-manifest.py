#!/usr/bin/env python3
"""Validates manifest.json against the JSON schema and checks structural integrity."""

import json
import sys
from pathlib import Path

try:
    import jsonschema
except ImportError:
    print("ERROR: jsonschema not installed. Run: pip install jsonschema", file=sys.stderr)
    sys.exit(2)

REPO_ROOT = Path(__file__).parent.parent.parent
MANIFEST_PATH = REPO_ROOT / "manifest.json"
SCHEMA_PATH = REPO_ROOT / ".github" / "schemas" / "manifest.schema.json"


def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        print(f"ERROR: {path.name} is not valid JSON: {e}", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print(f"ERROR: File not found: {path}", file=sys.stderr)
        sys.exit(1)


def validate_schema(manifest, schema):
    try:
        jsonschema.validate(manifest, schema)
        return []
    except jsonschema.ValidationError as e:
        path_str = " -> ".join(str(p) for p in e.absolute_path) or "(root)"
        return [f"Schema violation at '{path_str}': {e.message}"]
    except jsonschema.SchemaError as e:
        return [f"Schema itself is invalid: {e.message}"]


def check_duplicate_ids(apps):
    errors = []
    seen = {}
    for i, app in enumerate(apps):
        app_id = app.get("id", f"<missing id at index {i}>")
        if app_id in seen:
            errors.append(
                f"Duplicate app ID '{app_id}' at index {i} (first seen at {seen[app_id]})"
            )
        else:
            seen[app_id] = i
    return errors


def check_dependency_refs(apps):
    errors = []
    all_ids = {app.get("id") for app in apps if "id" in app}
    for app in apps:
        app_id = app.get("id", "?")
        for dep in app.get("dependencies", []):
            if dep not in all_ids:
                errors.append(
                    f"App '{app_id}' has dependency '{dep}' which does not exist in the manifest"
                )
    return errors


def check_install_method_present(apps):
    """Every app should have at least one install method field."""
    install_fields = {
        "wingetId", "psGalleryModule", "vscodeExtensionId", "chocolateyId",
        "directDownload", "wslDistroName", "windowsFeatureName",
        "registryPath", "postInstallCommands", "postInstallOnly",
    }
    warnings = []
    for app in apps:
        app_id = app.get("id", "?")
        if not any(field in app for field in install_fields):
            warnings.append(f"WARN: App '{app_id}' has no recognizable install method field")
    return warnings


def main():
    print(f"Loading schema: {SCHEMA_PATH.relative_to(REPO_ROOT)}")
    print(f"Validating:     {MANIFEST_PATH.relative_to(REPO_ROOT)}")
    print()

    schema = load_json(SCHEMA_PATH)
    manifest = load_json(MANIFEST_PATH)
    apps = manifest.get("apps", [])

    all_errors = []

    # 1. JSON schema validation
    print("--- Schema validation ---")
    schema_errors = validate_schema(manifest, schema)
    if schema_errors:
        all_errors.extend(schema_errors)
        for e in schema_errors:
            print(f"  ERROR: {e}", file=sys.stderr)
    else:
        print(f"  OK")

    # 2. Duplicate IDs
    print("--- Duplicate ID check ---")
    dupe_errors = check_duplicate_ids(apps)
    if dupe_errors:
        all_errors.extend(dupe_errors)
        for e in dupe_errors:
            print(f"  ERROR: {e}", file=sys.stderr)
    else:
        print(f"  OK ({len(apps)} unique IDs)")

    # 3. Dependency references
    print("--- Dependency reference check ---")
    dep_errors = check_dependency_refs(apps)
    if dep_errors:
        all_errors.extend(dep_errors)
        for e in dep_errors:
            print(f"  ERROR: {e}", file=sys.stderr)
    else:
        print(f"  OK")

    # 4. Install method presence (warnings only)
    print("--- Install method check ---")
    method_warnings = check_install_method_present(apps)
    if method_warnings:
        for w in method_warnings:
            print(f"  {w}")
    else:
        print(f"  OK")

    print()
    if all_errors:
        print(f"FAILED: {len(all_errors)} error(s) found.", file=sys.stderr)
        sys.exit(1)
    else:
        print(f"PASSED: manifest.json is valid ({len(apps)} apps).")
        sys.exit(0)


if __name__ == "__main__":
    main()
