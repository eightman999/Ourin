# 固定 shioridll-nim の POSIX ABI 差分

対象: `9bb220712818ce709d9eeb69c1a9d1cbd77906a6`。OurinのNativeローダーは変更せず、展開した一時コピーの `shioridll.nim` だけへ差分を適用します。各置換は固定上流で1か所だけ一致することを確認します。

1. POSIXの `shioriAlloc` / `shioriFree` は上流でNimの `alloc` / `dealloc` を使用します。しかしOurinの `ukagaka-long` 契約は、入力がホストの `malloc`、出力がホストの `free` です。公開境界のバッファだけをlibcの `malloc` / `free` に揃えます。内部一時バッファは従来どおりNimのallocatorで管理します。
2. `load` / `unload` のC公開戻り値をNim `bool` から `cint` に変換します。内部callbackのboolは保持し、`ord`で0/1へ変換します。C `int32` を返すと明示したOurinの既存ロード規約に合わせるためです。ポインタ長は引き続き `clong`（macOS 64 bit）で、メタデータに `ukagaka-long` を記載します。
3. callbackの返却するNim stringを変数へ保持してから `cstring` としてコピーします。一時文字列から取り出したpointerだけを保持する状態を避けます。メモリ管理は `--mm:arc --threads:on --tlsEmulation:off` を固定します。

上流 `example/basic.nim` のバイト列、イベント分岐、返却テキストを変更しません。別途自作した `example/japanese.nim` は固定上流の実 `shioridll` をimportする検証用callbackであり、インターフェースを置き換えるstubではありません。

2026-10-26、実Nim Compiler 2.2.4で両dylibのコンパイルを確認。独立Swift probeからOurin本番の `NativeShioriModule` を使い、日本語OnBoot、絵文字を含むReference往復、終了時保存、同一モジュールのunload/reloadを2周確認しました。標準FactoryとXPCを含むXcode回帰は `NimShioriEngineTests` で確認します。

## XPC の異なるホストスレッドからの呼出し

初回の `--mm:refc` ビルドは同一スレッドでのロード・要求・終了には成功しましたが、XPCでload後の最初の要求がSIGSEGVになりました。同じdylibに対し、Swiftからload/request/unloadをそれぞれ新規 `Thread` で呼ぶ独立probeでもSIGSEGVを再現しました。シリアルDispatchQueueは同じpthreadを保証しません。

固定Nim Compilerの `lib/system/gc_common.nim` は、refcで外部スレッドへ入る際に `setupForeignThreadGc` によるスレッドごとのGC初期化を要求します。一方 `lib/system/arc.nim` の同APIはnopです。今回はホストのthread lifecycleへGC登録・解除を追加するのではなく、Nimの標準ARCを明示選択し、tracing GCのスレッド別ヒープへの依存を取り除きました。Ourin側のABIやXPC実行方式は変更しません。文字列callbackの内容・状態は保持します。callbackを並行実行する保証はなく、既存のNative/XPCと同じ直列呼出しを前提とします。

修正後の実コンパイルdylibを同じ独立probeへ渡し、2 lifecycle、各要求を新規foreign threadで実行する計20回の日本語要求、別threadでのunloadと再loadがPASSしました。回帰試験 `nativeNimEntryPointsRunOnFreshForeignThreads` を追加しました。初回の同thread probeだけではこの層を検証できていなかったため、その成功とXPC対応成功を区別します。

## Intel / Universal2

2026-10-28: 同じ固定arm64 Nim 2.2.4コンパイラから、`--cpu:arm64` または `--cpu:amd64` とClangの `-arch arm64/x86_64` を明示してC backendをクロスビルドします。CPUごとにnimcacheを分離し、ABI境界の既存patchとARC/TLS設定は共有します。Universal2は同じcallbackから生成した両dylibをlipoで結合し、出力sliceを検査します。LC_ID_DYLIBは一時build directoryではなく `@rpath/最終ファイル名` へ固定します。source/exampleの変更やthreadモデルの回避策は追加していません。

新規 `probe/NativeProbe.swift` は本番NativeShioriModuleと一緒にarm64/Intel Swift CLIへcompileします。上流basicと日本語例を同時loadし、fresh foreign pthreadからの直列entry、20回の日本語＋絵文字往復、別threadでのunload、2 lifecycleを実行します。thin IntelとUniversal2 Intelの両方でRosetta translated=1、Universal2 arm64ではnative実行を確認しました。Intel実機の証明とは区別します。Universal2のFactory/XPC回帰は追加したXcode testで行います。
