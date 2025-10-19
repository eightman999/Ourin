# YAYA Core 技術仕様書

**バージョン**: 1.0  
**日付**: 2025-10-16  
**対象**: macOS (Universal Binary: arm64 + x86_64)  
**ライセンス**: BSD-3-Clause (YAYA準拠)

---

## 1. 概要

### 1.1 目的

本ドキュメントは、Ourin向けYAYA Core実装の技術的な詳細を定義します。Windows版YAYAの言語仕様を参考にしつつ、macOSネイティブ環境に最適化された実装を提供します。

### 1.2 スコープ

- YAYA言語の字句解析・構文解析
- YAYA仮想マシン（VM）の実装
- SHIORI/3.0Mプロトコルとの統合
- UTF-8/CP932文字コードのサポート

### 1.3 非スコープ

- Windows DLLバイナリ互換（不可能）
- SAORI連携（Phase 2以降）
- デバッガUI（将来拡張）

---

## 2. YAYA言語仕様（実装対象）

### 2.1 字句要素（Lexical Elements）

#### 2.1.1 トークン種別

```cpp
enum class TokenType {
    // リテラル
    String,          // "文字列"
    Integer,         // 123
    Float,           // 3.14
    
    // 識別子・キーワード
    Identifier,      // 変数名・関数名
    If,              // if
    Else,            // else
    ElseIf,          // elseif
    When,            // when
    While,           // while
    For,             // for
    Foreach,         // foreach
    Break,           // break
    Continue,        // continue
    Return,          // return
    
    // 演算子
    Assign,          // =
    Plus,            // +
    Minus,           // -
    Multiply,        // *
    Divide,          // /
    Modulo,          // %
    Equal,           // ==
    NotEqual,        // !=
    Less,            // <
    Greater,         // >
    LessEqual,       // <=
    GreaterEqual,    // >=
    LogicalAnd,      // &&
    LogicalOr,       // ||
    LogicalNot,      // !
    BitwiseAnd,      // &
    BitwiseOr,       // |
    BitwiseXor,      // ^
    LeftShift,       // <<
    RightShift,      // >>
    Increment,       // ++
    Decrement,       // --
    Question,        // ?
    Colon,           // :
    Comma,           // ,
    Semicolon,       // ;
    Match,           // =~ (正規表現マッチ)
    NotMatch,        // !~ (正規表現非マッチ)
    
    // 区切り文字
    LeftBrace,       // {
    RightBrace,      // }
    LeftParen,       // (
    RightParen,      // )
    LeftBracket,     // [
    RightBracket,    // ]
    
    // 特殊
    Comment,         // // または /* */
    Newline,         // 改行
    Eof,             // ファイル終端
    Invalid          // エラートークン
};
```

#### 2.1.2 コメント

```yaya
// 行コメント（行末まで）

/*
 * ブロックコメント
 * 複数行対応
 */
```

#### 2.1.3 文字列リテラル

```yaya
// 基本文字列
"Hello, World"

// SakuraScript埋め込み
"\0\s[0]こんにちは\e"

// エスケープシーケンス
"改行\n タブ\t クォート\" バックスラッシュ\\"
```

**エスケープ処理**:
- `\n` → LF (0x0A)
- `\t` → TAB (0x09)
- `\"` → `"`
- `\\` → `\`
- その他 → そのまま（SakuraScript互換）

### 2.2 データ型

#### 2.2.1 基本型

```cpp
class Value {
public:
    enum class Type {
        Void,       // 未初期化・戻り値なし
        Integer,    // 整数（int64_t）
        Float,      // 浮動小数点（double）
        String,     // 文字列（std::string, UTF-8）
        Array,      // 配列（std::vector<Value>）
        Dict        // 連想配列（std::map<std::string, Value>）
    };
    
private:
    Type type_;
    std::variant<
        std::monostate,              // Void
        int64_t,                     // Integer
        double,                      // Float
        std::string,                 // String
        std::vector<Value>,          // Array
        std::map<std::string, Value> // Dict
    > data_;
};
```

#### 2.2.2 型変換規則

**暗黙的変換**:
```yaya
// 数値 → 文字列（算術演算外の文脈）
_var = 123 + "abc"  // "123abc"

