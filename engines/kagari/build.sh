#!/usr/bin/env bash
# KAGARI SHIORI (POSIX / instance-ID ABI) を固定 revision でビルドする。
# Lua 5.4.4 と sol2 3.2.2 は task-local に取得（ハッシュ検証付き）。brew 不要。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
PINNED="$ROOT/engines/PINNED_UPSTREAM.json"
DEPS_MANIFEST="$ENGINE_DIR/DEPENDENCIES.json"
OUT="${1:-$ROOT/build/engines/kagari}"
DEPS="${OURIN_KAGARI_DEPS:-$ROOT/build/deps/kagari}"
REV="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["kagari_shiori"]["revision"])' "$PINNED")"
SRC="${OURIN_KAGARI_SRC:-$DEPS/kagari_shiori-src}"
PATCH_DIR="$ENGINE_DIR/patches"

CXX="${CXX:-clang++}"
CC="${CC:-clang}"

fetch_verified() {
  local url="$1" sha="$2" dest="$3"
  local tmp
  tmp="$(mktemp)"
  curl -fsSL "$url" -o "$tmp"
  local got
  got="$(shasum -a 256 "$tmp" | awk '{print $1}')"
  if [[ "$got" != "$sha" ]]; then
    echo "SHA256 mismatch for $url (expected $sha, got $got)" >&2
    exit 3
  fi
  mkdir -p "$(dirname "$dest")"
  mv "$tmp" "$dest"
}

ensure_deps() {
  local lua_url lua_sha sol_url sol_sha
  read -r lua_url lua_sha sol_url sol_sha <<<"$(python3 - <<'PY' "$DEPS_MANIFEST"
import json, sys
d = json.load(open(sys.argv[1]))
print(d["lua"]["url"], d["lua"]["sha256"], d["sol2"]["url"], d["sol2"]["sha256"])
PY
)"

  local lua_tgz="$DEPS/lua-5.4.4.tar.gz"
  local sol_tgz="$DEPS/sol2-3.2.2.tar.gz"
  [[ -f "$lua_tgz" ]] || fetch_verified "$lua_url" "$lua_sha" "$lua_tgz"
  [[ -f "$sol_tgz" ]] || fetch_verified "$sol_url" "$sol_sha" "$sol_tgz"

  if [[ ! -d "$DEPS/sol2-3.2.2/include/sol" ]]; then
    rm -rf "$DEPS/sol2-3.2.2"
    tar -xzf "$sol_tgz" -C "$DEPS"
    if [[ -f "$PATCH_DIR/003-sol2-optional-ref-emplace.patch" ]]; then
      patch -d "$DEPS/sol2-3.2.2" -p0 -N --forward -i "$PATCH_DIR/003-sol2-optional-ref-emplace.patch" || true
    fi
  fi
  if [[ ! -f "$DEPS/sol2-3.2.2/include/sol/sol.hpp" ]]; then
    echo "sol2 include tree incomplete after extract" >&2
    exit 3
  fi
  # Apple Clang + libc++ で 3.2.2 の optional<T&>::emplace が壊れるためパッチ済みであること
  if ! grep -q 'optional<T&>::emplace requires one lvalue' "$DEPS/sol2-3.2.2/include/sol/optional_implementation.hpp" 2>/dev/null; then
    patch -d "$DEPS/sol2-3.2.2" -p0 -N --forward -i "$PATCH_DIR/003-sol2-optional-ref-emplace.patch"
  fi

  if [[ ! -d "$DEPS/lua-5.4.4/src" ]]; then
    tar -xzf "$lua_tgz" -C "$DEPS"
  fi

  cp "$DEPS_MANIFEST" "$DEPS/DEPENDENCIES.json"
  cp "$DEPS/lua-5.4.4/doc/readme.html" "$DEPS/LICENSE.lua.html"
  if [[ -f "$DEPS/sol2-3.2.2/LICENSE.txt" ]]; then
    cp "$DEPS/sol2-3.2.2/LICENSE.txt" "$DEPS/LICENSE.sol2"
  fi
}

ensure_kagari_src() {
  if [[ ! -d "$SRC/.git" ]]; then
    git clone --filter=blob:none https://github.com/Tatakinov/kagari_shiori.git "$SRC"
  fi
  git -C "$SRC" fetch --depth 1 origin "$REV"
  git -C "$SRC" checkout --force --detach "$REV"
  for p in "$PATCH_DIR"/00[12]-*.patch; do
    [[ -f "$p" ]] || continue
    if ! patch -d "$SRC" -p1 -N --forward -i "$p"; then
      if ! grep -q 'defined(__APPLE__)' "$SRC/kagari.cpp" 2>/dev/null \
        && [[ "$(basename "$p")" == "001-apple-unix.patch" ]]; then
        echo "Failed to apply $p" >&2
        exit 4
      fi
      if ! grep -q 'instance->load(p)' "$SRC/kagari_unix.cpp" 2>/dev/null \
        && [[ "$(basename "$p")" == "002-kagari-unix-load-failure.patch" ]]; then
        echo "Failed to apply $p" >&2
        exit 4
      fi
    fi
  done
}

