#pragma once

#include "AST.hpp"
#include "Value.hpp"
#include <map>
#include <string>
#include <vector>
#include <functional>

class VM {
public:
    VM();
    
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
    // Function registry
    std::map<std::string, std::shared_ptr<AST::FunctionNode>> functions_;
    
    // Variable storage
    std::map<std::string, Value> variables_;
    
    // SHIORI reference values
    std::vector<Value> references_;
    
    // Built-in functions
    std::map<std::string, std::function<Value(const std::vector<Value>&)>> builtins_;
    
    // Execution helpers
    Value executeNode(std::shared_ptr<AST::Node> node);
    Value executeBlock(const std::vector<std::shared_ptr<AST::Node>>& statements);
    Value evaluateBinaryOp(const std::string& op, const Value& left, const Value& right);
    Value evaluateUnaryOp(const std::string& op, const Value& operand);
    Value callBuiltin(const std::string& name, const std::vector<Value>& args);
    
    // Register built-in functions
    void registerBuiltins();
};