// 文字列 → 数値（算術演算）
_num = "123" + 456  // 579

// 論理値（真偽判定）
// - 整数: 0 = false, 非0 = true
// - 文字列: "" = false, 非空 = true
// - 配列: 空 = false, 非空 = true
```

### 2.3 式と文

#### 2.3.1 式（Expressions）

```yaya
// 算術式
_result = (10 + 20) * 3 / 2

// 比較式
_is_greater = _a > _b

// 論理式
_both = (_a > 0) && (_b < 100)

// 三項演算子
_value = _condition ? "yes" : "no"

// 文字列連結
_greeting = "Hello, " + _name

// 配列アクセス
_item = _array[0]

// 関数呼び出し
_random = RAND(10)
```

#### 2.3.2 文（Statements）

```yaya
// 代入文
_var = 123

// 条件分岐
if _condition {
    // 真の場合
}
elseif _another {
    // 別の条件
}
else {
    // それ以外
}

// when文（値による分岐）
when _value {
    1: { "one" }
    2: { "two" }
    others: { "many" }
}

// while文
while _count < 10 {
    _count++
}

// foreach文
foreach _array; _item {
    // _itemで各要素にアクセス
}

// break/continue
break
continue

// return（関数終了・戻り値）
return _result
```

### 2.4 関数定義

#### 2.4.1 基本構文

```yaya
// 関数定義
FunctionName {
    // 処理
    return "result"
}

// 引数なし関数
OnBoot {
    "\0\s[0]起動しました\e"
}

// 引数あり関数（暗黙的パラメータ）
OnMouseClick {
    // reference[0], reference[1], ... で引数アクセス
    when reference[0] {
        0: { "\0\s[0]さくらがクリックされました" }
        1: { "\1\s[10]うにゅうがクリックされました" }
    }
}
```

#### 2.4.2 組み込み変数

**SHIORI固有**:
```yaya
reference[0]     // 第1引数
reference[1]     // 第2引数
reference[n]     // 第n+1引数

charset          // 文字コード（"UTF-8" など）
sender           // 送信元（"Ourin" など）
```

**システム変数**:
```yaya
// 実装予定
_argc            // 引数の数
_argv[n]         // 引数配列（reference[]のエイリアス）
```

### 2.5 組み込み関数

#### 2.5.1 Phase 1 必須関数

**乱数**:
```yaya
RAND(max)        // 0 〜 max-1 の整数乱数
```

**文字列操作**:
```yaya
STRLEN(str)      // 文字列長（UTF-8文字数）
STRSTR(hay, needle, [start])  // 部分文字列検索（位置返却、-1=未発見、start省略可）
SUBSTR(str, start, len)  // 部分文字列取得
TOUPPER(str)     // 大文字化
TOLOWER(str)     // 小文字化
```

**配列操作**:
```yaya
ARRAYSIZE(arr)   // 配列サイズ
IARRAY           // 空配列作成
```

**型変換**:
```yaya
TOINT(val)       // 整数化
TOSTR(val)       // 文字列化
```

**判定**:
```yaya
ISVAR(varname)   // 変数が定義済みか
ISFUNC(funcname) // 関数が定義済みか
```

#### 2.5.2 Phase 2 拡張関数

**正規表現**:
```yaya
RE_MATCH(str, pattern)     // マッチ判定
RE_SEARCH(str, pattern)    // マッチ位置
RE_REPLACE(str, pattern, replacement)  // 置換
```

**日時**:
```yaya
GETTIME[0]       // 年
GETTIME[1]       // 月
GETTIME[2]       // 日
GETTIME[3]       // 時
GETTIME[4]       // 分
GETTIME[5]       // 秒
```

**ファイル操作**:
```yaya
FOPEN(path, mode)
FREAD(handle)
FWRITE(handle, data)
FCLOSE(handle)
```

---

## 3. アーキテクチャ詳細

### 3.1 クラス構成

```
yaya_core/src/
├── main.cpp                    # エントリポイント
├── YayaCore.{cpp,hpp}          # コントローラー
├── DictionaryManager.{cpp,hpp} # 辞書管理
├── Lexer.{cpp,hpp}             # 字句解析
├── Parser.{cpp,hpp}            # 構文解析
├── AST.{cpp,hpp}               # 抽象構文木
├── VM.{cpp,hpp}                # 仮想マシン
├── Value.{cpp,hpp}             # 値型
├── FunctionRegistry.{cpp,hpp}  # 関数テーブル
├── VariableStore.{cpp,hpp}     # 変数ストレージ
├── BuiltinFunctions.{cpp,hpp}  # 組み込み関数
├── ShioriAdapter.{cpp,hpp}     # SHIORI変換
└── Utils.{cpp,hpp}             # ユーティリティ
```

### 3.2 字句解析器（Lexer）

#### 3.2.1 責務
- ファイル読み込み（UTF-8/CP932自動検出）
- トークン列への分割
- コメント除去
- エラー位置記録

#### 3.2.2 インターフェース

```cpp
class Lexer {
public:
    explicit Lexer(std::string source);
    
