#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

run_step() {
  printf '\n==> %s\n' "$1"
}

PS_CMD=""
if command -v powershell >/dev/null 2>&1; then
  PS_CMD="powershell"
elif command -v pwsh >/dev/null 2>&1; then
  PS_CMD="pwsh"
else
  echo "ERROR: neither 'powershell' nor 'pwsh' is available on PATH"
  exit 2
fi

run_step "Checking for Windows zone metadata files"
mapfile -t zone_files < <(find . -name '*:Zone.Identifier' -type f | sort)
if [[ ${#zone_files[@]} -gt 0 ]]; then
  echo "ERROR: found ${#zone_files[@]} Zone.Identifier file(s):"
  printf '  %s\n' "${zone_files[@]}"
  echo "Run: find . -name '*:Zone.Identifier' -type f -delete"
  exit 1
fi

echo "OK: no Zone.Identifier files found"

run_step "PowerShell parse check"
"$PS_CMD" -NoProfile -File ./tests/parse-check.ps1

run_step "PowerShell test suite"
"$PS_CMD" -NoProfile -File ./tests/run-all-tests.ps1

run_step "gitleaks"
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --source . --no-banner
  echo "OK: gitleaks found no leaks"
else
  echo "WARN: gitleaks not installed; skipping secret scan"
fi

printf '\nAll checks passed.\n'
