# Ourin ドキュメント（HTML版） / Ourin Documentation (HTML)

このディレクトリには、Ourin（桜鈴）の全ドキュメントの HTML 版が含まれています。  
This directory contains HTML versions of all Ourin documentation.

## 閲覧方法 / How to View

1. **索引ページから閲覧 / Browse from Index**: [index.html](index.html) を開いて、カテゴリ別に整理されたドキュメント一覧から選択  
   Open [index.html](index.html) and select from categorized document list
2. **直接閲覧 / Direct Access**: 各 HTML ファイルを直接開く  
   Open individual HTML files directly

## ドキュメントについて / About Documentation

### 言語サポート / Language Support
- **バイリンガル / Bilingual**: 全ドキュメントに日本語版と英語版があります  
  All documents are available in both Japanese and English
- **言語切り替え / Language Switching**: 各ドキュメントページ上部で言語を切り替えられます  
  Switch languages using the controls at the top of each document

### ファイル命名規則 / File Naming Convention
- 日本語版 / Japanese: `{DocumentName}_ja-jp.html`
- 英語版 / English: `{DocumentName}_en-us.html`

### 翻訳ステータス / Translation Status
最新の翻訳状況は [TRANSLATION_MANIFEST.md](../TRANSLATION_MANIFEST.md) を参照してください。
See [TRANSLATION_MANIFEST.md](../TRANSLATION_MANIFEST.md) for the current translation status.

## 主要ドキュメント / Key Documents

### コア仕様書 / Core Specifications
- [SHIORI/3.0M 仕様 / Specification](SHIORI_3.0M_SPEC_ja-jp.html) ([EN](SHIORI_3.0M_SPEC_en-us.html))
- [SSTP/1.xM 仕様 / Specification](SSTP_1.xM_SPEC_ja-jp.html) ([EN](SSTP_1.xM_SPEC_en-us.html))
- [PLUGIN/2.0M 仕様 / Specification](SPEC_PLUGIN_2.0M_ja-jp.html) ([EN](SPEC_PLUGIN_2.0M_en-us.html))
- [NAR INSTALL/1.0M 仕様 / Specification](NAR_INSTALL_1.0M_SPEC_ja-jp.html) ([EN](NAR_INSTALL_1.0M_SPEC_en-us.html))

### システム実装 / System Implementation
- [FMO について / About FMO](About_FMO_ja-jp.html) ([EN](About_FMO_en-us.html))
- [YAYA Adapter 仕様 / Specification](OURIN_YAYA_ADAPTER_SPEC_1.0M_ja-jp.html) ([EN](OURIN_YAYA_ADAPTER_SPEC_1.0M_en-us.html))

## 生成について / Generation

### 自動生成 / Automated Generation
これらの HTML ファイルは、マークダウン版から Python の markdown パッケージを使用して自動生成されています。  
These HTML files are automatically generated from markdown source using Python's markdown package.

### 再生成方法 / How to Regenerate
```bash
cd docs
python3 generate_html.py
```

### スタイル / Styling
日本語フォントとコードブロックの読みやすさを重視して設計されています。  
Designed with emphasis on Japanese font rendering and code block readability.

## ライセンス / License

Ourin独自ドキュメントはCC BY-SA 4.0です。第三者資料は元のライセンスを維持します。
Original Ourin documentation is CC BY-SA 4.0. Third-party material retains its original license.

## 更新日 / Last Updated
2026-08-15
