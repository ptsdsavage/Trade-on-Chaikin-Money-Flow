#!/bin/bash
# Builds standalone macOS executables (arm64 + x86_64 via Rosetta) for
# cmf_spy.py (signal viewer) and cmf_trader.py (paper trader) using isolated
# venvs, so PyInstaller doesn't bundle unrelated packages from the system
# Python. Compiled deps (e.g. pydantic_core) aren't shipped as fat binaries,
# so we build each architecture separately rather than universal2. The
# resulting binaries + launcher scripts are packaged into
# "Trade on Chaikin Money Flow.zip".
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Trade on Chaikin Money Flow"

rm -rf build dist .build-venv-arm64 .build-venv-x86_64 "$APP_NAME" "$APP_NAME.zip" \
  SPY-CMF-Signal-arm64.spec SPY-CMF-Signal-x86_64.spec CMF-Trader-arm64.spec CMF-Trader-x86_64.spec

build_arch() {
  local venv="$1" pyinstaller_prefix="$2" arch_suffix="$3"

  $pyinstaller_prefix python3 -m venv "$venv"
  source "$venv/bin/activate"
  $pyinstaller_prefix python3 -m pip install --quiet --upgrade pip
  $pyinstaller_prefix python3 -m pip install --quiet -r requirements.txt
  $pyinstaller_prefix python3 -m PyInstaller --onefile --name "SPY-CMF-Signal-$arch_suffix" --console cmf_spy.py
  $pyinstaller_prefix python3 -m PyInstaller --onefile --name "CMF-Trader-$arch_suffix" --console cmf_trader.py
  deactivate
  rm -rf build "SPY-CMF-Signal-$arch_suffix.spec" "CMF-Trader-$arch_suffix.spec"
}

build_arch .build-venv-arm64 "" arm64
build_arch .build-venv-x86_64 "arch -x86_64" x86_64

rm -rf .build-venv-arm64 .build-venv-x86_64

mkdir "$APP_NAME"
cp dist/SPY-CMF-Signal-arm64 dist/SPY-CMF-Signal-x86_64 dist/CMF-Trader-arm64 dist/CMF-Trader-x86_64 "$APP_NAME/"

cat > "$APP_NAME/Run SPY Signal.command" <<'EOF'
#!/bin/bash
# Double-clickable launcher: picks the right binary for this Mac's chip and runs it.
cd "$(dirname "$0")"

if [ "$(uname -m)" = "arm64" ]; then
  BIN="./SPY-CMF-Signal-arm64"
else
  BIN="./SPY-CMF-Signal-x86_64"
fi

"$BIN"
echo
echo "Press Enter to close this window..."
read
EOF

cat > "$APP_NAME/Run CMF Trader.command" <<'EOF'
#!/bin/bash
# Double-clickable launcher: picks the right binary for this Mac's chip and runs it.
cd "$(dirname "$0")"

if [ "$(uname -m)" = "arm64" ]; then
  BIN="./CMF-Trader-arm64"
else
  BIN="./CMF-Trader-x86_64"
fi

"$BIN"
echo
echo "Press Enter to close this window..."
read
EOF

chmod +x "$APP_NAME/Run SPY Signal.command" "$APP_NAME/Run CMF Trader.command"

zip -r -q "$APP_NAME.zip" "$APP_NAME"
rm -rf "$APP_NAME"

echo "Built: $APP_NAME.zip (SPY-CMF-Signal + CMF-Trader, arm64 + x86_64)"

