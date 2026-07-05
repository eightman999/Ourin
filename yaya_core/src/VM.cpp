#include "VM.hpp"
#include "Lexer.hpp"
#include "Parser.hpp"
#include <random>
#include <stdexcept>
#include <ctime>
#include <cmath>
#include <algorithm>
#include <cctype>
#include <cstdint>
#include <chrono>
#include <set>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <thread>
#include <sys/wait.h>
#include <regex>
#include <unordered_set>
#include "Digest.hpp"
#include "Base64.hpp"

namespace {

// UTF-8 バイト列をコードポイント配列にデコードする。
// 不正なバイトは置換せず、そのまま 1 バイト = 1 コードポイントとして扱い、
// 元の文字列を壊さない（往復で同一バイト列に戻せる範囲を優先）。
std::vector<uint32_t> decodeUtf8(const std::string& s) {
    std::vector<uint32_t> out;
    size_t i = 0;
    const size_t n = s.size();
    while (i < n) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        uint32_t cp;
        size_t len;
        if (c < 0x80) { cp = c; len = 1; }
        else if ((c & 0xE0) == 0xC0) { cp = c & 0x1F; len = 2; }
        else if ((c & 0xF0) == 0xE0) { cp = c & 0x0F; len = 3; }
        else if ((c & 0xF8) == 0xF0) { cp = c & 0x07; len = 4; }
        else { out.push_back(c); i++; continue; } // 不正な先頭バイト
        if (i + len > n) { out.push_back(c); i++; continue; } // 途中で切れている
        bool valid = true;
        for (size_t k = 1; k < len; k++) {
            unsigned char cc = static_cast<unsigned char>(s[i + k]);
            if ((cc & 0xC0) != 0x80) { valid = false; break; }
            cp = (cp << 6) | (cc & 0x3F);
        }
        if (!valid) { out.push_back(c); i++; continue; }
        out.push_back(cp);
        i += len;
    }
    return out;
}

