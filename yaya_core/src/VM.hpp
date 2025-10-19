#pragma once

#include "AST.hpp"
#include "Value.hpp"
#include <map>
#include <string>
#include <vector>
#include <functional>
#include <nlohmann/json.hpp>

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
};

class VM {
public:
    VM();
    
    // Set callback for host operations
    void setCallback(VMCallback* callback) { callback_ = callback; }
    
    // Register a function
    void registerFunction(const std::string& name, std::shared_ptr<AST::FunctionNode> func);
    
    // Execute a function by name
    Value execute(const std::string& functionName, const std::vector<Value>& args);
    
    // Set/get variables
    void setVariable(const std::string& name, const Value& value);
    Value getVariable(const std::string& name) const;
    
    // Set reference values (from SHIORI request)
    void setReferences(const std::vector<std::string>& refs);
    
private:
    VMCallback* callback_ = nullptr;
    // Function registry
    std::map<std::string, std::shared_ptr<AST::FunctionNode>> functions_;

    // Variable storage
    std::map<std::string, Value> variables_;

    // SHIORI reference values
    std::vector<Value> references_;

    // Built-in functions
    std::map<std::string, std::function<Value(const std::vector<Value>&)>> builtins_;

    // 再帰深度制限（無限ループ防止）
    int recursion_depth_ = 0;
    static constexpr int MAX_RECURSION_DEPTH = 1000;

    // 実行タイムアウト（無限ループ防止）
    std::chrono::steady_clock::time_point execution_start_time_;
    static constexpr int MAX_EXECUTION_TIME_MS = 5000; // 5秒

    // Early return exception for control flow
    struct ReturnException {
        Value value;
        explicit ReturnException(const Value& v) : value(v) {}
    };

    // Execution helpers
    Value executeNode(std::shared_ptr<AST::Node> node);
    Value executeBlock(const std::vector<std::shared_ptr<AST::Node>>& statements);
    Value evaluateBinaryOp(const std::string& op, const Value& left, const Value& right);
    Value evaluateUnaryOp(const std::string& op, const Value& operand);
    Value callBuiltin(const std::string& name, const std::vector<Value>& args);
    std::string interpolateString(const std::string& str);
    
    // Register built-in functions
    void registerBuiltins();
};
