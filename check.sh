#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

STRICT_MODE="${STRICT_MODE:-0}"
FAIL_ON_MISSING_OPTIONAL_TOOLS="${FAIL_ON_MISSING_OPTIONAL_TOOLS:-0}"
FAIL_ON_UNSTAGED_CHANGES="${FAIL_ON_UNSTAGED_CHANGES:-0}"
RUN_GITLEAKS="${RUN_GITLEAKS:-1}"
RUN_GIT_SECRETS_CACHED="${RUN_GIT_SECRETS_CACHED:-1}"
RUN_GIT_SECRETS_HISTORY="${RUN_GIT_SECRETS_HISTORY:-0}"
ENABLE_MARKDOWN_LINK_CHECKS="${ENABLE_MARKDOWN_LINK_CHECKS:-1}"
ENABLE_SHELLCHECK_IF_AVAILABLE="${ENABLE_SHELLCHECK_IF_AVAILABLE:-1}"

if [[ "$STRICT_MODE" == "1" ]]; then
  FAIL_ON_MISSING_OPTIONAL_TOOLS=1
  RUN_GIT_SECRETS_HISTORY=1
fi

failures=0
warnings=0

step() {
  printf '\n==> %s\n' "$1"
}

pass() {
  printf 'PASS: %s\n' "$1"
}

warn() {
  printf 'WARN: %s\n' "$1"
  warnings=$((warnings + 1))
}

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

optional_tool_missing() {
  if [[ "$FAIL_ON_MISSING_OPTIONAL_TOOLS" == "1" ]]; then
    fail "$1"
  else
    warn "$1"
  fi
}

run_required() {
  local label="$1"
  shift

  if "$@"; then
    pass "$label"
  else
    fail "$label"
  fi
}

run_optional() {
  local label="$1"
  shift

  if "$@"; then
    pass "$label"
  else
    fail "$label"
  fi
}

have_command() {
  command -v "$1" >/dev/null 2>&1
}

list_tracked_files() {
  git ls-files
}

find_powershell() {
  if have_command powershell; then
    printf 'powershell'
    return 0
  fi
  if have_command pwsh; then
    printf 'pwsh'
    return 0
  fi
  return 1
}

run_python_json_checks() {
  python3 - <<'PY'
import json
import subprocess
import sys
from pathlib import Path

files = subprocess.run(
    ["git", "ls-files", "*.json"],
    check=True,
    text=True,
    capture_output=True,
).stdout.splitlines()

for raw in files:
    path = Path(raw.strip())
    if not path.is_file():
        continue
    try:
        json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"JSON validation failed for {path}: {exc}")
        sys.exit(1)
PY
}

run_markdown_checks() {
  python3 - <<'PY'
import os
import re
import subprocess
import sys
from pathlib import Path

files = subprocess.run(
    ["git", "ls-files", "*.md"],
    check=True,
    text=True,
    capture_output=True,
).stdout.splitlines()

pattern = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
skip_prefixes = ("http://", "https://", "mailto:", "#", "tel:")
root = Path.cwd()

for raw in files:
    path = Path(raw.strip())
    if not path.is_file():
        continue
    data = path.read_bytes()
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        print(f"Markdown is not valid UTF-8: {path}: {exc}")
        sys.exit(1)
    if data and not data.endswith(b"\n"):
      print(f"Markdown file is missing a trailing newline: {path}")
      sys.exit(1)

    if os.environ.get("ENABLE_MARKDOWN_LINK_CHECKS", "1") != "1":
        continue

    for target in pattern.findall(text):
        target = target.strip()
        if not target or target.startswith(skip_prefixes):
            continue
        if target.startswith("<") and target.endswith(">"):
            target = target[1:-1].strip()
        if not target or target.startswith(skip_prefixes):
            continue
        if target.startswith("/"):
            continue
        target = target.split("#", 1)[0]
        if not target:
            continue
        resolved = (path.parent / target).resolve()
        try:
            resolved.relative_to(root)
        except ValueError:
            print(f"Markdown link escapes repository: {path}: {target}")
            sys.exit(1)
        if not resolved.exists():
            print(f"Broken Markdown link: {path}: {target}")
            sys.exit(1)
PY
}

