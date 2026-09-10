#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'The application must be built on macOS. Use scripts/test.sh for portable checks.' >&2
  exit 1
fi
if [[ "$(uname -m)" != x86_64 ]]; then
  echo 'Build this Intel distribution using an Intel Mac and Intel Homebrew.' >&2
  exit 1
fi
python3 scripts/download_models.py
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DOpenCV_DIR="$(brew --prefix opencv)/lib/cmake/opencv4"
cmake --build build --parallel 2
ctest --test-dir build --output-on-failure
echo 'Built build/FaceGate.app. Start it with: open build/FaceGate.app'
