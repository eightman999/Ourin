#!/bin/bash
# =====================================================================
# Ourin 検証ハーネス（AIエージェント向け）
#
# 使い方:
#   ./verify.sh --check   ツール存在確認と実行予定ステップの表示のみ（数秒）
#   ./verify.sh           高速検証: 構成確認 + xcodebuild build（目安5分以内）
#   ./verify.sh --full    重い検証: 上記 + xcodebuild test
#                         （YayaEmily4RegressionTests を含む全テスト）
#                         実ゴースト Emily4 の回帰テストは、emily4/ghost/master/yaya.txt が
#                         あるか環境変数 OURIN_EMILY4_DIR を指定したときだけ実行する。
#                         無いときは実行されず skip（SKIP 件数に数える）。
#
# 契約:
#   - 出力は "[n/m] ステップ名" 形式。最後に VERIFY PASS / VERIFY FAIL(exit 1)
#   - ツール欠如時: --check は WARN、無印/--full は SKIP を正直に表示
#   - リポジトリの状態は変更しない（xcodebuild のビルドフェーズが
#     yaya_core/build・satori_core/build を生成するのは既存の設計通り）
#
# コマンドの出典（推測ではなく実ファイル記載のものを使用）:
#   - CLAUDE.md / README.md:
#       xcodebuild -project Ourin.xcodeproj -scheme Ourin build
#       xcodebuild -project Ourin.xcodeproj -scheme Ourin test
#   - xcodebuild の test 実行へ環境変数を渡すには TEST_RUNNER_ 接頭辞が要る
#     （接頭辞を外した名前でテストプロセスに渡される）。本スクリプトは
#     Emily4 のルートを TEST_RUNNER_OURIN_EMILY4_DIR として渡す。
#   - 単一テストのみ実行する場合(参考・本スクリプトでは未使用):
#       xcodebuild -project Ourin.xcodeproj -scheme Ourin \
#         -only-testing:OurinTests/YayaEmily4RegressionTests test
#   - yaya_core / satori_core の手動ビルド: 各ディレクトリの ./build.sh
#     (Xcode のビルドフェーズ "Build yaya_core" / "Build satori_core" が
#      自動実行するため、本スクリプトからは直接呼ばない。cmake 必須)
#
# 互換性: bash 3.2 / BSD ユーティリティ（mapfile・grep -P は不使用）
# =====================================================================
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"

MODE="fast"
case "${1:-}" in
  --check) MODE="check" ;;
  --full)  MODE="full" ;;
  "")      MODE="fast" ;;
  *)
    echo "不明な引数: ${1}（使用可能: --check / 無印 / --full）"
    exit 2
    ;;
esac

STEP=0
TOTAL=0
RUN_COUNT=0
SKIP_COUNT=0

step() { STEP=$((STEP + 1)); echo "[${STEP}/${TOTAL}] $1"; }
ok()   { RUN_COUNT=$((RUN_COUNT + 1)); echo "  OK: $1"; }
skip() { SKIP_COUNT=$((SKIP_COUNT + 1)); echo "  SKIP: $1"; }
info() { echo "  INFO: $1"; }
fail() {
  echo "  NG: $1"
  echo "VERIFY FAIL"
  exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }

finish() {
  echo "結果: 実行 ${RUN_COUNT} 件 / SKIP ${SKIP_COUNT} 件"
  echo "VERIFY PASS"
  exit 0
}

# --- ツール状態の事前判定 -------------------------------------------
# xcodebuild は存在してもXcode本体未選択（Command Line Toolsのみ）だと
# 動かないため、-version の成否まで確認する。
XCODEBUILD_OK=0
if have xcodebuild && xcodebuild -version >/dev/null 2>&1; then
  XCODEBUILD_OK=1
fi
CMAKE_OK=0
if have cmake; then CMAKE_OK=1; fi

# ヘルパーコアのビルド成果物（有無の事実確認のみ。生成はしない）
YAYA_BIN="yaya_core/build/yaya_core"
SATORI_BIN="satori_core/build/satori_core"

