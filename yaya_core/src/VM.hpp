#pragma once

#include "AST.hpp"
#include "Value.hpp"
#include <map>
#include <string>
#include <vector>
#include <functional>
#include <optional>
#include <nlohmann/json.hpp>
#include <random>
#include "RandomEngine.hpp"

// Callback interface for VM to request operations from host
class VMCallback {
public:
    virtual ~VMCallback() = default;
    
    // File I/O operations
    virtual nlohmann::json fileOperation(const std::string& op, const nlohmann::json& params) = 0;
    
    // Execute system command
    virtual nlohmann::json executeCommand(const std::string& command, bool wait) = 0;
    
    // Plugin/SAORI operations
    virtual nlohmann::json pluginOperation(const std::string& op, const nlohmann::json& params) = 0;

    // FMO (Forged Memory Object) 読み取り。op="read" でスナップショット文字列
    // （`id.key\x01value\r\n` 形式）を返す。デフォルトは未対応（空）。
    virtual nlohmann::json fmoOperation(const std::string& op, const nlohmann::json& params) {
        (void)op; (void)params;
        return nlohmann::json{{"ok", false}, {"error", "fmoOperation not implemented"}};
    }

    // Dynamic dictionary operations (Phase 6). Returns success flag.
    virtual bool dicLoad(const std::string& relativePath, const std::string& encoding) { (void)relativePath; (void)encoding; return false; }
    virtual bool dicUnload(const std::string& relativePath) { (void)relativePath; return false; }
};

class VM {
public:
    VM();
    
    // Set callback for host operations
    void setCallback(VMCallback* callback) { callback_ = callback; }

    /// One function declaration within the (possibly overloaded) registry.
    struct FunctionDecl {
        std::shared_ptr<AST::FunctionNode> node;
        int sourceId = 0;           // owning dictionary source id (0 = builtin/core)
        int declarationOrder = 0;   // global load order (stable iteration)
        bool enabled = true;        // toggled by UNDEFFUNC
        bool nonoverload = false;   // YAYA `nonoverload` attribute
        bool isWhen = false;        // YAYA `when` attribute
    };

    // Begin a new parse/load scope; functions registered afterwards belong to `sourceId`.
    // Returns the new source id. If sourceName is non-empty it is recorded for DICUNLOAD.
    int beginSource(const std::string& sourceName = "");
    // Register a function (attaches to the current source scope).
    void registerFunction(const std::string& name, std::shared_ptr<AST::FunctionNode> func);
    // Unregister every declaration owned by `sourceId` (DICUNLOAD).
    void unloadSource(int sourceId);
    // Find the source id whose name matches (DICUNLOAD by filename). Returns -1 if not found.
    int findSource(const std::string& sourceName) const;
    // Disable all enabled declarations of a function name (UNDEFFUNC).
    bool undefFunction(const std::string& name);
    // Read/modify declaration metadata (FUNCDECL_*).
    bool funcDeclRead(const std::string& name, std::string& out) const;
    bool funcDeclWrite(const std::string& name, const std::string& decl);
    bool funcDeclErase(const std::string& name);

    // Execute a function by name
    Value execute(const std::string& functionName, const std::vector<Value>& args);
    
    // Set/get variables
    void setVariable(const std::string& name, const Value& value);
    Value getVariable(const std::string& name) const;
    
    // Set reference values (from SHIORI request)
    void setReferences(const std::vector<std::string>& refs);

    // Check if a function is registered
    bool hasFunction(const std::string& name) const;

    // Set the ghost root path used to anchor relative persistence/DICLOAD paths.
    void setGhostRootPath(const std::string& path) { ghostRootPath_ = path; }
    std::string getGhostRootPath() const { return ghostRootPath_; }

    // 辞書ロード時プリプロセッサ (#globaldefine) からの登録口。
    // ISGLOBALDEFINE / SETGLOBALDEFINE / PROCESSGLOBALDEFINE と同じマップを共有する。
    void registerGlobalDefine(const std::string& name, const std::string& value) {
        globalDefines_[name] = value;
    }

private:
    VMCallback* callback_ = nullptr;
    // Function registry: supports multiple declarations per name (YAYA overload).
    std::map<std::string, std::vector<FunctionDecl>> functions_;
    // Source-id management for dictionary ownership (DICLOAD/DICUNLOAD).
    int nextSourceId_ = 1;
    int currentSourceId_ = 0;
    std::map<int, std::string> sourceNames_;
    int nextDeclarationOrder_ = 0;