build_lua_dylib() {
  local arch="$1"
  local objdir="$2"
  local outdylib="$3"
  mkdir -p "$objdir"
  local srcdir="$DEPS/lua-5.4.4/src"
  local flags=(-std=gnu99 -O2 -fPIC -mmacosx-version-min=13.0 -DLUA_USE_MACOSX -arch "$arch")
  local objs=()
  local core=(
    lapi lcode lctype ldebug ldo ldump lfunc lgc llex lmem lobject lopcodes lparser lstate lstring ltable ltm lundump lvm lzio
    lauxlib lbaselib lcorolib ldblib liolib lmathlib loadlib loslib ltablib lstrlib lutf8lib linit
  )
  for c in "${core[@]}"; do
    local o="$objdir/${c}.o"
    "$CC" "${flags[@]}" -c "$srcdir/${c}.c" -o "$o"
    objs+=("$o")
  done
  "$CC" "${flags[@]}" -dynamiclib -o "$outdylib" "${objs[@]}" \
    -install_name '@rpath/liblua.5.4.dylib' \
    -compatibility_version 5.4.4 -current_version 5.4.4 \
    -lm
}

build_kagari_dylib() {
  local arch="$1"
  local objdir="$2"
  local outdylib="$3"
  local luadylib="$4"
  mkdir -p "$objdir"
  local sol_inc="$DEPS/sol2-3.2.2/include"
  local lua_inc="$DEPS/lua-5.4.4/src"
  local flags=(-std=c++17 -O2 -fPIC -mmacosx-version-min=13.0 -arch "$arch" -I"$SRC" -I"$sol_inc" -I"$lua_inc")
  local lua_dir
  lua_dir="$(dirname "$luadylib")"
  "$CXX" "${flags[@]}" -c "$SRC/kagari.cpp" -o "$objdir/kagari.o"
  "$CXX" "${flags[@]}" -c "$SRC/kagari_unix.cpp" -o "$objdir/kagari_unix.o"
  "$CXX" "${flags[@]}" -shared -o "$outdylib" "$objdir/kagari.o" "$objdir/kagari_unix.o" \
    "$lua_dir/liblua.5.4.dylib" \
    -install_name '@rpath/libkagari.dylib' \
    -Wl,-rpath,'@loader_path' \
    -Wl,-rpath,'@executable_path'
  install_name_tool -change '@rpath/liblua.5.4.dylib' '@loader_path/liblua.5.4.dylib' "$outdylib"
}

build_for_arch() {
  local arch="$1"
  local staged="$DEPS/stage-$arch"
  rm -rf "$staged"
  mkdir -p "$staged"
  build_lua_dylib "$arch" "$staged/lua-obj" "$staged/liblua.5.4.dylib"
  build_kagari_dylib "$arch" "$staged/kagari-obj" "$staged/libkagari.dylib" "$staged/liblua.5.4.dylib"
}

main() {
  ensure_deps
  ensure_kagari_src
  mkdir -p "$OUT"

  local host_arch
  host_arch="$(uname -m)"
  local build_universal="${OURIN_KAGARI_UNIVERSAL:-0}"

  if [[ "$build_universal" == "1" ]]; then
    build_for_arch arm64
    build_for_arch x86_64
    lipo -create \
      "$DEPS/stage-arm64/liblua.5.4.dylib" \
      "$DEPS/stage-x86_64/liblua.5.4.dylib" \
      -output "$OUT/liblua.5.4.dylib"
    lipo -create \
      "$DEPS/stage-arm64/libkagari.dylib" \
      "$DEPS/stage-x86_64/libkagari.dylib" \
      -output "$OUT/libkagari.dylib"
  else
    local arch="$host_arch"
    if [[ "$arch" != arm64 && "$arch" != x86_64 ]]; then
      arch=arm64
    fi
    build_for_arch "$arch"
    cp "$DEPS/stage-$arch/liblua.5.4.dylib" "$OUT/liblua.5.4.dylib"
    cp "$DEPS/stage-$arch/libkagari.dylib" "$OUT/libkagari.dylib"
  fi

  PLIST="$OUT/libkagari.dylib.plist"
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0"><dict><key>OurinShioriABI</key><string>kagari</string></dict></plist>' > "$PLIST"
  cp "$SRC/LICENSE" "$OUT/LICENSE.kagari"
  cp "$DEPS/LICENSE.lua.html" "$OUT/LICENSE.lua.html"
  [[ -f "$DEPS/LICENSE.sol2" ]] && cp "$DEPS/LICENSE.sol2" "$OUT/LICENSE.sol2"
  cp "$DEPS/DEPENDENCIES.json" "$OUT/DEPENDENCIES.json"

  echo "Built $OUT/libkagari.dylib + liblua.5.4.dylib (kagari_shiori $REV)"
  otool -L "$OUT/libkagari.dylib"
}

main "$@"