// 単一コードポイントを UTF-8 バイト列に追記する。
void appendUtf8(std::string& out, uint32_t cp) {
    if (cp < 0x80) {
        out.push_back(static_cast<char>(cp));
    } else if (cp < 0x800) {
        out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else if (cp < 0x10000) {
        out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else {
        out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    }
}

// 全角英数字・記号・空白を半角へ変換する（ZEN2HAN）。
// 対象: 全角 ASCII 変種 U+FF01..U+FF5E と全角スペース U+3000。
// それ以外のコードポイント（漢字・かな等）はそのまま保持する。
std::string convertZenToHan(const std::string& s) {
    std::vector<uint32_t> cps = decodeUtf8(s);
    std::string out;
    out.reserve(s.size());
    for (uint32_t cp : cps) {
        if (cp >= 0xFF01 && cp <= 0xFF5E) {
            cp -= 0xFEE0; // 全角 ASCII -> 半角 ASCII
        } else if (cp == 0x3000) {
            cp = 0x0020; // 全角スペース -> 半角スペース
        }
        appendUtf8(out, cp);
    }
    return out;
}

// 半角英数字・記号・空白を全角へ変換する（HAN2ZEN）。
// 対象: 半角 ASCII U+0021..U+007E と半角スペース U+0020。
std::string convertHanToZen(const std::string& s) {
    std::vector<uint32_t> cps = decodeUtf8(s);
    std::string out;
    out.reserve(s.size() * 2);
    for (uint32_t cp : cps) {
        if (cp >= 0x0021 && cp <= 0x007E) {
            cp += 0xFEE0; // 半角 ASCII -> 全角 ASCII
        } else if (cp == 0x0020) {
            cp = 0x3000; // 半角スペース -> 全角スペース
        }
        appendUtf8(out, cp);
    }
    return out;
}

// UTF-8 文字数（コードポイント数）を返す。
size_t utf8Length(const std::string& s) {
    return decodeUtf8(s).size();
}

// コードポイント列を [start, start+count) で切り出して UTF-8 文字列に再構築する。
// start/count は文字（コードポイント）単位。範囲はクランプする。
std::string utf8Slice(const std::vector<uint32_t>& cps, size_t start, size_t count) {
    std::string out;
    size_t n = cps.size();
    if (start > n) start = n;
    size_t end = start + count;
    if (end > n || count > n) end = n; // オーバーフロー対策込み
    for (size_t i = start; i < end; i++) appendUtf8(out, cps[i]);
    return out;
}

// printf 風の書式整形。サポートする変換: d i u s f g e x X o c %。
// フラグ/幅/精度（例: %05d, %-10s, %.2f, %+d）を許容し、各指定子に対して
// 次の引数を消費する。整数系は asInt、f/g/e は asReal、s は asString で型変換する。
std::string formatPrintf(const std::string& format, const std::vector<Value>& args, size_t argStart) {
    std::string result;
    size_t argIndex = argStart;
    size_t i = 0;
    const size_t n = format.size();
    while (i < n) {
        char c = format[i];
        if (c != '%') { result += c; i++; continue; }
        // '%' の解析開始
        size_t specStart = i;
        i++; // skip '%'
        if (i < n && format[i] == '%') { result += '%'; i++; continue; }
        // フラグ・幅・精度・変換文字を含む書式指定子を抽出する
        std::string spec = "%";
        // フラグ
        while (i < n && (format[i] == '-' || format[i] == '+' || format[i] == ' ' ||
                         format[i] == '#' || format[i] == '0')) {
            spec += format[i]; i++;
        }
        // 幅
        while (i < n && std::isdigit(static_cast<unsigned char>(format[i]))) { spec += format[i]; i++; }
        // 精度
        if (i < n && format[i] == '.') {
            spec += format[i]; i++;
            while (i < n && std::isdigit(static_cast<unsigned char>(format[i]))) { spec += format[i]; i++; }
        }
        if (i >= n) { result += format.substr(specStart); break; } // 不完全 -> そのまま出力
        char conv = format[i];
        i++;
        const Value* arg = (argIndex < args.size()) ? &args[argIndex] : nullptr;
        char buf[256];
        switch (conv) {
            case 'd': case 'i': {
                spec += "lld";
                long long v = arg ? static_cast<long long>(arg->asInt()) : 0;
                std::snprintf(buf, sizeof(buf), spec.c_str(), v);
                result += buf; argIndex++;
                break;
            }
            case 'u': case 'x': case 'X': case 'o': {
                spec += "ll"; spec += conv;
                unsigned long long v = arg ? static_cast<unsigned long long>(static_cast<long long>(arg->asInt())) : 0;
                std::snprintf(buf, sizeof(buf), spec.c_str(), v);
                result += buf; argIndex++;
                break;
            }
            case 'f': case 'g': case 'e': case 'E': case 'G': case 'F': {
                spec += conv;
                double v = arg ? arg->asReal() : 0.0;
                std::snprintf(buf, sizeof(buf), spec.c_str(), v);
                result += buf; argIndex++;
                break;
            }
            case 'c': {
                spec += 'c';
                int v = arg ? arg->asInt() : 0;
                std::snprintf(buf, sizeof(buf), spec.c_str(), v);
                result += buf; argIndex++;
                break;
            }
            case 's': {
                spec += 's';
                std::string sv = arg ? arg->asString() : std::string();
                int needed = std::snprintf(nullptr, 0, spec.c_str(), sv.c_str());
                if (needed < 0) { result += sv; }
                else {
                    std::vector<char> dyn(static_cast<size_t>(needed) + 1);
                    std::snprintf(dyn.data(), dyn.size(), spec.c_str(), sv.c_str());
                    result += dyn.data();
                }
                argIndex++;
                break;
            }
            default:
                // 未知の変換 -> 指定子をそのまま出力する
                result += format.substr(specStart, i - specStart);
                break;
        }
    }
    return result;
}

} // namespace

VM::VM() {
    registerBuiltins();
}

int VM::beginSource(const std::string& sourceName) {
    currentSourceId_ = nextSourceId_++;
    if (!sourceName.empty()) {
        sourceNames_[currentSourceId_] = sourceName;
    }
    return currentSourceId_;
}

void VM::registerFunction(const std::string& name, std::shared_ptr<AST::FunctionNode> func) {
    FunctionDecl decl;
    decl.node = func;
    decl.sourceId = currentSourceId_;
    decl.declarationOrder = nextDeclarationOrder_++;
    // functionType modifiers are encoded in node->functionType; pull attributes out.
    const std::string& ft = func ? func->functionType : "";
    decl.nonoverload = (ft.find("nonoverload") != std::string::npos);
    decl.isWhen = (ft.find("when") != std::string::npos);
    // nonoverload semantics: a name declared nonoverload (now or previously) does
    // NOT accumulate — redefinition replaces. We keep all declarations in the
    // vector (so dicUnload can still retract by source), and the dispatcher picks
    // the last registered enabled declaration. Here we only need to drop earlier
    // declarations of the same name once the name has entered nonoverload mode.
    auto& vec = functions_[name];
    bool nameIsNonoverload = decl.nonoverload;
    for (const auto& d : vec) if (d.nonoverload) { nameIsNonoverload = true; break; }
    if (nameIsNonoverload) {
        vec.clear();
    }
    vec.push_back(std::move(decl));
}

void VM::unloadSource(int sourceId) {
    if (sourceId <= 0) return;
    for (auto& kv : functions_) {
        auto& vec = kv.second;
        vec.erase(std::remove_if(vec.begin(), vec.end(),
                                 [sourceId](const FunctionDecl& d) { return d.sourceId == sourceId; }),
                  vec.end());
    }
    // Drop empty entries so hasFunction/ISFUNC behave correctly.
    for (auto it = functions_.begin(); it != functions_.end(); ) {
        if (it->second.empty()) it = functions_.erase(it);
        else ++it;
    }
    sourceNames_.erase(sourceId);
}

int VM::findSource(const std::string& sourceName) const {
    if (sourceName.empty()) return -1;
    // Compare by basename so callers can pass "foo.dic" without a full path.
    auto basename = [](const std::string& p) -> std::string {
        auto pos = p.find_last_of("/\\");
        return (pos == std::string::npos) ? p : p.substr(pos + 1);
    };
    std::string want = basename(sourceName);
    for (const auto& kv : sourceNames_) {
        if (basename(kv.second) == want) return kv.first;
    }
    return -1;
}

bool VM::undefFunction(const std::string& name) {
    auto it = functions_.find(name);
    if (it == functions_.end()) return false;
    bool any = false;
    for (auto& d : it->second) {
        if (d.enabled) { d.enabled = false; any = true; }
    }
    return any;
}

bool VM::funcDeclRead(const std::string& name, std::string& out) const {
    auto it = functions_.find(name);
    if (it == functions_.end() || it->second.empty()) return false;
    const auto& decl = it->second.front();
    out = decl.node ? decl.node->functionType : "";
    return true;
}

bool VM::funcDeclWrite(const std::string& name, const std::string& decl) {
    auto it = functions_.find(name);
    if (it == functions_.end() || it->second.empty()) return false;
    if (it->second.front().node) {
        it->second.front().node->functionType = decl;
    }
    // re-derive attribute flags
    it->second.front().nonoverload = (decl.find("nonoverload") != std::string::npos);
    it->second.front().isWhen = (decl.find("when") != std::string::npos);
    return true;
}

bool VM::funcDeclErase(const std::string& name) {
    auto it = functions_.find(name);
    if (it == functions_.end()) return false;
    functions_.erase(it);
    return true;
}

Value VM::execute(const std::string& functionName, const std::vector<Value>& args) {
    // 空の関数名は無視（EVALで空文字列が渡されることがある）
    if (functionName.empty()) {
        std::cerr << "[VM::execute] WARNING: Empty function name, returning void" << std::endl;
        return Value();
    }

    // 再帰深度チェック（無限ループ防止）
    recursion_depth_++;
    if (recursion_depth_ > MAX_RECURSION_DEPTH) {
        std::cerr << "[VM::execute] ERROR: Maximum recursion depth (" << MAX_RECURSION_DEPTH
                  << ") exceeded while calling: " << functionName << std::endl;
        recursion_depth_--;
        return Value();
    }

    // 再帰深度が深い場合は警告（デバッグ用）
    if (recursion_depth_ > 100 && recursion_depth_ % 100 == 0) {
        std::cerr << "[VM::execute] WARNING: Recursion depth is " << recursion_depth_
                  << " while calling: " << functionName << std::endl;
    }

    if (recursion_depth_ <= 2) {
        std::cerr << "[VM::execute] [depth=" << recursion_depth_ << "] Looking for function: " << functionName << std::endl;
    }

    // Check if it's a built-in function
    if (builtins_.find(functionName) != builtins_.end()) {
        Value result = callBuiltin(functionName, args);
        recursion_depth_--;
        return result;
    }

    // Check if it's a user-defined function
    auto it = functions_.find(functionName);
    if (it == functions_.end() || it->second.empty()) {
        std::cerr << "[VM::execute] WARNING: Function not found: \"" << functionName << "\", returning void" << std::endl;
        recursion_depth_--;
        return Value();
    }

    // Gather enabled declarations in declaration order.
    std::vector<const FunctionDecl*> active;
    for (const auto& d : it->second) {
        if (d.enabled) active.push_back(&d);
    }
    if (active.empty()) {
        std::cerr << "[VM::execute] WARNING: Function disabled: \"" << functionName << "\", returning void" << std::endl;
        recursion_depth_--;
        return Value();
    }

    std::cerr << "[VM::execute] Found user function: " << functionName
              << " (" << active.size() << " decl(s)), executing..." << std::endl;
    auto exec_start = std::chrono::steady_clock::now();

    // トップレベル関数の場合、実行開始時刻を記録
    if (recursion_depth_ == 1) {
        execution_start_time_ = exec_start;
    }

    // Push new local variable scope (YAYA: variables starting with '_' are function-local)
    localScopes_.emplace_back();

    // Set _argv / _argc for this function call (now goes to local scope)
    std::vector<Value> argArray;
    for (const auto& a : args) {
        argArray.push_back(a);
    }
    setVariable("_argv", Value(argArray));
    setVariable("_argc", Value(static_cast<int>(args.size())));

    // Dispatch: nonoverload (or single declaration) runs only the first enabled
    // declaration. Otherwise (YAYA overload default) every declaration runs in
    // declaration order and their return values concatenate.
    Value result;
    bool anyNonoverload = false;
    for (const auto* d : active) { if (d->nonoverload) { anyNonoverload = true; break; } }

    if (active.size() == 1 || anyNonoverload) {
        result = executeFunctionDecl(*active.front());
    } else {
        // Overload concatenation: gather each declaration's result.
        std::vector<Value> collected;
        for (const auto* d : active) {
            Value v = executeFunctionDecl(*d);
            if (!v.isVoid()) collected.push_back(v);
        }
        // Determine target type from the first declaration.
        const std::string& ftype0 = active.front()->node ? active.front()->node->functionType : "";
        if (ftype0.find("array") != std::string::npos) {
            // Flatten: if each overload returns an array, concat their elements.
            std::vector<Value> flat;
            for (const auto& v : collected) {
                if (v.getType() == Value::Type::Array) {
                    for (const auto& e : v.asArray()) flat.push_back(e);
                } else {
                    flat.push_back(v);
                }
            }
            result = Value(flat);
        } else {
            std::string s;
            for (const auto& v : collected) s += v.asString();
            result = Value(s);
        }
    }

    // Pop local variable scope
    localScopes_.pop_back();

    auto exec_end = std::chrono::steady_clock::now();
    auto exec_duration = std::chrono::duration_cast<std::chrono::milliseconds>(exec_end - exec_start).count();
    std::cerr << "[VM::execute] Function execution complete: " << functionName << " (took " << exec_duration << "ms)";
    if (recursion_depth_ <= 3) {
        std::string rv = result.asString();
        if (rv.size() > 100) rv = rv.substr(0, 100) + "...";
        std::cerr << " => \"" << rv << "\"";
    }
    std::cerr << std::endl;

    recursion_depth_--;
    return result;
}

// Execute one function declaration body honoring its type modifier
// (array/sequential/void). Used both for direct and overload calls.
Value VM::executeFunctionDecl(const FunctionDecl& decl) {
    if (!decl.node) return Value();
    const auto& body = decl.node->body;
    const std::string& ftype = decl.node->functionType;

    bool isArray = (ftype.find("array") != std::string::npos);
    bool isSequential = (ftype.find("sequential") != std::string::npos);

    if (isArray || isSequential) {
        std::vector<Value> collected;
        try {
            for (const auto& stmt : body) {
                // parallel 文: 式の返す配列を個々の候補として展開（1段フラット化）
                if (stmt && stmt->type == AST::NodeType::Parallel) {
                    auto* par = dynamic_cast<AST::ParallelNode*>(stmt.get());
                    Value pv = executeNode(par->expr);
                    if (pv.getType() == Value::Type::Array) {
                        for (const auto& elem : pv.asArray()) {
                            collected.push_back(elem);
                        }
                    } else if (!pv.isVoid()) {
                        collected.push_back(pv);
                    }
                    continue;
                }
                Value v = executeNode(stmt);
                if (stmt && stmt->type != AST::NodeType::Assignment && !v.isVoid()) {
                    collected.push_back(v);
                }
            }
        } catch (const ReturnException& ret) {
            collected.clear();
            collected.push_back(ret.value);
        }
        if (isArray) {
            return Value(collected);
        } else {
            std::string s;
            for (const auto& v : collected) s += v.asString();
            return Value(s);
        }
    }

    Value result;
    try {
        result = executeBlock(body);
    } catch (const ReturnException& ret) {
        result = ret.value;
    }
    if (ftype.find("void") != std::string::npos) {
        result = Value();
    }
    return result;
}

void VM::setVariable(const std::string& name, const Value& value) {
    if (!name.empty() && name[0] == '_' && !localScopes_.empty()) {
        localScopes_.back()[name] = value;
    } else {
        variables_[name] = value;
    }
}

Value VM::getVariable(const std::string& name) const {
    if (!name.empty() && name[0] == '_' && !localScopes_.empty()) {
        auto& scope = localScopes_.back();
        auto it = scope.find(name);
        if (it != scope.end()) {
            return it->second;
        }
        return Value();
    }
    auto it = variables_.find(name);
    if (it != variables_.end()) {
        return it->second;
    }
    return Value(); // Return void for undefined variables
}

void VM::setReferences(const std::vector<std::string>& refs) {
    references_.clear();
    for (const auto& ref : refs) {
        references_.push_back(Value(ref));
    }
}

bool VM::hasFunction(const std::string& name) const {
    auto it = functions_.find(name);
    if (it == functions_.end()) return false;
    // Must have at least one enabled declaration.
    for (const auto& d : it->second) {
        if (d.enabled) return true;
    }
    return false;
}

Value VM::executeNode(std::shared_ptr<AST::Node> node) {
    if (!node) return Value();

    // タイムアウトチェック（無限ループ防止）
    if (recursion_depth_ > 0) { // トップレベル関数内でのみチェック
        auto now = std::chrono::steady_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - execution_start_time_).count();
        if (elapsed > MAX_EXECUTION_TIME_MS) {
            std::cerr << "[VM::executeNode] ERROR: Execution timeout (" << MAX_EXECUTION_TIME_MS
                      << "ms) exceeded. Aborting..." << std::endl;
            return Value(); // 空のValueを返して処理を中断
        }
    }

    switch (node->type) {
        case AST::NodeType::Literal: {
            auto* lit = dynamic_cast<AST::LiteralNode*>(node.get());
            if (lit->isString) {
                // Interpolate embedded expressions in string literals
                std::string interpolated = interpolateString(lit->value);
                return Value(interpolated);
            } else {
                try {
                    const std::string& s = lit->value;
                    // Support hex literals like 0xFF / 0Xff
                    if (s.size() > 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
                        // Parse hex (skip 0x prefix)
                        int v = std::stoi(s.substr(2), nullptr, 16);
                        return Value(v);
                    }
                    // Real literal: contains a decimal point
                    if (s.find('.') != std::string::npos) {
                        return Value(std::stod(s));
                    }
                    // Decimal fallback
                    return Value(std::stoi(s, nullptr, 10));
                } catch (...) {
                    return Value(0);
                }
            }
        }
        
        case AST::NodeType::Variable: {
            auto* var = dynamic_cast<AST::VariableNode*>(node.get());
            // First try as a variable
            Value val = getVariable(var->name);
            if (!val.isVoid()) {
                return val;
            }
            // If variable doesn't exist, try as a function call (YAYA allows bare function names)
            if (functions_.find(var->name) != functions_.end() || builtins_.find(var->name) != builtins_.end()) {
                return execute(var->name, {});
            }
            return Value();
        }
        
        case AST::NodeType::BinaryOp: {
            auto* binOp = dynamic_cast<AST::BinaryOpNode*>(node.get());
            auto left = executeNode(binOp->left);
            auto right = executeNode(binOp->right);
            return evaluateBinaryOp(binOp->op, left, right);
        }
        
        case AST::NodeType::UnaryOp: {
            auto* unOp = dynamic_cast<AST::UnaryOpNode*>(node.get());
            auto operand = executeNode(unOp->operand);
            return evaluateUnaryOp(unOp->op, operand);
        }
        
        case AST::NodeType::Ternary: {
            auto* ternary = dynamic_cast<AST::TernaryNode*>(node.get());
            auto condition = executeNode(ternary->condition);
            if (condition.toBool()) {
                return executeNode(ternary->trueBranch);
            } else {
                return executeNode(ternary->falseBranch);
            }
        }
        
        case AST::NodeType::Assignment: {
            auto* assign = dynamic_cast<AST::AssignmentNode*>(node.get());
            auto value = executeNode(assign->value);
            if (assign->variableName.find("SHIORI3FW") == 0) {
                std::cerr << "[VM::assign] " << assign->variableName << " = \"" << value.asString().substr(0, 50) << "\"" << std::endl;
            }
            setVariable(assign->variableName, value);
            return value;
        }
        
        case AST::NodeType::If: {
            auto* ifNode = dynamic_cast<AST::IfNode*>(node.get());
            auto condition = executeNode(ifNode->condition);
            if (condition.toBool()) {
                return executeBlock(ifNode->thenBody);
            } else {
                return executeBlock(ifNode->elseBody);
            }
        }

        case AST::NodeType::Parallel: {
            // 非 array 文脈の parallel: 配列から1要素を等確率で選択して返す
            // （array/sequential 関数の候補収集は executeFunctionDecl 側で展開する）
            auto* par = dynamic_cast<AST::ParallelNode*>(node.get());
            Value v = executeNode(par->expr);
            if (v.getType() == Value::Type::Array) {
                const auto& arr = v.asArray();
                if (arr.empty()) return Value();
                std::uniform_int_distribution<size_t> dis(0, arr.size() - 1);
                return arr[dis(yaya_rng::engine())];
            }
            return v;
        }
        
        case AST::NodeType::While: {
            auto* whileNode = dynamic_cast<AST::WhileNode*>(node.get());
            Value result;
            while (executeNode(whileNode->condition).toBool()) {
                try {
                    result = executeBlock(whileNode->body);
                } catch (const ContinueException&) {
                    continue;
                } catch (const BreakException&) {
                    break;
                }
            }
            return result;
        }

        case AST::NodeType::For: {
            auto* forNode = dynamic_cast<AST::ForNode*>(node.get());
            Value result;
            // Run the initializer once.
            if (forNode->init) executeNode(forNode->init);
            // Missing condition is treated as always true.
            while (!forNode->cond || executeNode(forNode->cond).toBool()) {
                try {
                    result = executeBlock(forNode->body);
                } catch (const ContinueException&) {
                    // fall through to increment
                } catch (const BreakException&) {
                    break;
                }
                if (forNode->incr) executeNode(forNode->incr);
            }
            return result;
        }

        case AST::NodeType::Foreach: {
            auto* feNode = dynamic_cast<AST::ForeachNode*>(node.get());
            Value result;
            Value arrayVal = executeNode(feNode->arrayExpr);
            if (arrayVal.getType() == Value::Type::Array) {
                const auto& arr = arrayVal.asArray();
                // Snapshot elements so mutation of the source array mid-loop is safe.
                std::vector<Value> elems(arr.begin(), arr.end());
                for (const auto& elem : elems) {
                    setVariable(feNode->varName, elem);
                    try {
                        result = executeBlock(feNode->body);
                    } catch (const ContinueException&) {
                        continue;
                    } catch (const BreakException&) {
                        break;
                    }
                }
            }
            return result;
        }
        
        case AST::NodeType::Call: {
            auto* call = dynamic_cast<AST::CallNode*>(node.get());
            
            // Handle special array operations
            if (call->functionName == "__array_literal__") {
                // Create an array from the arguments
                std::vector<Value> elements;
                for (const auto& argNode : call->arguments) {
                    elements.push_back(executeNode(argNode));
                }
                return Value(elements);
            }
            
            if (call->functionName == "__array_concat_assign__") {
                // Array concatenation assignment: var ,= value
                if (call->arguments.size() >= 2) {
                    auto* varNode = dynamic_cast<AST::VariableNode*>(call->arguments[0].get());
                    if (varNode) {
                        Value currentValue = getVariable(varNode->name);
                        Value newValue = executeNode(call->arguments[1]);
                        
                        // If current value is not an array, make it one
                        if (currentValue.getType() != Value::Type::Array) {
                            currentValue = Value(std::vector<Value>());
                        }
                        
                        // Concatenate
                        currentValue.arrayConcat(newValue);
                        setVariable(varNode->name, currentValue);
                        return currentValue;
                    }
                }
                return Value();
            }

            // Range/slice: __range__(base, start, length)
            // YAYA syntax: str[start, length] or array[start, count]
            if (call->functionName == "__range__") {
                if (call->arguments.size() == 3) {
                    Value base = executeNode(call->arguments[0]);
                    int start = executeNode(call->arguments[1]).asInt();
                    int len   = executeNode(call->arguments[2]).asInt();

                    if (base.getType() == Value::Type::String) {
                        std::string s = base.asString();
                        if (start < 0) start = 0;
                        if (start >= static_cast<int>(s.size())) return Value(std::string(""));
                        if (len < 0) len = 0;
                        return Value(s.substr(start, len));
                    }
                    if (base.getType() == Value::Type::Array) {
                        const auto& arr = base.asArray();
                        std::vector<Value> sub;
                        for (int i = start; i < start + len && i < static_cast<int>(arr.size()); i++) {
                            if (i >= 0) sub.push_back(arr[i]);
                        }
                        return Value(sub);
                    }
                }
                return Value();
            }

            // Generic indexing on any expression: __index__(base, index)
            if (call->functionName == "__index__") {
                if (call->arguments.size() == 2) {
                    Value base = executeNode(call->arguments[0]);
                    Value idxV = executeNode(call->arguments[1]);
                    int idx = idxV.asInt();

                    if (base.getType() == Value::Type::Array) {
                        return base.arrayGet(idx);
                    }

                    // Special handling if base was a variable named 'reference'
                    if (auto* varNode = dynamic_cast<AST::VariableNode*>(call->arguments[0].get())) {
                        if (varNode->name == "reference") {
                            if (idx >= 0 && idx < static_cast<int>(references_.size())) {
                                return references_[idx];
                            }
                            return Value();
                        }
                    }

                    return Value();
                }
                return Value();
            }
            
            // Increment / decrement: __postinc__, __postdec__, __preinc__, __predec__
            // Mutate the operand variable and return the appropriate value.
            static const std::set<std::string> incdecOps = {
                "__postinc__", "__postdec__", "__preinc__", "__predec__"
            };
            if (incdecOps.count(call->functionName) && call->arguments.size() == 1) {
                // Operand must be a plain variable to mutate; otherwise safe no-op.
                auto* var = dynamic_cast<AST::VariableNode*>(call->arguments[0].get());
                if (!var) {
                    return executeNode(call->arguments[0]);
                }
                Value preVal = getVariable(var->name);
                int delta = (call->functionName == "__postinc__" ||
                             call->functionName == "__preinc__") ? 1 : -1;
                Value newVal = evaluateBinaryOp("+", preVal, Value(delta));
                setVariable(var->name, newVal);
                bool isPost = (call->functionName == "__postinc__" ||
                               call->functionName == "__postdec__");
                return isPost ? preVal : newVal;
            }

            // Assignment operators: __assign__, __plus_assign__, etc.
            static const std::set<std::string> assignOps = {
                "__assign__", "__plus_assign__", "__minus_assign__",
                "__star_assign__", "__slash_assign__", "__percent_assign__",
                "__concat_assign__"
            };
            if (assignOps.count(call->functionName) &&
                call->arguments.size() == 2) {
                auto rhs = executeNode(call->arguments[1]);

                // Determine target variable name from LHS AST node
                std::string varName;
                int arrayIdx = -1;
                if (auto* var = dynamic_cast<AST::VariableNode*>(call->arguments[0].get())) {
                    varName = var->name;
                } else if (auto* acc = dynamic_cast<AST::ArrayAccessNode*>(call->arguments[0].get())) {
                    varName = acc->arrayName;
                    arrayIdx = executeNode(acc->index).asInt();
                }

                if (!varName.empty()) {
                    if (call->functionName == "__assign__") {
                        if (arrayIdx >= 0) {
                            Value arr = getVariable(varName);
                            arr.arraySet(arrayIdx, rhs);
                            setVariable(varName, arr);
                        } else {
                            setVariable(varName, rhs);
                        }
                        return rhs;
                    }
                    // Compound assignments
                    Value current = (arrayIdx >= 0) ? getVariable(varName).arrayGet(arrayIdx) : getVariable(varName);
                    Value result;
                    if (call->functionName == "__plus_assign__") {
                        result = evaluateBinaryOp("+", current, rhs);
                    } else if (call->functionName == "__minus_assign__") {
                        result = evaluateBinaryOp("-", current, rhs);
                    } else if (call->functionName == "__star_assign__") {
                        result = evaluateBinaryOp("*", current, rhs);
                    } else if (call->functionName == "__slash_assign__") {
                        result = evaluateBinaryOp("/", current, rhs);
                    } else if (call->functionName == "__percent_assign__") {
                        result = evaluateBinaryOp("%", current, rhs);
                    } else if (call->functionName == "__concat_assign__") {
                        // YAYA ,= operator: array append or string concat
                        if (current.getType() == Value::Type::Array) {
                            current.arrayConcat(rhs);
                            result = current;
                        } else {
                            result = Value(current.asString() + rhs.asString());
                        }
                    } else {
                        result = rhs;
                    }
                    if (arrayIdx >= 0) {
                        Value arr = getVariable(varName);
                        arr.arraySet(arrayIdx, result);
                        setVariable(varName, arr);
                    } else {
                        setVariable(varName, result);
                    }
                    return result;
                }
                return Value();
            }

            // E.Swap(&a, &b): YAYA の参照渡し（&）で2つの変数/配列要素を in-place 交換する。
            // 両引数が前置 '&' の参照であれば元の格納場所へ書き戻す。E.Swap は void。
            if (call->functionName == "E.Swap" && call->arguments.size() == 2) {
                auto refA = tryResolveReference(call->arguments[0]);
                auto refB = tryResolveReference(call->arguments[1]);
                if (refA && refB) {
                    Value va = readReference(*refA);
                    Value vb = readReference(*refB);
                    writeReference(*refA, vb);
                    writeReference(*refB, va);
                }
                return Value();
            }

            // Regular function call
            std::vector<Value> args;
            for (const auto& argNode : call->arguments) {
                args.push_back(executeNode(argNode));
            }
            return execute(call->functionName, args);
        }
        
        case AST::NodeType::ArrayAccess: {
            auto* access = dynamic_cast<AST::ArrayAccessNode*>(node.get());
            auto indexVal = executeNode(access->index);
            int index = indexVal.asInt();
            
            // Special case for "reference" array (SHIORI references)
            if (access->arrayName == "reference") {
                if (index >= 0 && index < static_cast<int>(references_.size())) {
                    return references_[index];
                }
                return Value();
            }
            
            // For other arrays, get from variables
            Value arrayVar = getVariable(access->arrayName);
            if (arrayVar.getType() == Value::Type::Array) {
                return arrayVar.arrayGet(index);
            }
            
            return Value();
        }
        
        case AST::NodeType::Switch: {
            auto* switchNode = dynamic_cast<AST::SwitchNode*>(node.get());
            auto switchVal = executeNode(switchNode->expression);
            int index = switchVal.asInt();
            
            // Return the case at the given index
            if (index >= 0 && index < static_cast<int>(switchNode->cases.size())) {
                return executeNode(switchNode->cases[index]);
            }
            
            return Value();
        }

        case AST::NodeType::Case: {
            // YAYA case/when: evaluate the case expression EXACTLY ONCE, then run the
            // first 'when' clause whose match values contain an equal value. If none match,
            // run the 'others'/'default' fallback. Non-selected bodies must not execute.
            auto* caseNode = dynamic_cast<AST::CaseNode*>(node.get());
            Value testValue = executeNode(caseNode->expression);

            for (const auto& clause : caseNode->whenClauses) {
                bool matched = false;
                for (const auto& mv : clause->matchValues) {
                    Value mvValue = executeNode(mv);
                    if (testValue == mvValue) {
                        matched = true;
                        break;
                    }
                }
                if (matched) {
                    return executeBlock(clause->body);
                }
            }

            // Fallback: others/default
            if (!caseNode->othersBody.empty()) {
                return executeBlock(caseNode->othersBody);
            }
            return Value();
        }

        case AST::NodeType::WhenClause: {
            // case 式の外に現れた standalone `when` 句。
            // YAYA では `when` は常に case のディスパッチ対象であり、単独で現れることは
            // 仕様上ない。case コンテキストを欠く WhenClause は対応する switch 値が存在しない
            // ためマッチ判定できない。したがって本体を無条件に実行するのは誤り（重複発話や
            // 副作用の誘発になる）であり、ここでは何も実行しない。
            // ※ case 内の when は CaseNode ハンドラが処理するため、ここへは到達しない。
            // ※ {{LABEL}} ブロック内で漏れ出た when も同様に安全のためスキップする。
            (void)node;
            return Value();
        }
        
        case AST::NodeType::Return: {
            auto* returnNode = dynamic_cast<AST::ReturnNode*>(node.get());
            Value returnValue = returnNode->value ? executeNode(returnNode->value) : Value();
            throw ReturnException(returnValue);
        }
        
        case AST::NodeType::Block: {
            auto* block = dynamic_cast<AST::BlockNode*>(node.get());
            return executeBlock(block->statements);
        }

        case AST::NodeType::Break: {
            // Unwind to the nearest enclosing loop (caught in While/For/Foreach).
            throw BreakException();
        }

        case AST::NodeType::Continue: {
            // Skip to the next iteration of the nearest enclosing loop.
            throw ContinueException();
        }
        
        default:
            return Value();
    }
}

