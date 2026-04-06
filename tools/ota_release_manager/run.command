#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# Prefer modern Python builds over Xcode-bundled Python 3.9 (Tk 8.5 crash on new macOS).
PY_CANDIDATES=(
  "/opt/homebrew/bin/python3"
  "/usr/local/bin/python3"
  "python3"
)

pick_python() {
  for py in "${PY_CANDIDATES[@]}"; do
    if ! command -v "$py" >/dev/null 2>&1; then
      continue
    fi
    # Ensure tkinter is available and usable.
    if "$py" -c "import tkinter; print('ok')" >/dev/null 2>&1; then
      echo "$py"
      return 0
    fi
  done
  return 1
}

if ! PY_BIN="$(pick_python)"; then
  cat <<'MSG'
[ERROR] Uygun tkinter destekli Python bulunamadi.

Onerilen:
  brew install python

Sonra tekrar:
  ./run.command
MSG
  exit 1
fi

exec "$PY_BIN" app.py