if [ "$MODE" = "check" ]; then
  TOTAL=2
  step "ツール存在確認"
  if [ "$XCODEBUILD_OK" -eq 1 ]; then
    echo "  ツール xcodebuild: 有（$(xcodebuild -version | head -n 1)）"
  elif have xcodebuild; then
    echo "  ツール xcodebuild: WARN コマンドはあるが動作しない（Xcode本体が未選択の可能性。xcode-select 要確認）"
  else
    echo "  ツール xcodebuild: WARN 見つからない（Xcodeが必要）"
  fi
  if [ "$CMAKE_OK" -eq 1 ]; then
    echo "  ツール cmake: 有（$(command -v cmake)）"
  else
    echo "  ツール cmake: WARN 見つからない（ビルドフェーズ Build yaya_core / Build satori_core が失敗する。brew install cmake）"
  fi
  if have make; then
    echo "  ツール make: 有（$(command -v make)）"
  else
    echo "  ツール make: WARN 見つからない（Xcode Command Line Tools が必要）"
  fi
  step "実行予定ステップ表示"
  echo "  無印 : [1/3] 構成ファイル確認（Ourin.xcodeproj）"
  echo "         [2/3] yaya_core / satori_core のビルド有無確認"
  echo "         [3/3] xcodebuild -project Ourin.xcodeproj -scheme Ourin build"
  echo "  --full: 上記に加えて"
  echo "         [4/5] YayaEmily4 回帰テストの前提確認（emily4/ または OURIN_EMILY4_DIR の辞書・yaya_core バイナリ）"
  echo "         [5/5] xcodebuild -project Ourin.xcodeproj -scheme Ourin test"
  finish
fi

# --- 無印 / --full 共通ステップ --------------------------------------
if [ "$MODE" = "full" ]; then TOTAL=5; else TOTAL=3; fi

step "構成ファイル確認（Ourin.xcodeproj）"
HAS_PROJ=0
if [ -d "Ourin.xcodeproj" ]; then
  HAS_PROJ=1
  ok "Ourin.xcodeproj が存在する"
else
  # xcodeproj が無い環境では xcodebuild 系ステップは実行できない
  skip "Ourin.xcodeproj が見つからないため xcodebuild 系ステップをスキップする"
fi

step "yaya_core / satori_core のビルド有無確認"
if [ -x "$YAYA_BIN" ]; then
  ok "yaya_core ビルド済み（${YAYA_BIN}）"
else
  info "yaya_core 未ビルド（${YAYA_BIN} が無い）。見つからないまま test を実行すると YayaEmily4RegressionTests は skip される"
fi
if [ -x "$SATORI_BIN" ]; then
  ok "satori_core ビルド済み（${SATORI_BIN}）"
else
  info "satori_core 未ビルド（${SATORI_BIN} が無い）"
fi
if [ "$CMAKE_OK" -eq 0 ]; then
  info "cmake が無いため、xcodebuild 実行時のヘルパーコアビルドフェーズは失敗する（brew install cmake）"
fi

step "アプリのビルド: xcodebuild -project Ourin.xcodeproj -scheme Ourin build"
BUILD_DONE=0
if [ "$HAS_PROJ" -eq 0 ]; then
  skip "Ourin.xcodeproj が無い"
elif [ "$XCODEBUILD_OK" -eq 0 ]; then
  skip "xcodebuild が使用できない"
elif [ "$CMAKE_OK" -eq 0 ] && { [ ! -x "$SATORI_BIN" ] || [ ! -x "$YAYA_BIN" ]; }; then
  # satori_core のビルドフェーズは毎回 build.sh を呼び、cmake 欠如時は exit 127 する。
  # 確実に失敗すると分かっているビルドは実行せず、理由を示してスキップする。
  skip "cmake 未インストールかつヘルパーコア未ビルドのため build は失敗する。brew install cmake 後に再実行"
else
  LOG=$(mktemp "${TMPDIR:-/tmp}/ourin_verify_build.XXXXXX")
  echo "  実行中（ログ: ${LOG}）..."
  if xcodebuild -project Ourin.xcodeproj -scheme Ourin build >"$LOG" 2>&1; then
    ok "ビルド成功"
    BUILD_DONE=1
  else
    echo "  --- ビルドログ末尾 ---"
    tail -n 40 "$LOG"
    fail "xcodebuild build が失敗した（全ログ: ${LOG}）"
  fi
fi

if [ "$MODE" = "fast" ]; then
  finish
fi

# --- --full 専用ステップ ---------------------------------------------
step "YayaEmily4 回帰テストの前提確認"
if [ -f "OurinTests/YayaEmily4RegressionTests.swift" ]; then
  ok "OurinTests/YayaEmily4RegressionTests.swift が存在する"
