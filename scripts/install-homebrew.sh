#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != x86_64 ]]; then
  echo 'This installer requires an Intel Mac running macOS 14 or newer.' >&2
  exit 1
fi
if [[ "$(/usr/bin/sw_vers -productVersion | cut -d. -f1)" -lt 14 ]]; then
  echo 'macOS 14 or newer is required.' >&2
  exit 1
fi
if [[ "$(id -u)" == 0 ]]; then echo 'Run without sudo.' >&2; exit 1; fi
command -v brew >/dev/null || { echo 'Install Homebrew from https://brew.sh first.' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'Install Python 3: brew install python' >&2; exit 1; }
if ! brew tap | /usr/bin/grep -qx 'local/facegate'; then
  brew tap-new local/facegate
fi
fg_tap="$(brew --repository local/facegate)"
mkdir -p "$fg_tap/vendor" "$fg_tap/Formula"
python3 scripts/package.py --output "$fg_tap/vendor/facegate-0.1.0.tar.gz"
python3 scripts/make_formula.py --archive "$fg_tap/vendor/facegate-0.1.0.tar.gz" --output "$fg_tap/Formula/facegate.rb"
brew install --build-from-source local/facegate/facegate
facegate
