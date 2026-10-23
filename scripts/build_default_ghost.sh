#!/bin/bash
# DefaultGhost/sakura を sakura.nar にまとめる（Xcode の Resources に同梱）。
set -euo pipefail
cd "$(dirname "$0")/.."
rm -f sakura.nar
(cd DefaultGhost/sakura && zip -qr -X ../../sakura.nar . -x '.DS_Store')
echo "built sakura.nar"