Value VM::executeBlock(const std::vector<std::shared_ptr<AST::Node>>& statements) {
    Value lastValue;
    for (const auto& stmt : statements) {
        Value v = executeNode(stmt);
        // 代入文は出力候補にならない（本家YAYA準拠）。副作用のみ実行し、
        // ブロックの値には反映しない（if の分岐値として配列代入が漏れるのを防ぐ）
        if (stmt && stmt->type != AST::NodeType::Assignment) {
            lastValue = v;
        }
    }
    return lastValue;
}

Value VM::evaluateBinaryOp(const std::string& op, const Value& left, const Value& right) {
    if (op == "+") return left + right;
    if (op == "-") return left - right;
    if (op == "*") return left * right;
    if (op == "/") return left / right;
    if (op == "%") return left % right;
    if (op == "==") return Value(left == right ? 1 : 0);
    if (op == "!=") return Value(left != right ? 1 : 0);
    if (op == "<") return Value(left < right ? 1 : 0);
    if (op == ">") return Value(left > right ? 1 : 0);
    if (op == "<=") return Value(left <= right ? 1 : 0);
    if (op == ">=") return Value(left >= right ? 1 : 0);
    if (op == "&&") return Value(left.toBool() && right.toBool() ? 1 : 0);
    if (op == "||") return Value(left.toBool() || right.toBool() ? 1 : 0);
    // '&' is integer bitwise-AND (per Ourin/YAYA spec: BitwiseAnd)
    if (op == "&") return Value(left.asInt() & right.asInt());
    if (op == "_in_") {
        // String contains check: "substring" _in_ "full string"
        // or array contains check: "value" _in_ array
        if (right.getType() == Value::Type::Array) {
            // Check if left is in array right
            const auto& arr = right.asArray();
            for (const auto& elem : arr) {
                if (elem == left) {
                    return Value(1);
                }
            }
            return Value(0);
        } else {
            // String contains check
            std::string haystack = right.asString();
            std::string needle = left.asString();
            return Value(haystack.find(needle) != std::string::npos ? 1 : 0);
        }
    }
    return Value();
}

Value VM::evaluateUnaryOp(const std::string& op, const Value& operand) {
    if (op == "!") return Value(!operand.toBool() ? 1 : 0);
    if (op == "-") {
        if (operand.isReal()) return Value(-operand.asReal());
        return Value(-operand.asInt());
    }
    // 前置 '&'（YAYA 参照演算子）: 汎用フォールバック。
    // 真の参照渡しは Call サイトで tryResolveReference 経由で解決し、参照を取る
    // ビルトイン（E.Swap 等）が in-place で格納場所へ書き戻す。ここに到達するのは
    // 「参照を受け取らない関数へ &x を渡した」等のケースで、値渡し（恒等）が正しい挙動。
    if (op == "&") return operand;
    return Value();
}

std::optional<VM::RefTarget> VM::tryResolveReference(std::shared_ptr<AST::Node> node) {
    auto* unary = dynamic_cast<AST::UnaryOpNode*>(node.get());
    if (!unary || unary->op != "&") return std::nullopt;
    const auto& operand = unary->operand;
    if (auto* var = dynamic_cast<AST::VariableNode*>(operand.get())) {
        return RefTarget{ var->name, false, 0 };
    }
    if (auto* acc = dynamic_cast<AST::ArrayAccessNode*>(operand.get())) {
        int idx = executeNode(acc->index).asInt();
        return RefTarget{ acc->arrayName, true, idx };
    }
    return std::nullopt;
}

Value VM::readReference(const RefTarget& target) {
    Value v = getVariable(target.varName);
    if (target.hasIndex) {
        return v.arrayGet(target.arrayIdx);
    }
    return v;
}

void VM::writeReference(const RefTarget& target, const Value& value) {
    if (target.hasIndex) {
        Value arr = getVariable(target.varName);
        arr.arraySet(target.arrayIdx, value);
        setVariable(target.varName, arr);
    } else {
        setVariable(target.varName, value);
    }
}

Value VM::callBuiltin(const std::string& name, const std::vector<Value>& args) {
    auto it = builtins_.find(name);
    if (it != builtins_.end()) {
        return it->second(args);
    }
    return Value();
}

