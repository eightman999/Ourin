# OurinSwiftSHIORI
Swift による最小の **SHIORI/3.0M** 実装サンプルです。
詳細仕様は `docs/SHIORI_3.0M_SPEC.md` および `OURIN_SHIORI3M_HOST_PLAN.md`、`SAMPLE` を参照してください。

## ビルド（Swift Package Manager）
```bash
cd swift_shiori
swift build -c release
```
生成されたライブラリは `ourin-shiori-host` などの SHIORI/3.0M ホストからロードできます。