else
  info "OurinTests/YayaEmily4RegressionTests.swift が見つからない"
fi
# テストが見るのは環境変数 OURIN_EMILY4_DIR（Emily4 ゴーストのルート）だけなので、
# ここで同じ値を決めて test 実行へ渡す。指定があればそれを優先し、無ければ emily4/ を使う。
EMILY4_DIR=""
if [ -n "${OURIN_EMILY4_DIR:-}" ]; then
  EMILY4_DIR="$OURIN_EMILY4_DIR"
elif [ -f "emily4/ghost/master/yaya.txt" ]; then
  EMILY4_DIR="$(pwd)/emily4"
fi
if [ -z "$EMILY4_DIR" ]; then
  skip "Emily4 が無い（emily4/ghost/master/yaya.txt も OURIN_EMILY4_DIR も無い）ため、実ゴースト回帰テストは実行されず skip になる"
elif [ ! -d "${EMILY4_DIR}/ghost/master" ]; then
  # 明示指定したのに使えないのは設定ミス。skip で済ませず失敗にする。
  fail "OURIN_EMILY4_DIR=${EMILY4_DIR} に ghost/master が無い（Emily4 ゴーストのルートを指定する）"
else
  ok "実ゴースト Emily4 を回帰テストに渡す（OURIN_EMILY4_DIR=${EMILY4_DIR}）"
fi
if [ ! -x "$YAYA_BIN" ]; then
  if [ "$BUILD_DONE" -eq 1 ]; then
    info "build 後も ${YAYA_BIN} が無い。見つからないままだと回帰テストは skip される"
  else
    info "${YAYA_BIN} が無い。見つからないままだと回帰テストは skip される（test のビルドフェーズで生成される場合あり）"
  fi
fi

# xcodebuild test のテストプロセスへ環境変数を渡すには TEST_RUNNER_ 接頭辞が要る。
run_xcodebuild_test() {
  if [ -n "$EMILY4_DIR" ]; then
    TEST_RUNNER_OURIN_EMILY4_DIR="$EMILY4_DIR" \
      xcodebuild -project Ourin.xcodeproj -scheme Ourin test
  else
    xcodebuild -project Ourin.xcodeproj -scheme Ourin test
  fi
}

step "テスト: xcodebuild -project Ourin.xcodeproj -scheme Ourin test"
if [ "$HAS_PROJ" -eq 0 ]; then
  skip "Ourin.xcodeproj が無い"
elif [ "$XCODEBUILD_OK" -eq 0 ]; then
  skip "xcodebuild が使用できない"
elif [ "$CMAKE_OK" -eq 0 ] && { [ ! -x "$SATORI_BIN" ] || [ ! -x "$YAYA_BIN" ]; }; then
  skip "cmake 未インストールかつヘルパーコア未ビルドのため test は失敗する。brew install cmake 後に再実行"
else
  LOG=$(mktemp "${TMPDIR:-/tmp}/ourin_verify_test.XXXXXX")
  echo "  実行中（ログ: ${LOG}）..."
  if run_xcodebuild_test >"$LOG" 2>&1; then
    ok "テスト成功（xcodebuild test が終了コード 0）"
    # Emily4 の回帰テストが「実行された」のか「skip された」のかを区別して報告する。
    # skip は xcodebuild の成功に含まれるため、終了コードだけでは分からない。
    # ここはログの文面に頼る簡易判定（Emily4 のテスト名と skipped が同じ行に出るか）。
    if [ -z "$EMILY4_DIR" ]; then
      info "Emily4 実ゴースト回帰テストは前提が無く実行されていない（上の SKIP を参照）"
    elif grep -Eqi 'skipped.*emily4|emily4.*skipped' "$LOG"; then
      skip "Emily4 を渡したが、Emily4 回帰テストが skip と報告された（ログ: ${LOG}）"
    elif grep -q "YayaEmily4RegressionTests" "$LOG"; then
      ok "YayaEmily4RegressionTests がログに出現し、skip の報告は無い"
    else
      skip "YayaEmily4RegressionTests がログに見つからず、実行を確認できない（ログ: ${LOG}）"
    fi
  else
    echo "  --- テストログ末尾 ---"
    tail -n 60 "$LOG"
    fail "xcodebuild test が失敗した（全ログ: ${LOG}）"
  fi
fi

finish
