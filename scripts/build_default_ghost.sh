#!/bin/bash
# DefaultGhost/rin を rin.nar にまとめる（Xcode の Resources に同梱）。
set -euo pipefail
cd "$(dirname "$0")/.."
rm -f rin.nar
(cd DefaultGhost/rin && zip -qr -X ../../rin.nar . -x '.DS_Store')
echo "built rin.nar"