    std::vector<Token> tokenize();
    
private:
    std::string source_;
    size_t pos_;
    size_t line_;
    size_t column_;
    
    char peek();
    char advance();
    bool match(char expected);
    
    Token makeToken(TokenType type);
    Token makeString();
    Token makeNumber();
    Token makeIdentifier();
    
    void skipWhitespace();
    void skipLineComment();
    void skipBlockComment();
};
```

### 3.3 構文解析器（Parser）

#### 3.3.1 文法（簡略版BNF）

```
Program       := FunctionDef*
FunctionDef   := Identifier '{' Statement* '}'
Statement     := IfStmt | WhileStmt | ForEachStmt | ReturnStmt | ExprStmt
IfStmt        := 'if' Expression '{' Statement* '}' ElseClause?
ElseClause    := 'else' (IfStmt | '{' Statement* '}')
WhileStmt     := 'while' Expression '{' Statement* '}'
ForEachStmt   := 'foreach' Expression ';' Identifier '{' Statement* '}'
ReturnStmt    := 'return' Expression?
ExprStmt      := Expression

Expression    := Assignment
Assignment    := Ternary ('=' Assignment)?
Ternary       := LogicalOr ('?' Expression ':' Ternary)?
LogicalOr     := LogicalAnd ('||' LogicalAnd)*
LogicalAnd    := Equality ('&&' Equality)*
Equality      := Relational (('==' | '!=') Relational)*
Relational    := Additive (('<' | '>' | '<=' | '>=') Additive)*
Additive      := Multiplicative (('+' | '-') Multiplicative)*
Multiplicative := Unary (('*' | '/' | '%') Unary)*
Unary         := ('!' | '-' | '++' | '--') Unary | Postfix
Postfix       := Primary ('++' | '--' | '[' Expression ']' | '(' ArgList? ')')*
Primary       := Identifier | Number | String | '(' Expression ')'

ArgList       := Expression (',' Expression)*
```

#### 3.3.2 抽象構文木（AST）

```cpp
// 基底クラス
class ASTNode {
public:
    virtual ~ASTNode() = default;
    virtual Value evaluate(VM& vm) = 0;
};

// 式ノード
class ExpressionNode : public ASTNode { /* ... */ };
class BinaryOpNode : public ExpressionNode { /* ... */ };
class UnaryOpNode : public ExpressionNode { /* ... */ };
class LiteralNode : public ExpressionNode { /* ... */ };
class IdentifierNode : public ExpressionNode { /* ... */ };
class CallNode : public ExpressionNode { /* ... */ };

// 文ノード
class StatementNode : public ASTNode { /* ... */ };
class IfStatementNode : public StatementNode { /* ... */ };
class WhileStatementNode : public StatementNode { /* ... */ };
class ReturnStatementNode : public StatementNode { /* ... */ };

// 関数定義
class FunctionNode : public ASTNode {
public:
    std::string name;
    std::vector<std::shared_ptr<StatementNode>> body;
};
```

### 3.4 仮想マシン（VM）

#### 3.4.1 実行モデル

```cpp
class VM {
public:
    Value execute(const FunctionNode& func, const std::vector<Value>& args);
    
