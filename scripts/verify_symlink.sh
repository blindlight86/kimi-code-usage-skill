#!/usr/bin/env bash
set -euo pipefail

target="$1"
[ -L "$target" ] || { echo "not symlink"; exit 1; }
readlink "$target"
