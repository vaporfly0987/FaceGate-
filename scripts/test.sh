#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -pedantic -Iinclude \
  src/Gate.cpp tests/GateTests.cpp -o build/gate_tests
build/gate_tests
python3 -m unittest discover -s tests -p 'test_*.py' -v