    // 変数アクセス
    Value getVariable(const std::string& name);
    void setVariable(const std::string& name, const Value& value);
    
    // 組み込み関数呼び出し
    Value callBuiltin(const std::string& name, const std::vector<Value>& args);
    
private:
    VariableStore variables_;
    FunctionRegistry functions_;
    BuiltinFunctions builtins_;
    
    // 実行スタック（関数呼び出し）
    struct CallFrame {
        std::string functionName;
        std::map<std::string, Value> localVars;
    };
    std::vector<CallFrame> callStack_;
};
```

#### 3.4.2 実行フロー

1. **関数呼び出し**
   - 新しいCallFrameをスタックに積む
   - ローカル変数スコープ作成
   - 引数を`reference[]`に設定

2. **文の実行**
   - ASTノードを再帰的に評価
   - 変数代入・関数呼び出し処理

3. **戻り値処理**
   - `return`文で明示的に返却
   - または関数末尾の式評価結果

4. **スタック解放**
   - CallFrameをpop
   - ローカル変数破棄

### 3.5 変数ストア

```cpp
class VariableStore {
public:
    Value get(const std::string& name);
    void set(const std::string& name, const Value& value);
    bool exists(const std::string& name);
    void clear();
    
private:
    std::unordered_map<std::string, Value> globals_;
    // スコープ管理（将来拡張）
};
```

**変数命名規則**:
- `_var`: ローカル変数（関数内）
- `var`: グローバル変数
- `reference[n]`: SHIORI引数（読み取り専用）

### 3.6 SHIORI アダプタ

#### 3.6.1 リクエスト処理

```cpp
class ShioriAdapter {
public:
    std::string processRequest(const std::string& method, 
                               const std::string& id,
                               const std::map<std::string, std::string>& headers,
                               const std::vector<std::string>& references);
    
private:
    VM& vm_;
    
    void setReferenceVariables(const std::vector<std::string>& refs);
    std::string buildResponse(const Value& result, int status);
};
```

#### 3.6.2 レスポンス形式

**GET成功時**:
```
SHIORI/3.0 200 OK
Charset: UTF-8
Sender: yaya_core

\0\s[0]こんにちは\e
```

**NOTIFY成功時**:
```
SHIORI/3.0 204 No Content
Charset: UTF-8
```

**エラー時**:
```
SHIORI/3.0 500 Internal Server Error
Charset: UTF-8

Error: Function 'Unknown' not found
```

---

## 4. 文字コード処理

### 4.1 対応エンコーディング

- **UTF-8**: 標準（推奨）
- **CP932** (Shift_JIS): Windows互換

### 4.2 自動検出アルゴリズム

```cpp
Encoding detectEncoding(const std::vector<uint8_t>& data) {
    // 1. BOMチェック
    if (hasUtf8Bom(data)) return Encoding::UTF8;
    
    // 2. UTF-8妥当性検証
    if (isValidUtf8(data)) return Encoding::UTF8;
    
    // 3. CP932とみなす（フォールバック）
    return Encoding::CP932;
}
```

### 4.3 変換処理

```cpp
std::string convertToUtf8(const std::vector<uint8_t>& data, Encoding enc) {
    if (enc == Encoding::UTF8) {
        return std::string(data.begin(), data.end());
    }
    
    // ICU使用
    UErrorCode status = U_ZERO_ERROR;
    UConverter* conv = ucnv_open("windows-932", &status);
    // ... 変換処理
    ucnv_close(conv);
    
    return utf8_result;
}
```

---

## 5. エラーハンドリング

### 5.1 エラー種別

```cpp
enum class ErrorType {
    LexicalError,    // 字句解析エラー
    SyntaxError,     // 構文エラー
    RuntimeError,    // 実行時エラー
    TypeError,       // 型エラー
    NameError,       // 未定義名
    FileError        // ファイルI/Oエラー
};

class YayaException : public std::exception {
public:
    YayaException(ErrorType type, const std::string& message, 
                  size_t line, size_t column);
    