    // Variable storage (global variables)
    std::map<std::string, Value> variables_;

    // Local variable scope stack (for variables starting with '_')
    std::vector<std::map<std::string, Value>> localScopes_;

    // SETDELIM/GETDELIM で設定する配列⇔文字列の既定区切り文字（SPLIT の区切り省略時に使用）
    std::string arrayDelimiter_ = ",";

    // SHIORI reference values
    std::vector<Value> references_;

    // Persistence/settings (Phase 7)
    std::string ghostRootPath_;                          // base dir for SAVEVAR/RESTOREVAR/DICLOAD
    std::map<std::string, Value> settings_;              // GETSETTING/SETSETTING store
    std::vector<std::string> tempVarNames_;              // SHIORI3FW.RegisterTempVar (not persisted)
    int lastError_ = 0;                                   // GETLASTERROR/SETLASTERROR
    std::string lastErrorDesc_;                           // optional last error description
    std::vector<std::string> errorLog_;                   // GETERRORLOG/CLEARERRORLOG

    // SAORI multi-value response storage (Phase 8): last REQUESTLIB extras.
    std::vector<Value> saoriValueex_;                     // valueex0, valueex1, ...
    std::string saoriCharset_;                            // CHARSETLIB default charset

    // Runtime global defines (Phase 10): name → replacement text.
    std::map<std::string, std::string> globalDefines_;

    // LSO() 用: 直近に評価された parallel（本家の {a,b,c} ランダム選択相当）で
    // 選ばれた候補のインデックス。未選択時は -1。
    int lastSelectedIndex_ = -1;

    // OUTPUTNUM() 用: 直近に execute() した array/sequential 関数が収集した候補数。
    int lastOutputNum_ = 0;

    // Built-in functions
    std::map<std::string, std::function<Value(const std::vector<Value>&)>> builtins_;

    // 直近の RE_SEARCH / RE_MATCH / RE_GREP のマッチ結果
    // （RE_GETSTR / RE_GETPOS / RE_GETLEN で取得する）
    std::vector<Value> reMatchStrings_;
    std::vector<Value> reMatchPositions_;
    std::vector<Value> reMatchLengths_;
    // RE_OPTION で設定する正規表現オプション（bit0: icase, bit1: multiline）
    int reOptions_ = 0;

    // 再帰深度制限（無限ループ防止）
    int recursion_depth_ = 0;
    static constexpr int MAX_RECURSION_DEPTH = 1000;

    // 実行タイムアウト（無限ループ防止）
    std::chrono::steady_clock::time_point execution_start_time_;
    static constexpr int MAX_EXECUTION_TIME_MS = 120000; // 120秒（load()初期化用）

    // Early return exception for control flow
    struct ReturnException {
        Value value;
        explicit ReturnException(const Value& v) : value(v) {}
    };

    // Loop control-flow exceptions (caught by While/For/Foreach loops)
    struct BreakException {};
    struct ContinueException {};

    // Execution helpers
    Value executeNode(std::shared_ptr<AST::Node> node);
    Value executeBlock(const std::vector<std::shared_ptr<AST::Node>>& statements);
    // Execute a single function declaration body honoring its type modifier (array/sequential/void).
    // Used both for direct calls and overload concatenation.
    Value executeFunctionDecl(const FunctionDecl& decl);
    Value evaluateBinaryOp(const std::string& op, const Value& left, const Value& right);
    Value evaluateUnaryOp(const std::string& op, const Value& operand);
    Value callBuiltin(const std::string& name, const std::vector<Value>& args);
    std::string interpolateString(const std::string& str);

    // YAYA 前置 '&'（参照渡し）の解決用ヘルパ。
    // ノードが UnaryOpNode("&", operand) で、operand が変数または配列要素参照なら
    // その格納位置を表す RefTarget を返す（配列添字はこの時点で評価する）。
    struct RefTarget {
        std::string varName;
        bool hasIndex = false;
        int arrayIdx = 0;
    };
    std::optional<RefTarget> tryResolveReference(std::shared_ptr<AST::Node> node);
    Value readReference(const RefTarget& target);
    void writeReference(const RefTarget& target, const Value& value);
    
    // Register built-in functions
    void registerBuiltins();
};