run_staged_path_checks() {
  python3 - <<'PY'
import re
import subprocess
import sys

proc = subprocess.run(
    ["git", "diff", "--cached", "--name-only", "--diff-filter=AM"],
    check=True,
    text=True,
    capture_output=True,
)

dangerous = []
artifact_like = []
dangerous_re = re.compile(
    r"(^|/)(\.env($|\.)|.*\.pem$|.*\.key$|.*\.p12$|.*\.pfx$|.*\.kdbx$|.*:Zone\.Identifier$|.*\.local\..*|id_rsa(|\.pub)$|id_ed25519(|\.pub)$)",
    re.IGNORECASE,
)
artifact_re = re.compile(
    r"\.(zip|tar|tgz|gz|bz2|xz|7z|rar|sqlite|sqlite3|db|dump|bak|csv|tsv|parquet|png|jpg|jpeg|gif|bmp|pdf|doc|docx|xls|xlsx|ppt|pptx|mp4|mov|avi|mkv|wav|mp3)$",
    re.IGNORECASE,
)

for raw in proc.stdout.splitlines():
    path = raw.strip()
    if not path:
        continue
    if dangerous_re.search(path):
        dangerous.append(path)
    if artifact_re.search(path):
        artifact_like.append(path)

if dangerous:
    print("Suspicious staged secret-bearing or local-only paths detected:")
    for path in dangerous:
        print(f"- {path}")
    sys.exit(1)

if artifact_like:
    print("Suspicious staged artifact or export files detected:")
    for path in artifact_like:
        print(f"- {path}")
    sys.exit(1)
PY
}

run_staged_content_checks() {
  python3 - <<'PY'
import re
import subprocess
import sys

diff = subprocess.run(
    ["git", "diff", "--cached", "--unified=0", "--no-color"],
    check=True,
    text=True,
    capture_output=True,
).stdout.splitlines()

patterns = [
    ("merge marker", re.compile(r"^\+(<{7}|={7}|>{7})")),
    ("todo marker", re.compile(r"^\+\s*.*\b(TODO|FIXME|HACK|XXX)\b")),
    ("debug print", re.compile(r"^\+\s*.*\b(console\.log|print\(|dbg!|debugger;|fmt\.Println|System\.out\.println)\b")),
    ("local path", re.compile(r"^\+\s*.*(/home/|C:\\\\Users\\\\|/mnt/c/Users/)")),
    ("private key marker", re.compile(r"^\+\s*.*(BEGIN [A-Z0-9 ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})")),
]

current_file = None
skip_exts = (".md", ".txt", ".rst")
skip_files = {"check.sh"}
hits = []

for line in diff:
    if line.startswith("diff --git "):
        match = re.match(r"diff --git a/(.+) b/(.+)", line)
        current_file = match.group(2) if match else None
        continue
    if not line.startswith("+") or line.startswith("+++"):
        continue
    if current_file and (
        current_file in skip_files or current_file.endswith(skip_exts)
    ):
        continue
    for label, pattern in patterns:
        if pattern.search(line):
            hits.append((label, line[:200]))

if hits:
    print("Risky staged diff markers detected:")
    for label, line in hits[:20]:
        print(f"- {label}: {line}")
    sys.exit(1)
PY
}

run_shell_syntax_checks() {
  local shell_files=()
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    shell_files+=("$file")
  done < <(find . -path './.git' -prune -o -type f -name '*.sh' -print | sort)

  if [[ "${#shell_files[@]}" -eq 0 ]]; then
    pass "No shell scripts found"
    return 0
  fi

  local file
  for file in "${shell_files[@]}"; do
    bash -n "$file"
  done
}

