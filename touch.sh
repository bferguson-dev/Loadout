cat > check.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ---- Step: find repo root ----
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

# ---- Step: ensure Python + venv ----
PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-.venv}"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "ERROR: $PYTHON_BIN not found."
  exit 2
fi

if [[ ! -d "$VENV_DIR" ]]; then
  echo "[setup] Creating venv at $VENV_DIR"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

# ---- Step: install/upgrade tooling ----
echo "[setup] Upgrading pip + installing tooling"
python -m pip install -U pip >/dev/null
python -m pip install -U ruff bandit pip-audit pytest >/dev/null

# ---- Step: format ----
echo "[format] ruff format"
ruff format .

# ---- Step: lint ----
echo "[lint] ruff check"
ruff check .

# ---- Step: security scan (code) ----
echo "[security] bandit"
# Exclude common venv/cache dirs; add more if needed.
bandit -r . -x "./.venv,./venv,./.git,./__pycache__" -q

# ---- Step: dependency audit ----
echo "[deps] pip-audit"
# Audit installed env; also audit requirements files if present.
pip-audit

if [[ -f "requirements.txt" ]]; then
  pip-audit -r requirements.txt
fi
if [[ -f "requirements-dev.txt" ]]; then
  pip-audit -r requirements-dev.txt
fi

# ---- Step: tests ----
if [[ -d "tests" || -f "pytest.ini" || -f "pyproject.toml" || -f "setup.cfg" ]]; then
  echo "[tests] pytest"
  pytest -q
else
  echo "[tests] No obvious test config found; skipping pytest."
fi

echo "OK: checks passed"
EOF

chmod +x check.sh
