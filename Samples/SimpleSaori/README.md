# SimpleSaori Samples

`SimpleSaori` は SAORI/1.0 の最小実装サンプルです。

- `cpp_saori/`: C++ 版 (`load/unload/request`)
- `swift_saori/`: Swift 版 (`@_cdecl("load"|"unload"|"request")`)

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

## Wire format

サンプルは SAORI/1.0 の応答を返します:

```text
SAORI/1.0 200 OK
Charset: UTF-8
Result: 1
Value: Hello from ... SAORI
```

`Argument0:` が含まれる場合は `Value` へ echo します。