void VM::registerBuiltins() {
    // RAND(max) or RAND(array) - Returns a random number from 0 to max-1, or random element from array
    builtins_["RAND"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);

        // If argument is an array, return a random element
        if (args[0].getType() == Value::Type::Array) {
            size_t size = args[0].arraySize();
            if (size == 0) return Value();
            std::uniform_int_distribution<> dis(0, static_cast<int>(size) - 1);
            return args[0].arrayGet(dis(yaya_rng::engine()));
        }

        // Otherwise, treat as integer max value
        int max = args[0].asInt();
        if (max <= 0) return Value(0);
        std::uniform_int_distribution<> dis(0, max - 1);
        return Value(dis(yaya_rng::engine()));
    };
    
    // STRLEN(str) - 文字列の長さ（UTF-8 コードポイント数）を返す
    builtins_["STRLEN"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        return Value(static_cast<int>(utf8Length(args[0].asString())));
    };
    
    // STRFORM(format, ...) - printf 風の書式整形
    // 指定子 %d %i %u %s %f %g %e %x %X %o %c %% をサポートし、フラグ/幅/精度を許容する。
    builtins_["STRFORM"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        std::string format = args[0].asString();
        return Value(formatPrintf(format, args, 1));
    };

    // SPRINTF(format, ...) - STRFORM と同一動作のエイリアス
    builtins_["SPRINTF"] = builtins_["STRFORM"];
    
    // GETTIME[index] - Get current time component
    builtins_["GETTIME"] = [](const std::vector<Value>& args) -> Value {
        std::time_t t = std::time(nullptr);
        std::tm* now = std::localtime(&t);
        if (args.empty()) return Value(0);
        int index = args[0].asInt();
        switch (index) {
            case 0: return Value(now->tm_year + 1900); // Year
            case 1: return Value(now->tm_mon + 1);     // Month
            case 2: return Value(now->tm_mday);        // Day
            case 3: return Value(now->tm_wday);        // Day of week
            case 4: return Value(now->tm_hour);        // Hour
            case 5: return Value(now->tm_min);         // Minute
            case 6: return Value(now->tm_sec);         // Second
            default: return Value(0);
        }
    };
    
    // ISVAR(varname) - Check if variable exists
    builtins_["ISVAR"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string varName = args[0].asString();
        return Value(variables_.find(varName) != variables_.end() ? 1 : 0);
    };
    
    // ISFUNC(funcname) - Check if function exists
    builtins_["ISFUNC"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        return Value(hasFunction(args[0].asString()) ? 1 : 0);
    };
    
    // EVAL(funcname) - Execute a function by name
    builtins_["EVAL"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value();

        // EVAL can work in multiple modes:
        // 1. EVAL("functionName") - call a function with no args
        // 2. EVAL("functionName", arg1, arg2, ...) - call a function with args
        // 3. EVAL("expression") - parse and evaluate an expression/statement

        std::string firstArg = args[0].asString();

        // If there are additional arguments, definitely a function call
        if (args.size() > 1) {
            std::vector<Value> funcArgs;
            for (size_t i = 1; i < args.size(); i++) {
                funcArgs.push_back(args[i]);
            }
            return execute(firstArg, funcArgs);
        }

        // Single argument: Try as function call first, then as expression
        // Check if it's a known function name
        if (hasFunction(firstArg) ||
            builtins_.find(firstArg) != builtins_.end()) {
            return execute(firstArg, {});
        }

        // Check if the string looks like a simple identifier (potential function name)
        // YAYA function names can contain dots (e.g., SHIORI3FW.ResetAITalkInterval)
        bool looksLikeIdentifier = !firstArg.empty();
        for (char c : firstArg) {
            if (!std::isalnum(static_cast<unsigned char>(c)) && c != '_' && c != '.') {
                looksLikeIdentifier = false;
                break;
            }
        }

        if (looksLikeIdentifier) {
            Value variableValue = getVariable(firstArg);
            if (!variableValue.isVoid()) {
                return variableValue;
            }
        }

        if (looksLikeIdentifier) {
            // Try to execute as function name, even if not found
            // This handles cases where functions are called before being fully registered
            try {
                return execute(firstArg, {});
            } catch (...) {
                // Function doesn't exist, fall through to expression parsing
            }
        }

        // Not a function name, parse and evaluate as an expression/statement body.
        // Parser::parse() expects top-level dictionary functions, so wrap the
        // snippet in a temporary function and execute its body in the current VM
        // context. This keeps YAYA idioms like EVAL('"text %(var)"') working.
        try {
            Lexer lexer("__eval_expr__ {\n" + firstArg + "\n}");
            Parser parser(lexer.tokenize());
            auto functions = parser.parse();

            Value result;
            for (const auto& fn : functions) {
                if (fn && fn->name == "__eval_expr__") {
                    try {
                        result = executeBlock(fn->body);
                    } catch (const ReturnException& ret) {
                        result = ret.value;
                    }
                    break;
                }
            }
            return result;
        } catch (const std::exception& e) {
            // If parsing fails, might be an undefined function - return void
            std::cerr << "[EVAL] Failed to evaluate: \"" << firstArg << "\" - " << e.what() << std::endl;
            return Value();
        }
    };

    // E.EvalEmbedValue(str) - Emily/AYA helper: expand %(expr) fragments in SakuraScript.
    builtins_["E.EvalEmbedValue"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(std::string(""));
        const std::string input = args[0].asString();
        std::string output;
        size_t pos = 0;

        auto findExpressionEnd = [](const std::string& s, size_t start) -> size_t {
            int depth = 1;
            char quote = '\0';
            for (size_t i = start; i < s.size(); i++) {
                char c = s[i];
                if (quote != '\0') {
                    if (c == quote) quote = '\0';
                    continue;
                }
                if (c == '\'' || c == '"') {
                    quote = c;
                } else if (c == '(') {
                    depth++;
                } else if (c == ')') {
                    depth--;
                    if (depth == 0) return i;
                }
            }
            return std::string::npos;
        };

        while (pos < input.size()) {
            size_t marker = input.find("%(", pos);
            if (marker == std::string::npos) {
                output += input.substr(pos);
                break;
            }

            output += input.substr(pos, marker - pos);
            size_t exprStart = marker + 2;
            size_t exprEnd = findExpressionEnd(input, exprStart);
            if (exprEnd == std::string::npos) {
                output += input.substr(marker);
                break;
            }

            std::string expr = input.substr(exprStart, exprEnd - exprStart);
            output += callBuiltin("EVAL", {Value(expr)}).asString();
            pos = exprEnd + 1;
        }

        return Value(output);
    };
    
    // ARRAYSIZE(arr) - Get array size
    builtins_["ARRAYSIZE"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        if (args[0].getType() == Value::Type::Array) {
            return Value(static_cast<int>(args[0].arraySize()));
        }
        return Value(0);
    };
    
    // IARRAY - Create empty array
    builtins_["IARRAY"] = [](const std::vector<Value>& args) -> Value {
        (void)args;
        return Value(std::vector<Value>());
    };
    
    // ===== Type Conversion Functions =====
    
    // TOINT(value) - Convert to integer
    builtins_["TOINT"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        return Value(args[0].asInt());
    };
    
    // TOSTR(value) - Convert to string
    builtins_["TOSTR"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        return Value(args[0].asString());
    };
    
    // TOREAL(value) - Convert to real (floating-point)
    builtins_["TOREAL"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0.0);
        return Value(args[0].asReal());
    };
    
    // GETTYPE(value) - YAYA 標準の型コードを返す（0=void,1=int,2=real,3=string,4=array,5=dict）
    builtins_["GETTYPE"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        switch (args[0].getType()) {
            case Value::Type::Void: return Value(0);
            case Value::Type::Integer: return Value(1);
            case Value::Type::Real: return Value(2);
            case Value::Type::String: return Value(3);
            case Value::Type::Array: return Value(4);
            case Value::Type::Dictionary: return Value(5);
            default: return Value(0);
        }
    };
    
    // CVINT, CVSTR, CVREAL - Aliases for TOINT, TOSTR, TOREAL
    builtins_["CVINT"] = builtins_["TOINT"];
    builtins_["CVSTR"] = builtins_["TOSTR"];
    builtins_["CVREAL"] = builtins_["TOREAL"];
    
    // ===== String Operations =====
    
    // TOUPPER(str) - Convert to uppercase
    builtins_["TOUPPER"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        std::string str = args[0].asString();
        for (char& c : str) {
            c = std::toupper(c);
        }
        return Value(str);
    };
    
    // TOLOWER(str) - Convert to lowercase
    builtins_["TOLOWER"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        std::string str = args[0].asString();
        for (char& c : str) {
            c = std::tolower(c);
        }
        return Value(str);
    };
    
    // STRSTR(haystack, needle, [start]) - Find substring position (-1 if not found)
    // Optional third parameter specifies starting position for search
    builtins_["STRSTR"] = [this](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(-1);
        std::string haystack = args[0].asString();
        std::string needle = args[1].asString();

        // Optional start position (default: 0)
        int start = (args.size() >= 3) ? args[2].asInt() : 0;

        // Validate start position - allow start == length (search from end)
        if (start < 0 || start > static_cast<int>(haystack.length())) {
            return Value(-1);
        }

        // Search from start position
        size_t pos = haystack.find(needle, start);
        int result = (pos == std::string::npos ? -1 : static_cast<int>(pos));

        // Debug logging for troubleshooting infinite loops
        static int call_count = 0;
        call_count++;
        if (call_count <= 20 || call_count % 10 == 0) {
            std::string hay_preview = haystack.length() > 50 ?
                haystack.substr(0, 47) + "..." : haystack;
            std::cerr << "[STRSTR #" << call_count << "] "
                      << "haystack=\"" << hay_preview << "\" (len=" << haystack.length() << ")"
                      << ", needle=\"" << needle << "\""
                      << ", start=" << start
                      << " => " << result << std::endl;
        }

        return Value(result);
    };
    
    // SUBSTR(str, pos, len) - 部分文字列を抽出（pos/len は UTF-8 文字単位、0 始まり）
    builtins_["SUBSTR"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value("");
        std::string str = args[0].asString();
        std::vector<uint32_t> cps = decodeUtf8(str);
        int clen = static_cast<int>(cps.size());
        int pos = args[1].asInt();
        if (pos < 0 || pos >= clen) return Value("");

        int len = (args.size() >= 3) ? args[2].asInt() : (clen - pos);
        if (len < 0) return Value("");

        return Value(utf8Slice(cps, static_cast<size_t>(pos), static_cast<size_t>(len)));
    };
    
    // REPLACE(str, old, new) - Replace all occurrences
    builtins_["REPLACE"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 3) return Value("");
        std::string str = args[0].asString();
        std::string oldStr = args[1].asString();
        std::string newStr = args[2].asString();
        
        if (oldStr.empty()) return Value(str);
        
        size_t pos = 0;
        while ((pos = str.find(oldStr, pos)) != std::string::npos) {
            str.replace(pos, oldStr.length(), newStr);
            pos += newStr.length();
        }
        return Value(str);
    };
    
    // ERASE(str, pos, len) - 部分文字列を削除（pos/len は UTF-8 文字単位、0 始まり）
    builtins_["ERASE"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value("");
        std::string str = args[0].asString();
        std::vector<uint32_t> cps = decodeUtf8(str);
        int clen = static_cast<int>(cps.size());
        int pos = args[1].asInt();
        if (pos < 0 || pos >= clen) return Value(str);

        int len = (args.size() >= 3) ? args[2].asInt() : (clen - pos);
        if (len < 0) len = 0;

        // [0, pos) と [pos+len, end) を連結する
        std::string out = utf8Slice(cps, 0, static_cast<size_t>(pos));
        out += utf8Slice(cps, static_cast<size_t>(pos) + static_cast<size_t>(len),
                         cps.size());
        return Value(out);
    };
    
    // INSERT(str, pos, insertion) - 指定位置に文字列を挿入（pos は UTF-8 文字単位、0 始まり）
    builtins_["INSERT"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 3) return Value("");
        std::string str = args[0].asString();
        std::vector<uint32_t> cps = decodeUtf8(str);
        int clen = static_cast<int>(cps.size());
        int pos = args[1].asInt();
        std::string insertion = args[2].asString();

        if (pos < 0) pos = 0;
        if (pos > clen) pos = clen;

        std::string out = utf8Slice(cps, 0, static_cast<size_t>(pos));
        out += insertion;
        out += utf8Slice(cps, static_cast<size_t>(pos), cps.size());
        return Value(out);
    };
    
    // CUTSPACE(str) - Trim whitespace
    builtins_["CUTSPACE"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        std::string str = args[0].asString();
        
        // Trim leading whitespace
        size_t start = str.find_first_not_of(" \t\n\r");
        if (start == std::string::npos) return Value("");
        
        // Trim trailing whitespace
        size_t end = str.find_last_not_of(" \t\n\r");
        return Value(str.substr(start, end - start + 1));
    };
    
    // CHR(code, ...) - Convert ASCII codes to characters (supports multiple arguments)
    builtins_["CHR"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        std::string result;
        for (const auto& arg : args) {
            int code = arg.asInt();
            if (code >= 0 && code <= 255) {
                result += static_cast<char>(code);
            }
        }
        return Value(result);
    };
    
    // CHRCODE(str) - Get ASCII code of first character
    builtins_["CHRCODE"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string str = args[0].asString();
        if (str.empty()) return Value(0);
        return Value(static_cast<int>(static_cast<unsigned char>(str[0])));
    };
    
    // ===== Math Operations =====
    
    // FLOOR(value) - Round down (returns Real holding an integral value)
    builtins_["FLOOR"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0.0);
        return Value(std::floor(args[0].asReal()));
    };

    // CEIL(value) - Round up
    builtins_["CEIL"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0.0);
        return Value(std::ceil(args[0].asReal()));
    };

    // ROUND(value) - Round to nearest
    builtins_["ROUND"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0.0);
        return Value(std::round(args[0].asReal()));
    };

    // SQRT(value) - Square root
    builtins_["SQRT"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0.0);
        return Value(std::sqrt(args[0].asReal()));
    };

    // POW(base, exp) - Power
    builtins_["POW"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(0.0);
        return Value(std::pow(args[0].asReal(), args[1].asReal()));
    };

    // LOG(value) - Natural logarithm
    builtins_["LOG"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0.0);
        double val = args[0].asReal();
        if (val <= 0) return Value(0.0);
        return Value(std::log(val));
    };

    // LOG10(value) - Base-10 logarithm
    builtins_["LOG10"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0.0);
        double val = args[0].asReal();
        if (val <= 0) return Value(0.0);
        return Value(std::log10(val));
    };

    // EXP(value) - e raised to value
    builtins_["EXP"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0.0);
        return Value(std::exp(args[0].asReal()));
    };

    // SIN(value) - Sine
    builtins_["SIN"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0.0);
        return Value(std::sin(args[0].asReal()));
    };

    // COS(value) - Cosine
    builtins_["COS"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0.0);
        return Value(std::cos(args[0].asReal()));
    };

    // TAN(value) - Tangent
    builtins_["TAN"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0.0);
        return Value(std::tan(args[0].asReal()));
    };

    // ASIN(value) - Arc sine
    builtins_["ASIN"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0.0);
        return Value(std::asin(args[0].asReal()));
    };

    // ACOS(value) - Arc cosine
    builtins_["ACOS"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0.0);
        return Value(std::acos(args[0].asReal()));
    };

    // ATAN(value) - Arc tangent
    builtins_["ATAN"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0.0);
        return Value(std::atan(args[0].asReal()));
    };

    // SINH(value) - Hyperbolic sine
    builtins_["SINH"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0.0);
        return Value(std::sinh(args[0].asReal()));
    };

    // COSH(value) - Hyperbolic cosine
    builtins_["COSH"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0.0);
        return Value(std::cosh(args[0].asReal()));
    };

    // TANH(value) - Hyperbolic tangent
    builtins_["TANH"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0.0);
        return Value(std::tanh(args[0].asReal()));
    };
    
    // SRAND(seed) - Seed random number generator
    // RAND/ANY と Value::asString() の array→文字列（雑談配列のランダム選択）が共有する
    // yaya_rng::engine() を再シードする。これにより SRAND 呼び出し以降のランダム選択列が
    // 決定的に再現可能になる。
    builtins_["SRAND"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        yaya_rng::engine().seed(static_cast<std::mt19937::result_type>(args[0].asInt()));
        return Value(1);
    };
    
    // ===== Array Operations =====
    
    // SPLIT(str, delim) - Split string into array
    builtins_["SPLIT"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(std::vector<Value>());
        std::string str = args[0].asString();
        // 区切りが省略された場合は SETDELIM で設定したカレント区切りを使う（YAYA 準拠）
        std::string delim = (args.size() >= 2) ? args[1].asString() : arrayDelimiter_;

        // Optional third parameter: max number of splits (0 = unlimited)
        int maxSplits = (args.size() >= 3) ? args[2].asInt() : 0;

        static int split_call_count = 0;
        split_call_count++;

        std::vector<Value> result;
        if (delim.empty()) {
            // Split into individual characters
            for (char c : str) {
                result.push_back(Value(std::string(1, c)));
                if (maxSplits > 0 && result.size() >= static_cast<size_t>(maxSplits)) {
                    break;
                }
            }
        } else {
            size_t pos = 0;
            size_t found;
            int splitCount = 0;

            while ((found = str.find(delim, pos)) != std::string::npos) {
                result.push_back(Value(str.substr(pos, found - pos)));
                pos = found + delim.length();
                splitCount++;

                // If max splits reached, add remainder and stop
                if (maxSplits > 0 && splitCount >= maxSplits - 1) {
                    result.push_back(Value(str.substr(pos)));
                    if (split_call_count <= 5 || split_call_count % 10 == 0) {
                        std::cerr << "[SPLIT #" << split_call_count << "] "
                                  << "str=\"" << str << "\", delim=\"" << delim << "\", maxSplits=" << maxSplits
                                  << " => [" << result.size() << " elements, early return]" << std::endl;
                    }
                    return Value(result);
                }
            }
            // Add the last part
            result.push_back(Value(str.substr(pos)));
        }

        if (split_call_count <= 5 || split_call_count % 10 == 0) {
            std::cerr << "[SPLIT #" << split_call_count << "] "
                      << "str=\"" << str << "\", delim=\"" << delim << "\", maxSplits=" << maxSplits
                      << " => [" << result.size() << " elements]" << std::endl;
        }

        return Value(result);
    };
    
    // ASEARCH(array, value) - Search array for value, return index (-1 if not found)
    builtins_["ASEARCH"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(-1);
        if (args[0].getType() != Value::Type::Array) return Value(-1);
        
        const auto& arr = args[0].asArray();
        const Value& searchVal = args[1];
        
        for (size_t i = 0; i < arr.size(); i++) {
            if (arr[i] == searchVal) {
                return Value(static_cast<int>(i));
            }
        }
        return Value(-1);
    };
    
    // ASORT(array) - Sort array (simplified - sorts as strings)
    builtins_["ASORT"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(std::vector<Value>());
        if (args[0].getType() != Value::Type::Array) return args[0];
        
        std::vector<Value> result = args[0].asArray();
        std::sort(result.begin(), result.end(), [](const Value& a, const Value& b) {
            return a.asString() < b.asString();
        });
        
        return Value(result);
    };
    
    // ARRAYDEDUP(array) - Remove duplicates from array
    builtins_["ARRAYDEDUP"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(std::vector<Value>());
        if (args[0].getType() != Value::Type::Array) return args[0];
        
        const auto& arr = args[0].asArray();
        std::vector<Value> result;
        
        for (const auto& val : arr) {
            bool found = false;
            for (const auto& existing : result) {
                if (existing == val) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                result.push_back(val);
            }
        }
        
        return Value(result);
    };
    
    // ANY(array) - Return random element from array
    builtins_["ANY"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value();
        if (args[0].getType() != Value::Type::Array) return args[0];

        const auto& arr = args[0].asArray();
        if (arr.empty()) return Value();

        std::uniform_int_distribution<size_t> dis(0, arr.size() - 1);

        return arr[dis(yaya_rng::engine())];
    };
    
    // ===== Type Checking =====
    
    // ISINTSTR(str) - Check if string is integer
    builtins_["ISINTSTR"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string str = args[0].asString();
        if (str.empty()) return Value(0);
        
        size_t start = 0;
        if (str[0] == '+' || str[0] == '-') start = 1;
        
        if (start >= str.length()) return Value(0);
        
        for (size_t i = start; i < str.length(); i++) {
            if (!std::isdigit(str[i])) return Value(0);
        }
        
        return Value(1);
    };
    
    // ISREALSTR(str) - Check if string is real number
    builtins_["ISREALSTR"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string str = args[0].asString();
        if (str.empty()) return Value(0);
        
        size_t start = 0;
        if (str[0] == '+' || str[0] == '-') start = 1;
        
        bool hasDigit = false;
        bool hasDot = false;
        
        for (size_t i = start; i < str.length(); i++) {
            if (std::isdigit(str[i])) {
                hasDigit = true;
            } else if (str[i] == '.' && !hasDot) {
                hasDot = true;
            } else {
                return Value(0);
            }
        }
        
        return Value(hasDigit ? 1 : 0);
    };
    
    // ===== Bitwise Operations =====
    
    // BITWISE_AND(a, b) - Bitwise AND
    builtins_["BITWISE_AND"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(0);
        return Value(args[0].asInt() & args[1].asInt());
    };
    
    // BITWISE_OR(a, b) - Bitwise OR
    builtins_["BITWISE_OR"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(0);
        return Value(args[0].asInt() | args[1].asInt());
    };
    
    // BITWISE_XOR(a, b) - Bitwise XOR
    builtins_["BITWISE_XOR"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(0);
        return Value(args[0].asInt() ^ args[1].asInt());
    };
    
    // BITWISE_NOT(a) - Bitwise NOT
    builtins_["BITWISE_NOT"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        return Value(~args[0].asInt());
    };
    
    // BITWISE_SHIFT(value, shift) - Bitwise shift (positive = left, negative = right)
    builtins_["BITWISE_SHIFT"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(0);
        int value = args[0].asInt();
        int shift = args[1].asInt();
        
        if (shift >= 0) {
            return Value(value << shift);
        } else {
            return Value(value >> (-shift));
        }
    };
    
    // ===== Hex/Binary Conversions =====
    
    // TOHEXSTR(value, digits) - Convert to hex string
    builtins_["TOHEXSTR"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        int value = args[0].asInt();
        int digits = (args.size() >= 2) ? args[1].asInt() : 8;
        
        char buf[32];
        snprintf(buf, sizeof(buf), "%0*X", digits, value);
        return Value(std::string(buf));
    };
    
    // HEXSTRTOI(hexstr) - Convert hex string to integer
    builtins_["HEXSTRTOI"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string str = args[0].asString();
        
        try {
            return Value(static_cast<int>(std::stoul(str, nullptr, 16)));
        } catch (...) {
            return Value(0);
        }
    };
    
    // TOBINSTR(value, digits) - Convert to binary string
    builtins_["TOBINSTR"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        int value = args[0].asInt();
        int digits = (args.size() >= 2) ? args[1].asInt() : 32;
        
        std::string result;
        for (int i = digits - 1; i >= 0; i--) {
            result += ((value >> i) & 1) ? '1' : '0';
        }
        return Value(result);
    };
    
    // BINSTRTOI(binstr) - Convert binary string to integer
    builtins_["BINSTRTOI"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string str = args[0].asString();
        
        try {
            return Value(static_cast<int>(std::stoul(str, nullptr, 2)));
        } catch (...) {
            return Value(0);
        }
    };
    
    // ===== Variable/Function Management =====
    
    // ERASEVAR(varname) - Delete a variable
    builtins_["ERASEVAR"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string varName = args[0].asString();
        auto it = variables_.find(varName);
        if (it != variables_.end()) {
            variables_.erase(it);
            return Value(1);
        }
        return Value(0);
    };
    
    // GETFUNCLIST(prefix) - Get list of user-defined functions matching prefix
    builtins_["GETFUNCLIST"] = [this](const std::vector<Value>& args) -> Value {
        std::string prefix;
        if (!args.empty()) {
            prefix = args[0].asString();
        }
        std::vector<Value> result;
        for (const auto& pair : functions_) {
            // Only list names that have at least one enabled declaration.
            bool enabled = false;
            for (const auto& d : pair.second) if (d.enabled) { enabled = true; break; }
            if (!enabled) continue;
            if (prefix.empty() || pair.first.compare(0, prefix.size(), prefix) == 0) {
                result.push_back(Value(pair.first));
            }
        }
        return Value(result);
    };
    
    // GETVARLIST() - Get list of variables
    builtins_["GETVARLIST"] = [this](const std::vector<Value>& args) -> Value {
        (void)args;
        std::vector<Value> result;
        for (const auto& pair : variables_) {
            result.push_back(Value(pair.first));
        }
        return Value(result);
    };
    
    // GETSYSTEMFUNCLIST() - Get list of system/built-in functions
    builtins_["GETSYSTEMFUNCLIST"] = [this](const std::vector<Value>& args) -> Value {
        (void)args;
        std::vector<Value> result;
        for (const auto& pair : builtins_) {
            result.push_back(Value(pair.first));
        }
        return Value(result);
    };
    
    // ===== System Operations =====
    
    // GETTICKCOUNT() - Get milliseconds since epoch (simplified)
    builtins_["GETTICKCOUNT"] = [](const std::vector<Value>& args) -> Value {
        (void)args;
        auto now = std::chrono::system_clock::now();
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch());
        return Value(static_cast<int>(ms.count()));
    };
    
    // GETSECCOUNT() - Get seconds since epoch
    builtins_["GETSECCOUNT"] = [](const std::vector<Value>& args) -> Value {
        (void)args;
        return Value(static_cast<int>(std::time(nullptr)));
    };
    
    // GETENV(varname) - Get environment variable
    builtins_["GETENV"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        std::string varName = args[0].asString();
        const char* val = std::getenv(varName.c_str());
        return Value(val ? std::string(val) : "");
    };
    
    // ===== File Operations =====
    // File operations restricted to ghost directory for security
    // File handles stored in a map for management
    
    // File handle management (shared between file operation functions)
    static std::map<int, std::unique_ptr<std::fstream>> fileHandles;
    static int nextHandle = 1;
    static std::string ghostBasePath; // Will be set when ghost loads
    
    // Helper to validate path is within ghost directory
    auto isPathSafe = [](const std::string& path) -> bool {
        // For now, allow relative paths only (no absolute paths, no .. )
        if (path.empty()) return false;
        if (path[0] == '/') return false;  // No absolute paths
        if (path.find("..") != std::string::npos) return false; // No parent directory access
        return true;
    };
    
    // FOPEN(filename, mode) - Open file
    builtins_["FOPEN"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(-1);
        std::string filename = args[0].asString();
        std::string mode = args[1].asString();
        
        // Security check
        if (filename.empty() || filename[0] == '/' || filename.find("..") != std::string::npos) {
            return Value(-1);
        }
        
        // Determine open mode
        std::ios_base::openmode openMode = std::ios_base::binary;
        if (mode.find('r') != std::string::npos) openMode |= std::ios_base::in;
        if (mode.find('w') != std::string::npos) openMode |= std::ios_base::out | std::ios_base::trunc;
        if (mode.find('a') != std::string::npos) openMode |= std::ios_base::out | std::ios_base::app;
        if (mode.find('+') != std::string::npos) openMode |= std::ios_base::in | std::ios_base::out;
        
        try {
            auto file = std::make_unique<std::fstream>(filename, openMode);
            if (!file->is_open()) {
                return Value(-1);
            }
            
            int handle = nextHandle++;
            fileHandles[handle] = std::move(file);
            return Value(handle);
        } catch (...) {
            return Value(-1);
        }
    };
    
    // FCLOSE(handle) - Close file
    builtins_["FCLOSE"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        int handle = args[0].asInt();
        
        auto it = fileHandles.find(handle);
        if (it != fileHandles.end()) {
            it->second->close();
            fileHandles.erase(it);
            return Value(1);
        }
        return Value(0);
    };
    
    // FREAD(handle) - Read from file
    builtins_["FREAD"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        int handle = args[0].asInt();
        
        auto it = fileHandles.find(handle);
        if (it == fileHandles.end() || !it->second->is_open()) {
            return Value("");
        }
        
        std::string line;
        if (std::getline(*it->second, line)) {
            return Value(line);
        }
        return Value("");
    };
    
    // FWRITE(handle, data) - Write to file
    builtins_["FWRITE"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(0);
        int handle = args[0].asInt();
        std::string data = args[1].asString();
        
        auto it = fileHandles.find(handle);
        if (it == fileHandles.end() || !it->second->is_open()) {
            return Value(0);
        }
        
        *it->second << data;
        return Value(static_cast<int>(data.length()));
    };
    
    // FWRITE2(filename, data) - Write to file directly
    builtins_["FWRITE2"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(0);
        std::string filename = args[0].asString();
        std::string data = args[1].asString();
        
        // Security check
        if (filename.empty() || filename[0] == '/' || filename.find("..") != std::string::npos) {
            return Value(0);
        }
        
        try {
            std::ofstream file(filename, std::ios_base::out | std::ios_base::trunc);
            if (!file.is_open()) return Value(0);
            file << data;
            file.close();
            return Value(1);
        } catch (...) {
            return Value(0);
        }
    };
    
    // FSIZE(filename) - Get file size
    builtins_["FSIZE"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(-1);
        std::string filename = args[0].asString();
        
        // Security check
        if (filename.empty() || filename[0] == '/' || filename.find("..") != std::string::npos) {
            return Value(-1);
        }
        
        try {
            std::ifstream file(filename, std::ios_base::ate | std::ios_base::binary);
            if (!file.is_open()) return Value(-1);
            return Value(static_cast<int>(file.tellg()));
        } catch (...) {
            return Value(-1);
        }
    };
    
    // FENUM(path, pattern) - Enumerate files (simple substring match)
    builtins_["FENUM"] = [](const std::vector<Value>& args) -> Value {
        std::vector<Value> out;
        if (args.size() < 2) return Value(out);
        std::string dir = args[0].asString();
        std::string pat = args[1].asString();
        // YAYA ゴーストは自分の絶対パス配下を列挙するため絶対パスを許可する
        // （macOS コンテナのサンドボックスが実境界）。親階層への .. 抜けのみ禁止。
        if (dir.empty() || dir.find("..") != std::string::npos) return Value(out);
        try {
            std::string needle;
            for (char c : pat) if (c != '*') needle += c;
            namespace fs = std::filesystem;
            for (const auto& entry : fs::directory_iterator(dir)) {
                if (!entry.is_regular_file()) continue;
                std::string name = entry.path().filename().string();
                if (needle.empty() || name.find(needle) != std::string::npos) {
                    out.emplace_back(name);
                }
            }
        } catch (...) {}
        return Value(out);
    };
    
    // FCOPY(src, dst) - Copy file
    builtins_["FCOPY"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(0);
        std::string src = args[0].asString();
        std::string dst = args[1].asString();
        
        // Security check
        if (src.empty() || dst.empty() || src[0] == '/' || dst[0] == '/' ||
            src.find("..") != std::string::npos || dst.find("..") != std::string::npos) {
            return Value(0);
        }
        
        try {
            std::ifstream srcFile(src, std::ios_base::binary);
            if (!srcFile.is_open()) return Value(0);
            
            std::ofstream dstFile(dst, std::ios_base::binary);
            if (!dstFile.is_open()) return Value(0);
            
            dstFile << srcFile.rdbuf();
            return Value(1);
        } catch (...) {
            return Value(0);
        }
    };
    
    // FMOVE(src, dst) - Move file
    builtins_["FMOVE"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(0);
        std::string src = args[0].asString();
        std::string dst = args[1].asString();
        
        // Security check
        if (src.empty() || dst.empty() || src[0] == '/' || dst[0] == '/' ||
            src.find("..") != std::string::npos || dst.find("..") != std::string::npos) {
            return Value(0);
        }
        
        try {
            if (std::rename(src.c_str(), dst.c_str()) == 0) {
                return Value(1);
            }
            return Value(0);
        } catch (...) {
            return Value(0);
        }
    };
    
    // FDEL(filename) - Delete file
    builtins_["FDEL"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string filename = args[0].asString();
        
        // Security check
        if (filename.empty() || filename[0] == '/' || filename.find("..") != std::string::npos) {
            return Value(0);
        }
        
        try {
            if (std::remove(filename.c_str()) == 0) {
                return Value(1);
            }
            return Value(0);
        } catch (...) {
            return Value(0);
        }
    };
    
    // FRENAME(old, new) - Rename file
    builtins_["FRENAME"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(0);
        std::string oldName = args[0].asString();
        std::string newName = args[1].asString();
        
        // Security check
        if (oldName.empty() || newName.empty() || oldName[0] == '/' || newName[0] == '/' ||
            oldName.find("..") != std::string::npos || newName.find("..") != std::string::npos) {
            return Value(0);
        }
        
        try {
            if (std::rename(oldName.c_str(), newName.c_str()) == 0) {
                return Value(1);
            }
            return Value(0);
        } catch (...) {
            return Value(0);
        }
    };
    
    // MKDIR(path) - Create directory
    builtins_["MKDIR"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string path = args[0].asString();
        // Security: only relative paths without parent traversal
        if (path.empty() || path[0] == '/' || path.find("..") != std::string::npos) return Value(0);
        try {
            namespace fs = std::filesystem;
            fs::create_directories(path);
            return Value(1);
        } catch (...) {
            return Value(0);
        }
    };
    
    // RMDIR(path) - Remove directory (only if empty)
    builtins_["RMDIR"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string path = args[0].asString();
        if (path.empty() || path[0] == '/' || path.find("..") != std::string::npos) return Value(0);
        try {
            namespace fs = std::filesystem;
            bool removed = fs::remove(path);
            return Value(removed ? 1 : 0);
        } catch (...) {
            return Value(0);
        }
    };
    
    // FSEEK(handle, pos) - Seek in file
    builtins_["FSEEK"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(-1);
        int handle = args[0].asInt();
        int pos = args[1].asInt();
        
        auto it = fileHandles.find(handle);
        if (it == fileHandles.end() || !it->second->is_open()) {
            return Value(-1);
        }
        
        it->second->seekg(pos, std::ios_base::beg);
        return Value(0);
    };
    
    // FTELL(handle) - Get file position
    builtins_["FTELL"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(-1);
        int handle = args[0].asInt();
        
        auto it = fileHandles.find(handle);
        if (it == fileHandles.end() || !it->second->is_open()) {
            return Value(-1);
        }
        
        return Value(static_cast<int>(it->second->tellg()));
    };
    
    // FCHARSET(filename) - Detect file charset
    builtins_["FCHARSET"] = [](const std::vector<Value>& args) -> Value {
        // Charset detection is complex - default to UTF-8
        return Value("UTF-8");
    };
    
    // FATTRIB(filename) - Get file attributes
    builtins_["FATTRIB"] = [](const std::vector<Value>& args) -> Value {
        // Would need platform-specific code
        return Value(0);
    };
    
    // FREADBIN(handle) - Read binary from file
    builtins_["FREADBIN"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        int handle = args[0].asInt();
        
        auto it = fileHandles.find(handle);
        if (it == fileHandles.end() || !it->second->is_open()) {
            return Value("");
        }
        
        std::string data;
        char ch;
        while (it->second->get(ch)) {
            data += ch;
        }
        return Value(data);
    };
    
    // FWRITEBIN(handle, data) - Write binary to file
    builtins_["FWRITEBIN"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(0);
        int handle = args[0].asInt();
        std::string data = args[1].asString();
        
        auto it = fileHandles.find(handle);
        if (it == fileHandles.end() || !it->second->is_open()) {
            return Value(0);
        }
        
        it->second->write(data.c_str(), data.length());
        return Value(static_cast<int>(data.length()));
    };
    
    // FREADENCODE(handle, encoding) - Read with encoding
    builtins_["FREADENCODE"] = [](const std::vector<Value>& args) -> Value {
        return Value("");
    };
    
    // FWRITEDECODE(handle, data, encoding) - Write with encoding (stub)
    builtins_["FWRITEDECODE"] = [](const std::vector<Value>& args) -> Value {
        return Value(0);
    };
    
    // FDIGEST(filename, algorithm) - File hash/digest (md5/sha1/crc32)
    builtins_["FDIGEST"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value("");
        std::string filename = args[0].asString();
        std::string algo = args[1].asString();
        for (auto& ch : algo) ch = static_cast<char>(std::tolower(ch));
        if (filename.empty() || filename[0] == '/' || filename.find("..") != std::string::npos) return Value("");
        std::ifstream f(filename, std::ios::binary);
        if (!f.is_open()) return Value("");
        std::ostringstream buffer;
        buffer << f.rdbuf();
        std::string data = buffer.str();
        if (algo == "md5") return Value(md5_hex(data));
        if (algo == "sha1") return Value(sha1_hex(data));
        if (algo == "crc32") return Value(crc32_hex(data));
        return Value("");
    };
    
    // ===== Regular Expression Functions (std::regex-based) =====
    // NOTE: 本家 YAYA と同じく、検索系 RE_* は直近のマッチ結果を保持し、
    //       RE_GETSTR / RE_GETPOS / RE_GETLEN で取得できる。
    //       引数順も本家準拠: RE_xxx(対象文字列, パターン)。
    //       （旧実装は (パターン, 文字列) 順だったが本家は (str, pattern)）

    // RE_OPTION を反映した std::regex を生成する
    auto makeRegex = [this](const std::string& pattern) {
        auto flags = std::regex::ECMAScript;
        if (reOptions_ & 1) flags |= std::regex::icase;
        if (reOptions_ & 2) flags |= std::regex::multiline;
        return std::regex(pattern, flags);
    };

    auto clearReState = [this]() {
        reMatchStrings_.clear();
        reMatchPositions_.clear();
        reMatchLengths_.clear();
    };

    // マッチ結果（グループ含む）を保存する
    auto storeMatch = [this](const std::smatch& m) {
        for (size_t i = 0; i < m.size(); ++i) {
            reMatchStrings_.emplace_back(m[i].str());
            if (m[i].matched) {
                reMatchPositions_.emplace_back(static_cast<int>(m.position(i)));
                reMatchLengths_.emplace_back(static_cast<int>(m.length(i)));
            } else {
                reMatchPositions_.emplace_back(-1);
                reMatchLengths_.emplace_back(-1);
            }
        }
    };

    // RE_SEARCH(str, pattern) - Search for pattern; return 1/0 (マッチ結果は RE_GET* で取得)
    builtins_["RE_SEARCH"] = [this, makeRegex, clearReState, storeMatch](const std::vector<Value>& args) -> Value {
        clearReState();
        if (args.size() < 2) return Value(0);
        try {
            std::regex re = makeRegex(args[1].asString());
            std::smatch m;
            std::string s = args[0].asString();
            if (std::regex_search(s, m, re)) {
                storeMatch(m);
                return Value(1);
            }
            return Value(0);
        } catch (const std::exception& e) {
            std::cerr << "[VM] RE_SEARCH regex error: " << e.what() << std::endl;
            return Value(0);
        }
    };

    // RE_MATCH(str, pattern) - Full match; return 1/0
    builtins_["RE_MATCH"] = [this, makeRegex, clearReState, storeMatch](const std::vector<Value>& args) -> Value {
        clearReState();
        if (args.size() < 2) return Value(0);
        try {
            std::regex re = makeRegex(args[1].asString());
            std::smatch m;
            std::string s = args[0].asString();
            if (std::regex_match(s, m, re)) {
                storeMatch(m);
                return Value(1);
            }
            return Value(0);
        } catch (const std::exception& e) {
            std::cerr << "[VM] RE_MATCH regex error: " << e.what() << std::endl;
            return Value(0);
        }
    };

    // RE_GREP(str, pattern) - Return match count; matches stored for RE_GET*
    builtins_["RE_GREP"] = [this, makeRegex, clearReState](const std::vector<Value>& args) -> Value {
        clearReState();
        if (args.size() < 2) return Value(0);
        int count = 0;
        try {
            std::regex re = makeRegex(args[1].asString());
            const std::string s = args[0].asString();
            for (std::sregex_iterator it(s.begin(), s.end(), re), end; it != end; ++it) {
                reMatchStrings_.emplace_back(it->str());
                reMatchPositions_.emplace_back(static_cast<int>(it->position()));
                reMatchLengths_.emplace_back(static_cast<int>(it->length()));
                ++count;
            }
        } catch (const std::exception& e) {
            std::cerr << "[VM] RE_GREP regex error: " << e.what() << std::endl;
        }
        return Value(count);
    };

    // RE_GETSTR() - 直近マッチの文字列群（汎用配列）
    builtins_["RE_GETSTR"] = [this](const std::vector<Value>&) -> Value {
        return Value(reMatchStrings_);
    };

    // RE_GETPOS() - 直近マッチの開始位置群
    builtins_["RE_GETPOS"] = [this](const std::vector<Value>&) -> Value {
        return Value(reMatchPositions_);
    };

    // RE_GETLEN() - 直近マッチの長さ群
    builtins_["RE_GETLEN"] = [this](const std::vector<Value>&) -> Value {
        return Value(reMatchLengths_);
    };

    // RE_OPTION(flags) - 以降の RE_* のオプションを設定（bit0: 大小無視, bit1: 複数行）
    builtins_["RE_OPTION"] = [this](const std::vector<Value>& args) -> Value {
        int prev = reOptions_;
        if (!args.empty()) {
            reOptions_ = args[0].asInt();
        }
        return Value(prev);
    };

    // RE_REPLACE(str, pattern, replacement) - Replace all occurrences
    builtins_["RE_REPLACE"] = [this, makeRegex](const std::vector<Value>& args) -> Value {
        if (args.size() < 3) return Value("");
        try {
            return Value(std::regex_replace(args[0].asString(), makeRegex(args[1].asString()), args[2].asString()));
        } catch (const std::exception& e) {
            std::cerr << "[VM] RE_REPLACE regex error: " << e.what() << std::endl;
            return args[0];
        }
    };

    // RE_REPLACEEX(str, pattern, replacement) - $0/$1 等の後方参照を使った置換
    // std::regex_replace は ECMAScript 形式 ($1) をそのまま解釈するため同実装で良い
    builtins_["RE_REPLACEEX"] = builtins_["RE_REPLACE"];
    
    // RE_SPLIT(str, pattern) - Split by regex（本家準拠の引数順）
    builtins_["RE_SPLIT"] = [this, makeRegex](const std::vector<Value>& args) -> Value {
        std::vector<Value> out;
        if (args.size() < 2) return Value(out);
        try {
            std::regex re = makeRegex(args[1].asString());
            const std::string s = args[0].asString();
            std::sregex_token_iterator it(s.begin(), s.end(), re, -1), end;
            for (; it != end; ++it) out.emplace_back(it->str());
        } catch (const std::exception& e) {
            std::cerr << "[VM] RE_SPLIT regex error: " << e.what() << std::endl;
        }
        return Value(out);
    };
    
    // RE_ASEARCH(array, pattern) - Return index of first array element matching regex.
    builtins_["RE_ASEARCH"] = [this, makeRegex](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(-1);
        if (args[0].getType() != Value::Type::Array) return Value(-1);
        std::regex re;
        try { re = makeRegex(args[1].asString()); }
        catch (...) { return Value(-1); }
        const auto& arr = args[0].asArray();
        for (size_t i = 0; i < arr.size(); ++i) {
            try {
                if (std::regex_search(arr[i].asString(), re)) return Value(static_cast<int>(i));
            } catch (...) {}
        }
        return Value(-1);
    };

    // RE_ASEARCHEX(array, pattern) - Return array of all matching element indices.
    builtins_["RE_ASEARCHEX"] = [this, makeRegex](const std::vector<Value>& args) -> Value {
        std::vector<Value> out;
        if (args.size() < 2) return Value(out);
        if (args[0].getType() != Value::Type::Array) return Value(out);
        std::regex re;
        try { re = makeRegex(args[1].asString()); }
        catch (...) { return Value(out); }
        const auto& arr = args[0].asArray();
        for (size_t i = 0; i < arr.size(); ++i) {
            try {
                if (std::regex_search(arr[i].asString(), re)) out.push_back(Value(static_cast<int>(i)));
            } catch (...) {}
        }
        return Value(out);
    };
    
    // ===== Encoding/Decoding Functions =====
    // URL encode/decode helpers
    auto url_encode = [](const std::string& s, bool plus) {
        std::string out;
        out.reserve(s.size() * 3);
        static const char* hex = "0123456789ABCDEF";
        for (unsigned char c : s) {
            bool unreserved = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c=='.' || c=='_' || c=='-';
            if (unreserved) {
                out.push_back(static_cast<char>(c));
            } else if (c == ' ' && plus) {
                out.push_back('+');
            } else {
                out.push_back('%');
                out.push_back(hex[(c >> 4) & 0xF]);
                out.push_back(hex[c & 0xF]);
            }
        }
        return out;
    };
    auto url_decode = [](const std::string& s, bool plus) {
        std::string out;
        out.reserve(s.size());
        for (size_t i = 0; i < s.size(); ++i) {
            unsigned char c = s[i];
            if (c == '%' && i + 2 < s.size()) {
                auto hexval = [](unsigned char h) -> int {
                    if (h >= '0' && h <= '9') return h - '0';
                    if (h >= 'a' && h <= 'f') return 10 + (h - 'a');
                    if (h >= 'A' && h <= 'F') return 10 + (h - 'A');
                    return -1;
                };
                int hi = hexval(s[i+1]);
                int lo = hexval(s[i+2]);
                if (hi >= 0 && lo >= 0) {
                    out.push_back(static_cast<char>((hi << 4) | lo));
                    i += 2;
                } else {
                    out.push_back('%');
                }
            } else if (plus && c == '+') {
                out.push_back(' ');
            } else {
                out.push_back(static_cast<char>(c));
            }
        }
        return out;
    };

    // STRENCODE(str, encoding) - Encode string (supports "url" / "url+" / "base64")
    builtins_["STRENCODE"] = [url_encode](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        std::string enc = (args.size() >= 2) ? args[1].asString() : std::string("url");
        for (auto& ch : enc) ch = static_cast<char>(std::tolower(ch));
        if (enc == "base64") {
            return Value(Base64::encode(args[0].asString()));
        } else {
            bool plus = (enc.find("url+") != std::string::npos) || (enc == "url");
            return Value(url_encode(args[0].asString(), plus));
        }
    };
    
    // STRDECODE(str, encoding) - Decode string (supports "url" / "url+" / "base64")
    builtins_["STRDECODE"] = [url_decode](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        std::string enc = (args.size() >= 2) ? args[1].asString() : std::string("url");
        for (auto& ch : enc) ch = static_cast<char>(std::tolower(ch));
        if (enc == "base64") {
            return Value(Base64::decode(args[0].asString()));
        } else {
            bool plus = (enc.find("url+") != std::string::npos) || (enc == "url");
            return Value(url_decode(args[0].asString(), plus));
        }
    };
    
    // GETSTRURLENCODE, GETSTRURLDECODE - URL encode/decode with '+' for spaces
    builtins_["GETSTRURLENCODE"] = [url_encode](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        return Value(url_encode(args[0].asString(), true));
    };
    builtins_["GETSTRURLDECODE"] = [url_decode](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        return Value(url_decode(args[0].asString(), true));
    };
    
    // STRDIGEST(str, algorithm) - String hash/digest (md5/sha1/crc32)
    builtins_["STRDIGEST"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value("");
        std::string algo = args[1].asString();
        for (auto& ch : algo) ch = static_cast<char>(std::tolower(ch));
        std::string s = args[0].asString();
        if (algo == "md5") return Value(md5_hex(s));
        if (algo == "sha1") return Value(sha1_hex(s));
        if (algo == "crc32") return Value(crc32_hex(s));
        return Value("");
    };
    
    // CHARSETLIB/CHARSETLIBEX are registered later (Phase 8) with real state.

    // CHARSETTEXTTOID(text) - Convert charset name to numeric ID (Phase 10).
    builtins_["CHARSETTEXTTOID"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string n = args[0].asString();
        std::transform(n.begin(), n.end(), n.begin(), [](unsigned char c){ return std::tolower(c); });
        if (n == "utf-8" || n == "utf8") return Value(65001);
        if (n == "shift_jis" || n == "shift-jis" || n == "sjis" || n == "cp932" || n == "windows-31j") return Value(932);
        if (n == "euc-jp" || n == "eucjp") return Value(20932);
        if (n == "iso-2022-jp" || n == "jis") return Value(50220);
        if (n == "us-ascii" || n == "ascii") return Value(20127);
        return Value(0);
    };

    // CHARSETIDTOTEXT(id) - Convert numeric charset ID to name (Phase 10).
    builtins_["CHARSETIDTOTEXT"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("UTF-8");
        switch (args[0].asInt()) {
            case 65001: return Value("UTF-8");
            case 932: return Value("Shift_JIS");
            case 20932: return Value("EUC-JP");
            case 50220: return Value("ISO-2022-JP");
            case 20127: return Value("US-ASCII");
            default: return Value("UTF-8");
        }
    };
    
    // ZEN2HAN(str) - Convert full-width ASCII/space to half-width
    builtins_["ZEN2HAN"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        return Value(convertZenToHan(args[0].asString()));
    };

    // HAN2ZEN(str) - Convert half-width ASCII/space to full-width
    builtins_["HAN2ZEN"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        return Value(convertHanToZen(args[0].asString()));
    };
    
    // ===== Additional Variable/Function Management =====
    
    // SAVEVAR(filename) - グローバル変数を JSON で指定ファイルへ保存する。
    // 型情報（s=文字列, i=整数, r=実数, a=配列, v=void）を保持し RESTOREVAR で復元可能にする。
    // Phase 7: relative paths anchor under the ghost root; temp vars are excluded.
    builtins_["SAVEVAR"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string filename = args[0].asString();
        // Sandbox: relative paths only, no parent traversal.
        if (filename.empty() || filename[0] == '/' || filename.find("..") != std::string::npos) {
            return Value(0);
        }
        // Anchor under ghost root when available.
        std::string full = filename;
        if (!ghostRootPath_.empty()) {
            std::string base = ghostRootPath_;
            if (!base.empty() && base.back() != '/') base += '/';
            full = base + filename;
        }
        std::function<nlohmann::json(const Value&)> toJson = [&toJson](const Value& v) -> nlohmann::json {
            nlohmann::json j;
            switch (v.getType()) {
                case Value::Type::String: j["t"] = "s"; j["v"] = v.asString(); break;
                case Value::Type::Integer: j["t"] = "i"; j["v"] = v.asInt(); break;
                case Value::Type::Real: j["t"] = "r"; j["v"] = v.asReal(); break;
                case Value::Type::Array: {
                    j["t"] = "a";
                    nlohmann::json a = nlohmann::json::array();
                    for (const auto& e : v.asArray()) a.push_back(toJson(e));
                    j["v"] = a;
                    break;
                }
                default: j["t"] = "v"; break;
            }
            return j;
        };
        nlohmann::json root = nlohmann::json::object();
        // Build a set of temp-var names to exclude from persistence.
        std::set<std::string> excluded(tempVarNames_.begin(), tempVarNames_.end());
        for (const auto& kv : variables_) {
            if (excluded.count(kv.first)) continue;  // registered temp vars are not persisted
            root[kv.first] = toJson(kv.second);
        }
        try {
            std::ofstream ofs(full, std::ios::binary | std::ios::trunc);
            if (!ofs.is_open()) return Value(0);
            ofs << root.dump();
            return Value(ofs.good() ? 1 : 0);
        } catch (...) {
            return Value(0);
        }
    };

    // RESTOREVAR(filename) - SAVEVAR で保存した JSON からグローバル変数を復元する。
    builtins_["RESTOREVAR"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string filename = args[0].asString();
        if (filename.empty() || filename[0] == '/' || filename.find("..") != std::string::npos) {
            return Value(0);
        }
        std::string full = filename;
        if (!ghostRootPath_.empty()) {
            std::string base = ghostRootPath_;
            if (!base.empty() && base.back() != '/') base += '/';
            full = base + filename;
        }
        std::function<Value(const nlohmann::json&)> fromJson = [&fromJson](const nlohmann::json& j) -> Value {
            std::string t = j.value("t", std::string("v"));
            if (t == "s") return Value(j.value("v", std::string()));
            if (t == "i") return Value(j.value("v", 0));
            if (t == "r") return Value(j.value("v", 0.0));
            if (t == "a") {
                std::vector<Value> arr;
                if (j.contains("v") && j["v"].is_array()) {
                    for (const auto& e : j["v"]) arr.push_back(fromJson(e));
                }
                return Value(arr);
            }
            return Value();
        };
        try {
            std::ifstream ifs(full, std::ios::binary);
            if (!ifs.is_open()) return Value(0);
            nlohmann::json root = nlohmann::json::parse(ifs);
            if (!root.is_object()) return Value(0);
            for (auto it = root.begin(); it != root.end(); ++it) {
                variables_[it.key()] = fromJson(it.value());
            }
            return Value(1);
        } catch (...) {
            return Value(0);
        }
    };
    
    // DUMPVAR() - Dump all variables (for debugging)
    builtins_["DUMPVAR"] = [this](const std::vector<Value>& args) -> Value {
        (void)args;
        std::string result;
        for (const auto& pair : variables_) {
            result += pair.first + " = " + pair.second.asString() + "\n";
        }
        return Value(result);
    };

    // REGISTERTEMPVAR(name) - Register a variable name as temporary so that
    // SAVEVAR excludes it (mirrors yaya-dic SHIORI3FW.RegisterTempVar at the
    // builtin level so it works even when the framework is absent).
    builtins_["REGISTERTEMPVAR"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string name = args[0].asString();
        if (name.empty()) return Value(0);
        if (std::find(tempVarNames_.begin(), tempVarNames_.end(), name) == tempVarNames_.end()) {
            tempVarNames_.push_back(name);
        }
        return Value(1);
    };
    // UNREGISTERTEMPVAR(name) - Remove a name from the temp-var set.
    builtins_["UNREGISTERTEMPVAR"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string name = args[0].asString();
        auto it = std::find(tempVarNames_.begin(), tempVarNames_.end(), name);
        if (it == tempVarNames_.end()) return Value(0);
        tempVarNames_.erase(it);
        return Value(1);
    };

    // LOGGING(message...) - 引数をログへ出力する（本家仕様: logger へ書き込み＋改行）。
    // Ourin では yaya_core の stderr が Swift 側/テストの Pipe に回収されるため stderr へ出す。
    builtins_["LOGGING"] = [](const std::vector<Value>& args) -> Value {
        std::string line;
        for (size_t i = 0; i < args.size(); i++) {
            if (i > 0) line += ", ";
            line += args[i].asString();
        }
        std::cerr << "[YAYA][LOGGING] " << line << std::endl;
        return Value(1);
    };
    
    // ZEN2HAN(text) - Convert full-width ASCII/space to half-width
    builtins_["ZEN2HAN"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        return Value(convertZenToHan(args[0].asString()));
    };

    // HAN2ZEN(text) - Convert half-width ASCII/space to full-width
    builtins_["HAN2ZEN"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        return Value(convertHanToZen(args[0].asString()));
    };
    
    // LETTONAME(varname, value) - Assign to variable by name
    builtins_["LETTONAME"] = [this](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(0);
        std::string varName = args[0].asString();
        setVariable(varName, args[1]);
        return Value(1);
    };
    
    // LSO() - Get last selected option (stub)
    builtins_["LSO"] = [](const std::vector<Value>& args) -> Value {
        (void)args;
        return Value(0);
    };
    
    // ISEVALUABLE(str) - Check if string is evaluable (Phase 10).
    // Returns 1 only if the string parses as a complete expression with no
    // trailing tokens. A bare function name or variable is also evaluable.
    builtins_["ISEVALUABLE"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string s = args[0].asString();
        if (s.empty()) return Value(0);
        // A bare function name or variable is evaluable.
        if (hasFunction(s) || builtins_.find(s) != builtins_.end()) return Value(1);
        // Parse as a single expression; require full consumption.
        try {
            Lexer lexer(s);
            Parser parser(lexer.tokenize());
            std::string err;
            return Value(parser.parseExpressionOnly(err) ? 1 : 0);
        } catch (...) {
            return Value(0);
        }
    };
    
    // DICLOAD(filename) - Load dictionary file at runtime (Phase 6).
    // Resolves under ghost/master through the DictionaryManager callback.
    builtins_["DICLOAD"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) { lastError_ = 1; return Value(0); }
        if (!callback_) { lastError_ = 1; return Value(0); }
        std::string path = args[0].asString();
        std::string encoding = (args.size() >= 2) ? args[1].asString() : "";
        bool ok = callback_->dicLoad(path, encoding);
        if (!ok) lastError_ = 1;
        return Value(ok ? 1 : 0);
    };

    // DICUNLOAD(filename) - Unload dictionary file at runtime (Phase 6).
    builtins_["DICUNLOAD"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) { lastError_ = 1; return Value(0); }
        if (!callback_) { lastError_ = 1; return Value(0); }
        bool ok = callback_->dicUnload(args[0].asString());
        if (!ok) lastError_ = 1;
        return Value(ok ? 1 : 0);
    };
    
    // UNDEFFUNC(funcname) - Disable all declarations of a function (Phase 5/6).
    builtins_["UNDEFFUNC"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        return Value(undefFunction(args[0].asString()) ? 1 : 0);
    };
    
    // ===== Additional System/Utility Functions =====
    
    // EXECUTE(command) - Execute system command (non-blocking)
    builtins_["EXECUTE"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string command = args[0].asString();
        
        // Execute in background (non-blocking)
        command += " &";
        int result = system(command.c_str());
        return Value(result == 0 ? 1 : 0);
    };
    
    // EXECUTE_WAIT(command) - Execute and wait (blocking)
    builtins_["EXECUTE_WAIT"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string command = args[0].asString();
        
        // Execute and wait for completion
        int result = system(command.c_str());
        return Value(WEXITSTATUS(result));
    };
    
    // SLEEP(milliseconds) - Sleep
    builtins_["SLEEP"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        int ms = args[0].asInt();
        if (ms > 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(ms));
        }
        return Value(1);
    };
    
    // GETMEMINFO() - Get memory information (stub)
    builtins_["GETMEMINFO"] = [](const std::vector<Value>& args) -> Value {
        return Value(std::vector<Value>());
    };
    
    // READFMO(name) - FMO（Forged Memory Object）のスナップショットを読み込む。
    // 戻り値は SSP 互換の `id.key\x01value\r\n` 形式の文字列（buildSnapshot と同一）。
    // name は FMO 名（慣例 "Sakura"）。Ourin は単一 FMO のみ保持するため name は参照のみ。
    // ホスト（Swift）へ同期 IPC で問い合わせ、現在の FMO 内容を取得する。
    builtins_["READFMO"] = [this](const std::vector<Value>& args) -> Value {
        if (!callback_) return Value("");
        std::string name = args.empty() ? std::string("Sakura") : args[0].asString();
        try {
            nlohmann::json resp = callback_->fmoOperation("read", nlohmann::json{{"name", name}});
            if (resp.value("ok", false)) {
                return Value(resp.value("snapshot", std::string()));
            }
        } catch (...) {}
        return Value("");
    };
    
    // SETTAMAHWND(hwnd) - Set TAMA window handle (stub - Windows-specific)
    builtins_["SETTAMAHWND"] = [](const std::vector<Value>& args) -> Value {
        return Value(0);
    };
    
    // TRANSLATE(str, from, to) - 文字集合の対応変換（本家 yaya-shiori sysfunc.cpp 準拠）。
    // from/to は '-' 範囲展開（例 "a-z"、範囲上限256文字）と '\' エスケープに対応。
    // to が from より短い場合は to の末尾文字で充填、to が空の場合は該当文字を削除する。
    builtins_["TRANSLATE"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 3) return Value(-1);

        // '-' 範囲と '\' エスケープを展開してコードポイント列にする
        auto processSyntax = [](const std::string& spec) -> std::vector<uint32_t> {
            std::vector<uint32_t> cps = decodeUtf8(spec);
            std::vector<uint32_t> out;
            size_t n = cps.size();
            for (size_t i = 0; i < n; i++) {
                if (cps[i] == '-') {
                    if (i >= n - 1 || out.empty()) {
                        // '-' が閉じていない/開いていない: リテラル扱い（本家は警告のみ）
                        out.push_back('-');
                        continue;
                    }
                    i++;
                    uint32_t start = out.back();
                    out.pop_back();
                    uint32_t end = cps[i];
                    if (start > end) {
                        // ゼロ要素として続行（本家同様）
                    } else if (start == end) {
                        out.push_back(start);
                    } else {
                        if (end - start >= 256) end = start + 255; // 範囲上限（本家同様）
                        for (uint32_t c = start; c <= end; c++) out.push_back(c);
                    }
                } else if (cps[i] == '\\') {
                    if (i >= n - 1) {
                        out.push_back('-');
                        continue;
                    }
                    i++;
                    switch (cps[i]) {
                        case 'a': out.push_back('\a'); break;
                        case 'b': out.push_back('\b'); break;
                        case 'e': out.push_back(0x1b); break;
                        case 'f': out.push_back('\f'); break;
                        case 'n': out.push_back('\n'); break;
                        case 'r': out.push_back('\r'); break;
                        case 't': out.push_back('\t'); break;
                        case 'v': out.push_back('\v'); break;
                        case '0': out.push_back(0); break;
                        default:  out.push_back(cps[i]); break; // '\\' '\-' 等はその文字
                    }
                } else {
                    out.push_back(cps[i]);
                }
            }
            return out;
        };

        std::vector<uint32_t> str = decodeUtf8(args[0].asString());
        std::vector<uint32_t> repFrom = processSyntax(args[1].asString());
        std::vector<uint32_t> repTo = processSyntax(args[2].asString());

        if (repFrom.size() > repTo.size() && !repTo.empty()) {
            uint32_t pad = repTo.back();
            while (repFrom.size() > repTo.size()) repTo.push_back(pad);
        }
        bool isDelete = repTo.empty();

        std::string result;
        result.reserve(args[0].asString().size());
        for (uint32_t cp : str) {
            bool matched = false;
            for (size_t r = 0; r < repFrom.size(); r++) {
                if (cp == repFrom[r]) {
                    matched = true;
                    if (!isDelete) appendUtf8(result, repTo[r]);
                    break;
                }
            }
            if (!matched) appendUtf8(result, cp);
        }
        return Value(result);
    };
    
    // LICENSE() - Get license information
    builtins_["LICENSE"] = [](const std::vector<Value>& args) -> Value {
        (void)args;
        return Value("YAYA_core - YAYA interpreter for Ourin\nBased on YAYA specification");
    };
    
    // SPLITPATH(path) - Split file path into components
    builtins_["SPLITPATH"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(std::vector<Value>());
        std::string path = args[0].asString();
        
        std::vector<Value> result;
        // Simple split by / or backslash
        size_t pos = 0;
        size_t found;
        while ((found = path.find_first_of("/\\\\", pos)) != std::string::npos) {
            if (found > pos) {
                result.push_back(Value(path.substr(pos, found - pos)));
            }
            pos = found + 1;
        }
        if (pos < path.length()) {
            result.push_back(Value(path.substr(pos)));
        }
        
        return Value(result);
    };
    
    // GETSTRBYTES(str) - Get string byte length
    builtins_["GETSTRBYTES"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        return Value(static_cast<int>(args[0].asString().length()));
    };
    
    // ASEARCHEX(array, value, start) - Array search from position
    builtins_["ASEARCHEX"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(-1);
        if (args[0].getType() != Value::Type::Array) return Value(-1);
        
        const auto& arr = args[0].asArray();
        const Value& searchVal = args[1];
        int start = (args.size() >= 3) ? args[2].asInt() : 0;
        
        if (start < 0) start = 0;
        
        for (size_t i = start; i < arr.size(); i++) {
            if (arr[i] == searchVal) {
                return Value(static_cast<int>(i));
            }
        }
        return Value(-1);
    };

    // ASEARCHPOS(array, value, start) - 配列内を start 位置から検索し最初に見つかった
    // 要素のインデックスを返す。見つからなければ -1。start 省略時は 0（ASEARCH と同等）。
    builtins_["ASEARCHPOS"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(-1);
        if (args[0].getType() != Value::Type::Array) return Value(-1);

        const auto& arr = args[0].asArray();
        const Value& searchVal = args[1];
        int start = (args.size() >= 3) ? args[2].asInt() : 0;

        if (start < 0) start = 0;

        for (size_t i = static_cast<size_t>(start); i < arr.size(); i++) {
            if (arr[i] == searchVal) {
                return Value(static_cast<int>(i));
            }
        }
        return Value(-1);
    };
    
    // GETDELIM() - 現在の配列区切り文字を返す
    builtins_["GETDELIM"] = [this](const std::vector<Value>& args) -> Value {
        (void)args;
        return Value(arrayDelimiter_);
    };

    // SETDELIM(delim) - 配列区切り文字を設定する（SPLIT の区切り省略時に使用）
    builtins_["SETDELIM"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        arrayDelimiter_ = args[0].asString();
        return Value(1);
    };
    
    // GETSETTING(key) - Get setting value (Phase 7).
    builtins_["GETSETTING"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        auto it = settings_.find(args[0].asString());
        return (it != settings_.end()) ? it->second : Value("");
    };

    // SETSETTING(key, value) - Set setting value (Phase 7).
    builtins_["SETSETTING"] = [this](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(0);
        settings_[args[0].asString()] = args[1];
        return Value(1);
    };

    // GETLASTERROR() - Get last error code (Phase 7).
    builtins_["GETLASTERROR"] = [this](const std::vector<Value>& args) -> Value {
        (void)args;
        return Value(lastError_);
    };

    // SETLASTERROR(code) - Set last error code (Phase 7).
    builtins_["SETLASTERROR"] = [this](const std::vector<Value>& args) -> Value {
        lastError_ = args.empty() ? 0 : args[0].asInt();
        if (args.size() >= 2) lastErrorDesc_ = args[1].asString();
        return Value(1);
    };

    // GETERRORLOG() - Get accumulated error log (Phase 7/10).
    builtins_["GETERRORLOG"] = [this](const std::vector<Value>& args) -> Value {
        (void)args;
        std::string s;
        for (size_t i = 0; i < errorLog_.size(); ++i) {
            if (i) s += "\n";
            s += errorLog_[i];
        }
        return Value(s);
    };

    // CLEARERRORLOG() - Clear error log
    builtins_["CLEARERRORLOG"] = [this](const std::vector<Value>& args) -> Value {
        (void)args;
        errorLog_.clear();
        lastError_ = 0;
        lastErrorDesc_.clear();
        return Value(1);
    };

    // GETCALLSTACK() - Get call stack (Phase 10). Returns array of active frames
    // (best-effort: reports current recursion depth).
    builtins_["GETCALLSTACK"] = [this](const std::vector<Value>& args) -> Value {
        (void)args;
        return Value(std::vector<Value>{Value(recursion_depth_)});
    };
    
    // GETFUNCINFO(funcname) - Get function information (Phase 5).
    // Returns: array [type, overload_count, source_id] or empty if not found.
    builtins_["GETFUNCINFO"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(std::vector<Value>{});
        auto it = functions_.find(args[0].asString());
        if (it == functions_.end() || it->second.empty()) return Value(std::vector<Value>{});
        std::vector<Value> info;
        info.push_back(Value(it->second.front().node ? it->second.front().node->functionType : ""));
        int enabled = 0;
        for (const auto& d : it->second) if (d.enabled) enabled++;
        info.push_back(Value(enabled));
        info.push_back(Value(it->second.front().sourceId));
        return Value(info);
    };
    
    // LOADLIB(filename) - Load SAORI library
    builtins_["LOADLIB"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        if (!callback_) return Value(0);

        nlohmann::json params;
        params["module"] = args[0].asString();
        auto result = callback_->pluginOperation("saori_load", params);
        bool ok = result.value("ok", false);
        return Value(ok ? 1 : 0);
    };
    
    // UNLOADLIB(filename) - Unload SAORI library
    builtins_["UNLOADLIB"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        if (!callback_) return Value(0);

        nlohmann::json params;
        params["module"] = args[0].asString();
        auto result = callback_->pluginOperation("saori_unload", params);
        bool ok = result.value("ok", false);
        return Value(ok ? 1 : 0);
    };
    
    // REQUESTLIB(filename, request_text[, charset]) - Request from SAORI library.
    // Phase 8: parses the SAORI HTTP-like response, sets Result as the return value,
    // and stores extra Value0/Value1... in valueex (accessible via valueex builtin).
    builtins_["REQUESTLIB"] = [this](const std::vector<Value>& args) -> Value {
        saoriValueex_.clear();
        if (args.size() < 2) return Value("");
        if (!callback_) return Value("");

        std::string charset = !saoriCharset_.empty() ? saoriCharset_
                            : ((args.size() >= 3) ? args[2].asString() : std::string("UTF-8"));

        nlohmann::json params;
        params["module"] = args[0].asString();
        params["request"] = args[1].asString();
        params["charset"] = charset;

        auto result = callback_->pluginOperation("saori_request", params);
        bool ok = result.value("ok", false);
        if (!ok) {
            lastError_ = result.value("status", 1);
            return Value("");
        }

        std::string responseText;
        if (result.contains("response") && result["response"].is_string()) {
            responseText = result["response"].get<std::string>();
        } else if (result.contains("result") && result["result"].is_string()) {
            responseText = result["result"].get<std::string>();
        }

        // The host may return a pre-parsed Result directly; prefer it when present.
        if (result.contains("result") && result["result"].is_string()) {
            std::string res = result["result"].get<std::string>();
            // Still collect extras if the host provided them.
            if (result.contains("values") && result["values"].is_array()) {
                for (const auto& v : result["values"]) {
                    saoriValueex_.push_back(Value(v.is_string() ? v.get<std::string>()
                                                                : v.dump()));
                }
            }
            return Value(res);
        }

        // Parse the raw SAORI response: "SAORI/1.0 200 OK\r\nResult: ...\r\nValue0: ...\r\n\r\n"
        std::string resultValue;
        std::map<std::string, std::string> headers;
        {
            // Normalize CRLF parsing
            size_t lineStart = 0;
            bool firstLine = true;
            while (lineStart <= responseText.size()) {
                size_t lineEnd = responseText.find("\r\n", lineStart);
                std::string line;
                if (lineEnd == std::string::npos) {
                    line = responseText.substr(lineStart);
                    lineStart = responseText.size() + 1;
                } else {
                    line = responseText.substr(lineStart, lineEnd - lineStart);
                    lineStart = lineEnd + 2;
                }
                if (line.empty()) break;
                if (firstLine) { firstLine = false; continue; }
                auto colon = line.find(':');
                if (colon == std::string::npos) continue;
                std::string key = line.substr(0, colon);
                std::string val = line.substr(colon + 1);
                if (!val.empty() && val.front() == ' ') val.erase(0, 1);
                headers[key] = val;
            }
        }

        auto itResult = headers.find("Result");
        if (itResult != headers.end()) {
            resultValue = itResult->second;
        }
        // Collect Value0, Value1, ... in numeric order.
        for (int i = 0; ; ++i) {
            auto it = headers.find("Value" + std::to_string(i));
            if (it == headers.end()) break;
            saoriValueex_.push_back(Value(it->second));
        }
        return Value(resultValue);
    };

    // CHARSETLIB(charset) - Set the default charset used for subsequent SAORI requests.
    builtins_["CHARSETLIB"] = [this](const std::vector<Value>& args) -> Value {
        if (!args.empty()) saoriCharset_ = args[0].asString();
        return Value(1);
    };

    // CHARSETLIBEX(charset) - Extended charset selection (Phase 8).
    builtins_["CHARSETLIBEX"] = [this](const std::vector<Value>& args) -> Value {
        if (!args.empty()) saoriCharset_ = args[0].asString();
        return Value(1);
    };

    // valueex() - Array of extra SAORI return values from the last REQUESTLIB.
    builtins_["valueex"] = [this](const std::vector<Value>& args) -> Value {
        (void)args;
        return Value(saoriValueex_);
    };

    // valueexN accessors (valueex0, valueex1, ...)
    auto makeValueexN = [this](int n) -> std::function<Value(const std::vector<Value>&)> {
        return [this, n](const std::vector<Value>&) -> Value {
            if (n < static_cast<int>(saoriValueex_.size())) return saoriValueex_[n];
            return Value("");
        };
    };
    for (int i = 0; i < 16; ++i) {
        builtins_["valueex" + std::to_string(i)] = makeValueexN(i);
    }

    // FUNCTIONLOAD(path) / FUNCTIONEX(path, args...) / SAORI(path, args...) - yaya-dic SAORI wrappers.
    // These mirror the standard yaya_base helpers so ghosts that call them directly still work.
    builtins_["FUNCTIONLOAD"] = builtins_["LOADLIB"];
    builtins_["FUNCTIONEX"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        // Build a SAORI/1.0 request from the argument list.
        std::string req = "EXECUTE SAORI/1.0\r\nCharset: UTF-8\r\n";
        for (size_t i = 1; i < args.size(); ++i) {
            req += "Argument" + std::to_string(i - 1) + ": " + args[i].asString() + "\r\n";
        }
        req += "\r\n";
        std::vector<Value> libArgs = { args[0], Value(req) };
        return builtins_["REQUESTLIB"](libArgs);
    };
    builtins_["SAORI"] = builtins_["FUNCTIONEX"];
    
    // GETTYPEEX(value) - Get extended type information
    builtins_["GETTYPEEX"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("void");
        switch (args[0].getType()) {
            case Value::Type::Void: return Value("void");
            case Value::Type::Integer: return Value("int");
            case Value::Type::Real: return Value("real");
            case Value::Type::String: return Value("str");
            case Value::Type::Array: return Value("array");
            case Value::Type::Dictionary: return Value("dict");
            default: return Value("unknown");
        }
    };
    
    // TOAUTO(value) - Auto-convert type (tries to detect best type)
    builtins_["TOAUTO"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value();
        return args[0]; // Just return as-is
    };
    
    // TOAUTOEX(value) - Auto-convert extended
    builtins_["TOAUTOEX"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value();
        return args[0];
    };
    
    // CVAUTO, CVAUTOEX - Aliases for TOAUTO, TOAUTOEX
    builtins_["CVAUTO"] = builtins_["TOAUTO"];
    builtins_["CVAUTOEX"] = builtins_["TOAUTOEX"];
    
    // ===== Advanced/Undocumented Functions =====
    
    // ISGLOBALDEFINE(name) - Check if a runtime global define exists (Phase 10).
    builtins_["ISGLOBALDEFINE"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        return Value(globalDefines_.find(args[0].asString()) != globalDefines_.end() ? 1 : 0);
    };

    // SETGLOBALDEFINE(name, value) - Register a runtime global define (Phase 10).
    builtins_["SETGLOBALDEFINE"] = [this](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(0);
        globalDefines_[args[0].asString()] = args[1].asString();
        return Value(1);
    };

    // UNDEFGLOBALDEFINE(name) - Remove a runtime global define (Phase 10).
    builtins_["UNDEFGLOBALDEFINE"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        return Value(globalDefines_.erase(args[0].asString()) > 0 ? 1 : 0);
    };

    // PROCESSGLOBALDEFINE(str) - Apply runtime global defines to a string (Phase 10).
    builtins_["PROCESSGLOBALDEFINE"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        std::string s = args[0].asString();
        if (globalDefines_.empty()) return Value(s);
        // Replace whole-word occurrences of each define name.
        for (const auto& kv : globalDefines_) {
            std::string out;
            size_t pos = 0;
            while (pos < s.size()) {
                size_t found = s.find(kv.first, pos);
                if (found == std::string::npos) { out += s.substr(pos); break; }
                out += s.substr(pos, found - pos);
                out += kv.second;
                pos = found + kv.first.size();
            }
            s = out;
        }
        return Value(s);
    };
    
    // APPEND_RUNTIME_DIC(code) - Append runtime dictionary (Phase 6).
    // Parse code as a synthetic dictionary and register its functions.
    builtins_["APPEND_RUNTIME_DIC"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) { lastError_ = 1; return Value(0); }
        try {
            Lexer lexer(args[0].asString());
            Parser parser(lexer.tokenize());
            auto functions = parser.parse();
            beginSource("__runtime__");
            for (const auto& func : functions) {
                registerFunction(func->name, func);
            }
            return Value(1);
        } catch (const std::exception& e) {
            lastError_ = 1;
            lastErrorDesc_ = e.what();
            errorLog_.push_back("APPEND_RUNTIME_DIC: " + std::string(e.what()));
            return Value(0);
        }
    };

    // FUNCDECL_READ(funcname) - Read function declaration metadata (Phase 5).
    builtins_["FUNCDECL_READ"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        std::string decl;
        return Value(funcDeclRead(args[0].asString(), decl) ? decl : "");
    };

    // FUNCDECL_WRITE(funcname, decl) - Write function declaration metadata (Phase 5).
    builtins_["FUNCDECL_WRITE"] = [this](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(0);
        return Value(funcDeclWrite(args[0].asString(), args[1].asString()) ? 1 : 0);
    };

    // FUNCDECL_ERASE(funcname) - Erase function declaration (Phase 5).
    builtins_["FUNCDECL_ERASE"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        return Value(funcDeclErase(args[0].asString()) ? 1 : 0);
    };
    
    // OUTPUTNUM(format, number) - Format number output (stub)
    builtins_["OUTPUTNUM"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value("");
        return Value(args[1].asString());
    };
    
    // EmBeD_HiStOrY - Embedded history function (stub)
    builtins_["EmBeD_HiStOrY"] = [](const std::vector<Value>& args) -> Value {
        (void)args;
        return Value("");
    };
}