run_shellcheck_if_available() {
  local shell_files=()
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    shell_files+=("$file")
  done < <(find . -path './.git' -prune -o -type f -name '*.sh' -print | sort)

  if [[ "${#shell_files[@]}" -eq 0 ]]; then
    pass "No shell scripts found for shellcheck"
    return 0
  fi

  shellcheck "${shell_files[@]}"
}

step "Checking for Windows zone metadata files"
mapfile -t zone_files < <(find . -name '*:Zone.Identifier' -type f | sort)
if [[ ${#zone_files[@]} -gt 0 ]]; then
  printf 'Zone.Identifier files detected:\n'
  printf '  %s\n' "${zone_files[@]}"
  fail "Zone.Identifier cleanup"
else
  pass "No Zone.Identifier files found"
fi

if have_command git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  step "Git hygiene"

  if [[ "$FAIL_ON_UNSTAGED_CHANGES" == "1" ]] &&
    ! git diff --quiet --ignore-submodules --; then
    fail "Working tree has unstaged changes"
  else
    pass "Unstaged change policy"
  fi

  if git diff --cached --quiet; then
    warn "No staged changes; skipping staged diff checks"
  else
    run_required "git diff --cached --check" git diff --cached --check
    run_required "staged path policy" run_staged_path_checks
    run_required "staged content markers" run_staged_content_checks
  fi
fi

step "Text and config validation"
if have_command python3; then
  run_required "JSON syntax checks" run_python_json_checks
  run_required "Markdown validation" run_markdown_checks
else
  fail "python3 is required for JSON and Markdown validation"
fi

step "Shell validation"
run_required "bash -n" run_shell_syntax_checks
if [[ "$ENABLE_SHELLCHECK_IF_AVAILABLE" == "1" ]]; then
  if have_command shellcheck; then
    run_optional "shellcheck" run_shellcheck_if_available
  else
    optional_tool_missing "shellcheck not installed; skipping shell lint"
  fi
fi

step "PowerShell validation"
if PS_CMD="$(find_powershell)"; then
  run_required "PowerShell parse check" "$PS_CMD" -NoProfile -File ./tests/parse-check.ps1
  run_required "PowerShell test suite" "$PS_CMD" -NoProfile -File ./tests/run-all-tests.ps1
else
  fail "Neither powershell nor pwsh is available on PATH"
fi

step "Manifest validation"
if have_command python3; then
  if python3 -c "import jsonschema" >/dev/null 2>&1; then
    run_required "manifest validator" python3 ./.github/scripts/validate-manifest.py
  else
    optional_tool_missing "python3 module 'jsonschema' not installed; skipping manifest validation"
  fi
fi

step "Secret scanning"
if [[ "$RUN_GITLEAKS" == "1" ]]; then
  if have_command gitleaks; then
    run_optional "gitleaks detect" gitleaks detect --source . --no-banner
  else
    optional_tool_missing "gitleaks not installed; skipping repository secret scan"
  fi
fi

if [[ "$RUN_GIT_SECRETS_CACHED" == "1" ]]; then
  if have_command git-secrets; then
    if git diff --cached --quiet; then
      warn "No staged changes; skipping git-secrets cached scan"
    else
      run_optional "git-secrets --scan --cached" git-secrets --scan --cached
    fi
  else
    optional_tool_missing "git-secrets not installed; skipping staged secret scan"
  fi
fi

if [[ "$RUN_GIT_SECRETS_HISTORY" == "1" ]]; then
  if have_command git-secrets; then
    run_optional "git-secrets --scan-history" git-secrets --scan-history
  else
    optional_tool_missing "git-secrets not installed; skipping history secret scan"
  fi
fi

printf '\n==> Summary\n'
printf 'Failures: %s\n' "$failures"
printf 'Warnings: %s\n' "$warnings"

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi

printf '\nAll required checks passed.\n'
