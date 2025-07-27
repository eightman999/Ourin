# OurinSampleSHIORI（C, minimal）
最小の **SHIORI/3.0M** 実装（固定応答）。

## ビルド（CMake + clang）
```bash
cd samples/c_shiori
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
cmake --build . --config Release
# 生成物: build/OurinSampleSHIORI.bundle
```

## エクスポート関数（C ABI）
- `bool shiori_load(const char* dir_utf8)`
- `void shiori_unload(void)`
- `bool shiori_request(const unsigned char* req, size_t req_len, unsigned char** res, size_t* res_len)`
- `void shiori_free(unsigned char* p)`