// Interpolate embedded expressions in strings like %(_varname) or %(funcname())
// IMPORTANT: SSP/baseware percent variables like %(charname(0)) should NOT be interpolated by YAYA
std::string VM::interpolateString(const std::string& str) {
    std::string result;
    size_t pos = 0;

    // List of SSP/baseware variables that should NOT be interpolated by YAYA
    static const std::unordered_set<std::string> ssp_vars = {
        "charname", "username", "selfname", "selfname2", "keroname",
        "month", "day", "hour", "minute", "second",
        "screenwidth", "screenheight", "property"
    };

    while (pos < str.length()) {
        // Look for %(
        size_t start = str.find("%(", pos);
        if (start == std::string::npos) {
            // No more embedded expressions
            result += str.substr(pos);
            break;
        }

        // Add text before %(
        result += str.substr(pos, start - pos);

        // Find matching ) - need to handle nested parentheses for function calls
        int depth = 1;
        size_t end = start + 2;
        while (end < str.length() && depth > 0) {
            if (str[end] == '(') depth++;
            else if (str[end] == ')') depth--;
            if (depth > 0) end++;
        }

        if (depth != 0) {
            // Malformed - just add the rest
            result += str.substr(start);
            break;
        }

        // Extract the embedded expression
        std::string expr = str.substr(start + 2, end - start - 2);

        // Check if this looks like an SSP/baseware variable (e.g., charname(...))
        bool is_ssp_var = false;
        for (const auto& ssp_var : ssp_vars) {
            if (expr == ssp_var || expr.rfind(ssp_var + "(", 0) == 0 || expr.rfind(ssp_var + "[", 0) == 0) {
                is_ssp_var = true;
                break;
            }
        }

        if (is_ssp_var) {
            // Leave SSP variables for baseware to expand
            result += "%(" + expr + ")";
        } else {
            // 任意の式として評価する。inner text を Lexer/Parser に通し、
            // 得られた式ノードを executeNode で評価して asString() を埋め込む。
            bool evaluated = false;
            try {
                // public な parse() は関数定義を要求するため、合成関数で包んで本体を実行する
                Lexer lexer("__interp__{\n" + expr + "\n}");
                Parser parser(lexer.tokenize());
                auto funcs = parser.parse();
                if (!funcs.empty() && funcs[0]) {
                    Value val;
                    for (const auto& stmt : funcs[0]->body) {
                        val = executeNode(stmt);
                    }
                    result += val.asString();
                    evaluated = true;
                }
            } catch (...) {
                // パース/評価失敗時は下位のフォールバックへ
            }
            if (!evaluated) {
                // フォールバック: 単純な変数参照として評価する
                Value val = getVariable(expr);
                if (!val.isVoid()) {
                    result += val.asString();
                } else {
                    // 変数も見つからない場合は空文字（旧挙動は baseware 展開のため残置だったが
                    // 任意式評価の失敗時は空とする）
                }
            }
        }

        pos = end + 1;
    }

    return result;
}
