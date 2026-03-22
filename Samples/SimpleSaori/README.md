# SimpleSaori Samples

`SimpleSaori` は SAORI/1.0 の最小実装サンプルです。

- `cpp_saori/`: C++ 版 (`load/unload/request`)
- `swift_saori/`: Swift 版 (`@_cdecl("load"|"unload"|"request")`)
- `SimpleSaori.swift`: 単体ビルド用 Swift ソース
- `test_ghost/`: LOADLIB/REQUESTLIB/UNLOADLIB サイクル確認用ミニゴースト

## Build

### C++ sample

```bash
cd cpp_saori
cmake -S . -B build
cmake --build build
```

生成物: `build/simple_saori_cpp.dylib`

### Swift sample

```bash
cd swift_saori
swift build -c release
```

生成物: `.build/release/libsimple_saori_swift.dylib`

### Swift single-file build

```bash
cd Samples/SimpleSaori
chmod +x build_simple_saori.sh
./build_simple_saori.sh
```

生成物: `build/libsimple_saori_swift.dylib`

## Wire format

サンプルは SAORI/1.0 の応答を返します:

```text
SAORI/1.0 200 OK
Charset: UTF-8
Result: 1
Value: Hello from ... SAORI
```

`Argument0:` が含まれる場合は `Value` へ echo します。

## Test ghost

`test_ghost/ghost/master/saori_test.dic` は `OnBoot` で以下を実行します。

1. `LOADLIB`
2. `REQUESTLIB`
3. `UNLOADLIB`

事前に `saori_test.dic` 内の `_module` を実際の `.dylib` 絶対パスへ変更してください。