    ErrorType type() const;
    std::string message() const;
    size_t line() const;
    size_t column() const;
};
```

### 5.2 エラー報告

**開発時（詳細）**:
```
Error: Undefined variable '_unknown'
  at line 42, column 15 in aya_bootend.dic
  
  41: if _condition {
  42:     _result = _unknown + 123
                    ^^^^^^^^^
  43: }
```

**本番時（簡潔）**:
```json
{
  "ok": false,
  "status": 500,
  "error": "RuntimeError: Undefined variable '_unknown' (aya_bootend.dic:42)"
}
```

---

## 6. パフォーマンス最適化

### 6.1 目標

- **辞書ロード**: < 500ms (Emily4全体)
- **関数実行**: < 10ms (OnBoot)
- **メモリ使用**: < 100MB (辞書ロード後)

### 6.2 最適化手法

#### 6.2.1 Phase 1（基本）
- ASTキャッシュ（再パース不要）
- 文字列インターン（重複文字列の共有）
- 関数テーブルのハッシュマップ化

#### 6.2.2 Phase 2（拡張）
- バイトコードコンパイル
- JIT コンパイル（LLVM使用、将来）
- メモリプール

### 6.3 プロファイリング

```bash
# Instruments（macOS標準）
instruments -t "Time Profiler" ./yaya_core

# Valgrind（メモリリーク検出）
valgrind --leak-check=full ./yaya_core < test_input.json
```

---

## 7. テスト仕様

### 7.1 ユニットテスト構成

```
yaya_core/tests/
├── lexer_test.cpp
├── parser_test.cpp
├── vm_test.cpp
├── builtin_test.cpp
└── integration_test.cpp
```

### 7.2 テストケース例

```cpp
// Lexerテスト
TEST(LexerTest, TokenizeString) {
    Lexer lex(R"("Hello, World")");
    auto tokens = lex.tokenize();
    ASSERT_EQ(tokens.size(), 2); // String + EOF
    EXPECT_EQ(tokens[0].type, TokenType::String);
    EXPECT_EQ(tokens[0].value, "Hello, World");
}

// Parserテスト
TEST(ParserTest, ParseFunctionDefinition) {
    Parser parser("OnBoot { \"test\" }");
    auto ast = parser.parse();
    ASSERT_EQ(ast.functions.size(), 1);
    EXPECT_EQ(ast.functions[0].name, "OnBoot");
}

// VMテスト
TEST(VMTest, ExecuteSimpleFunction) {
    VM vm;
    // ... 関数登録
    auto result = vm.execute("OnBoot", {});
    EXPECT_EQ(result.asString(), "\\0\\s[0]test\\e");
}
```

### 7.3 統合テスト

```cpp
TEST(IntegrationTest, LoadEmily4) {
    DictionaryManager dm;
    bool ok = dm.load({
        "emily4/ghost/master/aya_bootend.dic",
        // ... 他の辞書
    }, "utf-8");
    ASSERT_TRUE(ok);
    
    auto response = dm.execute("OnBoot", {});
    EXPECT_FALSE(response.empty());
    EXPECT_TRUE(response.find("\\0\\s[") != std::string::npos);
}
```

---

## 8. ライセンスとクレジット

### 8.1 YAYA Core ライセンス

**BSD-3-Clause License**（公式YAYA準拠）

```
Copyright (c) 2025, Ourin Project
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
...
```

### 8.2 依存ライブラリ

- **nlohmann/json**: MIT License
- **ICU**: Unicode License
- **Google Test**: BSD-3-Clause License

### 8.3 参考実装クレジット

本実装は以下を参考にしています:
- **YAYA (C++)**: https://github.com/YAYA-shiori/yaya-shiori (BSD-3-Clause)
- **yaya-rs (Rust)**: https://github.com/apxxxxxxe/yaya-rs (MIT)

---

## 9. バージョン履歴

- **1.0** (2025-10-16): 初版作成

---

**ドキュメント管理**  
- リポジトリ: https://github.com/eightman999/Ourin
- パス: `docs/YAYA_CORE_TECHNICAL_SPEC.md`
