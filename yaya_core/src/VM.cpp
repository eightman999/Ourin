#include "VM.hpp"
#include <random>
#include <stdexcept>
#include <ctime>
#include <cmath>
#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdlib>
#include <fstream>
#include <map>
#include <memory>
#include <thread>
#include <sys/wait.h>

VM::VM() {
    registerBuiltins();
}

void VM::registerFunction(const std::string& name, std::shared_ptr<AST::FunctionNode> func) {
    functions_[name] = func;
}

Value VM::execute(const std::string& functionName, const std::vector<Value>& args) {
    // Check if it's a built-in function
    if (builtins_.find(functionName) != builtins_.end()) {
        return callBuiltin(functionName, args);
    }
    
    // Check if it's a user-defined function
    auto it = functions_.find(functionName);
    if (it == functions_.end()) {
        return Value(); // Function not found, return void
    }
    
    // Execute the function body
    return executeBlock(it->second->body);
}

void VM::setVariable(const std::string& name, const Value& value) {
    variables_[name] = value;
}

Value VM::getVariable(const std::string& name) const {
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

Value VM::executeNode(std::shared_ptr<AST::Node> node) {
    if (!node) return Value();
    
    switch (node->type) {
        case AST::NodeType::Literal: {
            auto* lit = dynamic_cast<AST::LiteralNode*>(node.get());
            if (lit->isString) {
                // Interpolate embedded expressions in string literals
                std::string interpolated = interpolateString(lit->value);
                return Value(interpolated);
            } else {
                try {
                    return Value(std::stoi(lit->value));
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
        
        case AST::NodeType::While: {
            auto* whileNode = dynamic_cast<AST::WhileNode*>(node.get());
            Value result;
            while (executeNode(whileNode->condition).toBool()) {
                result = executeBlock(whileNode->body);
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
        
        default:
            return Value();
    }
}

Value VM::executeBlock(const std::vector<std::shared_ptr<AST::Node>>& statements) {
    Value lastValue;
    for (const auto& stmt : statements) {
        lastValue = executeNode(stmt);
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
    if (op == "-") return Value(-operand.asInt());
    return Value();
}

Value VM::callBuiltin(const std::string& name, const std::vector<Value>& args) {
    auto it = builtins_.find(name);
    if (it != builtins_.end()) {
        return it->second(args);
    }
    return Value();
}

void VM::registerBuiltins() {
    // RAND(max) - Returns a random number from 0 to max-1
    builtins_["RAND"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        int max = args[0].asInt();
        if (max <= 0) return Value(0);
        static std::random_device rd;
        static std::mt19937 gen(rd());
        std::uniform_int_distribution<> dis(0, max - 1);
        return Value(dis(gen));
    };
    
    // STRLEN(str) - Returns the length of a string
    builtins_["STRLEN"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        return Value(static_cast<int>(args[0].asString().length()));
    };
    
    // STRFORM(format, ...) - Simple string formatting (simplified)
    builtins_["STRFORM"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        std::string format = args[0].asString();
        // Very simple implementation - just concatenate arguments for now
        std::string result = format;
        for (size_t i = 1; i < args.size(); i++) {
            result += args[i].asString();
        }
        return Value(result);
    };
    
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
        std::string funcName = args[0].asString();
        return Value(functions_.find(funcName) != functions_.end() ? 1 : 0);
    };
    
    // EVAL(funcname) - Execute a function by name
    builtins_["EVAL"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value();
        std::string funcName = args[0].asString();
        std::vector<Value> funcArgs;
        for (size_t i = 1; i < args.size(); i++) {
            funcArgs.push_back(args[i]);
        }
        return execute(funcName, funcArgs);
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
    
    // TOREAL(value) - Convert to real (for now, same as TOINT since we don't have float support)
    builtins_["TOREAL"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        return Value(args[0].asInt());
    };
    
    // GETTYPE(value) - Get type of value (0=void, 1=int, 2=str, 3=array)
    builtins_["GETTYPE"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        switch (args[0].getType()) {
            case Value::Type::Void: return Value(0);
            case Value::Type::Integer: return Value(1);
            case Value::Type::String: return Value(2);
            case Value::Type::Array: return Value(3);
            case Value::Type::Dictionary: return Value(4);
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
    
    // STRSTR(haystack, needle) - Find substring position (-1 if not found)
    builtins_["STRSTR"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(-1);
        std::string haystack = args[0].asString();
        std::string needle = args[1].asString();
        size_t pos = haystack.find(needle);
        return Value(pos == std::string::npos ? -1 : static_cast<int>(pos));
    };
    
    // SUBSTR(str, pos, len) - Extract substring
    builtins_["SUBSTR"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value("");
        std::string str = args[0].asString();
        int pos = args[1].asInt();
        if (pos < 0 || pos >= static_cast<int>(str.length())) return Value("");
        
        int len = (args.size() >= 3) ? args[2].asInt() : static_cast<int>(str.length() - pos);
        if (len < 0) return Value("");
        
        return Value(str.substr(pos, len));
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
    
    // ERASE(str, pos, len) - Remove substring
    builtins_["ERASE"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value("");
        std::string str = args[0].asString();
        int pos = args[1].asInt();
        if (pos < 0 || pos >= static_cast<int>(str.length())) return Value(str);
        
        int len = (args.size() >= 3) ? args[2].asInt() : static_cast<int>(str.length() - pos);
        if (len < 0) len = 0;
        
        str.erase(pos, len);
        return Value(str);
    };
    
    // INSERT(str, pos, insertion) - Insert string at position
    builtins_["INSERT"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 3) return Value("");
        std::string str = args[0].asString();
        int pos = args[1].asInt();
        std::string insertion = args[2].asString();
        
        if (pos < 0) pos = 0;
        if (pos > static_cast<int>(str.length())) pos = str.length();
        
        str.insert(pos, insertion);
        return Value(str);
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
    
    // CHR(code) - Convert ASCII code to character
    builtins_["CHR"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        int code = args[0].asInt();
        if (code < 0 || code > 255) return Value("");
        return Value(std::string(1, static_cast<char>(code)));
    };
    
    // CHRCODE(str) - Get ASCII code of first character
    builtins_["CHRCODE"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        std::string str = args[0].asString();
        if (str.empty()) return Value(0);
        return Value(static_cast<int>(static_cast<unsigned char>(str[0])));
    };
    
    // ===== Math Operations =====
    
    // FLOOR(value) - Round down
    builtins_["FLOOR"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        return Value(args[0].asInt()); // Integer division already floors
    };
    
    // CEIL(value) - Round up
    builtins_["CEIL"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        return Value(args[0].asInt()); // For integers, same as floor
    };
    
    // ROUND(value) - Round to nearest
    builtins_["ROUND"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        return Value(args[0].asInt());
    };
    
    // SQRT(value) - Square root
    builtins_["SQRT"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        double val = static_cast<double>(args[0].asInt());
        return Value(static_cast<int>(std::sqrt(val)));
    };
    
    // POW(base, exp) - Power
    builtins_["POW"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(0);
        double base = static_cast<double>(args[0].asInt());
        double exp = static_cast<double>(args[1].asInt());
        return Value(static_cast<int>(std::pow(base, exp)));
    };
    
    // LOG(value) - Natural logarithm
    builtins_["LOG"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        double val = static_cast<double>(args[0].asInt());
        if (val <= 0) return Value(0);
        return Value(static_cast<int>(std::log(val)));
    };
    
    // LOG10(value) - Base-10 logarithm
    builtins_["LOG10"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        double val = static_cast<double>(args[0].asInt());
        if (val <= 0) return Value(0);
        return Value(static_cast<int>(std::log10(val)));
    };
    
    // SIN(value) - Sine
    builtins_["SIN"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        double val = static_cast<double>(args[0].asInt());
        return Value(static_cast<int>(std::sin(val)));
    };
    
    // COS(value) - Cosine
    builtins_["COS"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        double val = static_cast<double>(args[0].asInt());
        return Value(static_cast<int>(std::cos(val)));
    };
    
    // TAN(value) - Tangent
    builtins_["TAN"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        double val = static_cast<double>(args[0].asInt());
        return Value(static_cast<int>(std::tan(val)));
    };
    
    // ASIN(value) - Arc sine
    builtins_["ASIN"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        double val = static_cast<double>(args[0].asInt());
        return Value(static_cast<int>(std::asin(val)));
    };
    
    // ACOS(value) - Arc cosine
    builtins_["ACOS"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        double val = static_cast<double>(args[0].asInt());
        return Value(static_cast<int>(std::acos(val)));
    };
    
    // ATAN(value) - Arc tangent
    builtins_["ATAN"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        double val = static_cast<double>(args[0].asInt());
        return Value(static_cast<int>(std::atan(val)));
    };
    
    // SINH(value) - Hyperbolic sine
    builtins_["SINH"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        double val = static_cast<double>(args[0].asInt());
        return Value(static_cast<int>(std::sinh(val)));
    };
    
    // COSH(value) - Hyperbolic cosine
    builtins_["COSH"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        double val = static_cast<double>(args[0].asInt());
        return Value(static_cast<int>(std::cosh(val)));
    };
    
    // TANH(value) - Hyperbolic tangent
    builtins_["TANH"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        double val = static_cast<double>(args[0].asInt());
        return Value(static_cast<int>(std::tanh(val)));
    };
    
    // SRAND(seed) - Seed random number generator
    builtins_["SRAND"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        // Note: In a real implementation, this would seed the RNG
        // For now, we just return success
        return Value(1);
    };
    
    // ===== Array Operations =====
    
    // SPLIT(str, delim) - Split string into array
    builtins_["SPLIT"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value(std::vector<Value>());
        std::string str = args[0].asString();
        std::string delim = args[1].asString();
        
        std::vector<Value> result;
        if (delim.empty()) {
            // Split into individual characters
            for (char c : str) {
                result.push_back(Value(std::string(1, c)));
            }
        } else {
            size_t pos = 0;
            size_t found;
            while ((found = str.find(delim, pos)) != std::string::npos) {
                result.push_back(Value(str.substr(pos, found - pos)));
                pos = found + delim.length();
            }
            // Add the last part
            result.push_back(Value(str.substr(pos)));
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
        
        static std::random_device rd;
        static std::mt19937 gen(rd());
        std::uniform_int_distribution<> dis(0, arr.size() - 1);
        
        return arr[dis(gen)];
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
    
    // GETFUNCLIST() - Get list of user-defined functions
    builtins_["GETFUNCLIST"] = [this](const std::vector<Value>& args) -> Value {
        (void)args;
        std::vector<Value> result;
        for (const auto& pair : functions_) {
            result.push_back(Value(pair.first));
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
    
    // FENUM(path, pattern) - Enumerate files
    builtins_["FENUM"] = [](const std::vector<Value>& args) -> Value {
        // Complex operation - return empty for now
        // Would need filesystem library or platform-specific code
        return Value(std::vector<Value>());
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
        // Would need platform-specific code or C++17 filesystem
        return Value(0);
    };
    
    // RMDIR(path) - Remove directory
    builtins_["RMDIR"] = [](const std::vector<Value>& args) -> Value {
        // Would need platform-specific code or C++17 filesystem
        return Value(0);
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
    
    // FDIGEST(filename, algorithm) - File hash/digest (stub)
    builtins_["FDIGEST"] = [](const std::vector<Value>& args) -> Value {
        return Value("");
    };
    
    // ===== Regular Expression Functions =====
    // Note: Regular expressions require a regex library - providing stubs
    
    // RE_SEARCH(pattern, str) - Search for pattern (stub)
    builtins_["RE_SEARCH"] = [](const std::vector<Value>& args) -> Value {
        return Value(-1);
    };
    
    // RE_MATCH(pattern, str) - Match pattern (stub)
    builtins_["RE_MATCH"] = [](const std::vector<Value>& args) -> Value {
        return Value(0);
    };
    
    // RE_GREP(pattern, str) - Grep for pattern (stub)
    builtins_["RE_GREP"] = [](const std::vector<Value>& args) -> Value {
        return Value(std::vector<Value>());
    };
    
    // RE_REPLACE(pattern, str, replacement) - Replace with regex (stub)
    builtins_["RE_REPLACE"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value("");
        return args[1]; // Just return original string
    };
    
    // RE_REPLACEEX(pattern, str, replacement) - Replace extended (stub)
    builtins_["RE_REPLACEEX"] = [](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value("");
        return args[1];
    };
    
    // RE_SPLIT(pattern, str) - Split by regex (stub - use simple split)
    builtins_["RE_SPLIT"] = [](const std::vector<Value>& args) -> Value {
        return Value(std::vector<Value>());
    };
    
    // RE_OPTION(options) - Set regex options (stub)
    builtins_["RE_OPTION"] = [](const std::vector<Value>& args) -> Value {
        return Value(0);
    };
    
    // RE_GETSTR() - Get last match string (stub)
    builtins_["RE_GETSTR"] = [](const std::vector<Value>& args) -> Value {
        return Value("");
    };
    
    // RE_GETPOS() - Get last match position (stub)
    builtins_["RE_GETPOS"] = [](const std::vector<Value>& args) -> Value {
        return Value(-1);
    };
    
    // RE_GETLEN() - Get last match length (stub)
    builtins_["RE_GETLEN"] = [](const std::vector<Value>& args) -> Value {
        return Value(0);
    };
    
    // RE_ASEARCH(array, pattern) - Array regex search (stub)
    builtins_["RE_ASEARCH"] = [](const std::vector<Value>& args) -> Value {
        return Value(-1);
    };
    
    // RE_ASEARCHEX(array, pattern) - Array regex search extended (stub)
    builtins_["RE_ASEARCHEX"] = [](const std::vector<Value>& args) -> Value {
        return Value(std::vector<Value>());
    };
    
    // ===== Encoding/Decoding Functions =====
    
    // STRENCODE(str, encoding) - Encode string (stub - URL encode)
    builtins_["STRENCODE"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        // Simple URL encoding stub
        return args[0];
    };
    
    // STRDECODE(str, encoding) - Decode string (stub - URL decode)
    builtins_["STRDECODE"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        // Simple URL decoding stub
        return args[0];
    };
    
    // GETSTRURLENCODE, GETSTRURLDECODE - Aliases for STRENCODE, STRDECODE
    builtins_["GETSTRURLENCODE"] = builtins_["STRENCODE"];
    builtins_["GETSTRURLDECODE"] = builtins_["STRDECODE"];
    
    // STRDIGEST(str, algorithm) - String hash/digest (stub)
    builtins_["STRDIGEST"] = [](const std::vector<Value>& args) -> Value {
        return Value("");
    };
    
    // CHARSETLIB(encoding) - Set charset for library operations (stub)
    builtins_["CHARSETLIB"] = [](const std::vector<Value>& args) -> Value {
        return Value(1);
    };
    
    // CHARSETLIBEX(encoding) - Set charset extended (stub)
    builtins_["CHARSETLIBEX"] = [](const std::vector<Value>& args) -> Value {
        return Value(1);
    };
    
    // CHARSETTEXTTOID(text) - Convert charset name to ID (stub)
    builtins_["CHARSETTEXTTOID"] = [](const std::vector<Value>& args) -> Value {
        return Value(0);
    };
    
    // CHARSETIDTOTEXT(id) - Convert charset ID to name (stub)
    builtins_["CHARSETIDTOTEXT"] = [](const std::vector<Value>& args) -> Value {
        return Value("UTF-8");
    };
    
    // ZEN2HAN(str) - Convert full-width to half-width (stub)
    builtins_["ZEN2HAN"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        return args[0];
    };
    
    // HAN2ZEN(str) - Convert half-width to full-width (stub)
    builtins_["HAN2ZEN"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        return args[0];
    };
    
    // ===== Additional Variable/Function Management =====
    
    // SAVEVAR(filename) - Save variables to file (stub)
    builtins_["SAVEVAR"] = [](const std::vector<Value>& args) -> Value {
        return Value(0);
    };
    
    // RESTOREVAR(filename) - Restore variables from file (stub)
    builtins_["RESTOREVAR"] = [](const std::vector<Value>& args) -> Value {
        return Value(0);
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
    
    // LOGGING(message) - Log message (stub - just returns success)
    builtins_["LOGGING"] = [](const std::vector<Value>& args) -> Value {
        return Value(1);
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
    
    // ISEVALUABLE(str) - Check if string is evaluable (stub)
    builtins_["ISEVALUABLE"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        return Value(1);
    };
    
    // DICLOAD(filename) - Load dictionary file (stub)
    builtins_["DICLOAD"] = [](const std::vector<Value>& args) -> Value {
        return Value(0);
    };
    
    // DICUNLOAD(filename) - Unload dictionary file (stub)
    builtins_["DICUNLOAD"] = [](const std::vector<Value>& args) -> Value {
        return Value(0);
    };
    
    // UNDEFFUNC(funcname) - Undefine function (stub)
    builtins_["UNDEFFUNC"] = [](const std::vector<Value>& args) -> Value {
        return Value(0);
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
    
    // READFMO(name) - Read from FMO (Forged Memory Object) (stub)
    builtins_["READFMO"] = [](const std::vector<Value>& args) -> Value {
        return Value("");
    };
    
    // SETTAMAHWND(hwnd) - Set TAMA window handle (stub - Windows-specific)
    builtins_["SETTAMAHWND"] = [](const std::vector<Value>& args) -> Value {
        return Value(0);
    };
    
    // TRANSLATE(str, mode) - Translate string (stub)
    builtins_["TRANSLATE"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        return args[0];
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
    
    // GETDELIM() - Get delimiter (stub)
    builtins_["GETDELIM"] = [](const std::vector<Value>& args) -> Value {
        (void)args;
        return Value(",");
    };
    
    // SETDELIM(delim) - Set delimiter (stub)
    builtins_["SETDELIM"] = [](const std::vector<Value>& args) -> Value {
        return Value(1);
    };
    
    // GETSETTING(key) - Get setting (stub)
    builtins_["GETSETTING"] = [](const std::vector<Value>& args) -> Value {
        return Value("");
    };
    
    // SETSETTING(key, value) - Set setting (stub)
    builtins_["SETSETTING"] = [](const std::vector<Value>& args) -> Value {
        return Value(1);
    };
    
    // GETLASTERROR() - Get last error code
    builtins_["GETLASTERROR"] = [](const std::vector<Value>& args) -> Value {
        (void)args;
        return Value(0);
    };
    
    // SETLASTERROR(code) - Set last error code
    builtins_["SETLASTERROR"] = [](const std::vector<Value>& args) -> Value {
        return Value(1);
    };
    
    // GETERRORLOG() - Get error log (stub)
    builtins_["GETERRORLOG"] = [](const std::vector<Value>& args) -> Value {
        (void)args;
        return Value("");
    };
    
    // CLEARERRORLOG() - Clear error log
    builtins_["CLEARERRORLOG"] = [](const std::vector<Value>& args) -> Value {
        (void)args;
        return Value(1);
    };
    
    // GETCALLSTACK() - Get call stack (stub)
    builtins_["GETCALLSTACK"] = [](const std::vector<Value>& args) -> Value {
        (void)args;
        return Value(std::vector<Value>());
    };
    
    // GETFUNCINFO(funcname) - Get function information (stub)
    builtins_["GETFUNCINFO"] = [](const std::vector<Value>& args) -> Value {
        return Value("");
    };
    
    // LOADLIB(filename) - Load SAORI/Plugin library
    // Note: This requires integration with Swift PluginRegistry
    // For now, returns success to allow scripts to run
    builtins_["LOADLIB"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        // TODO: Integrate with Swift PluginRegistry through callback
        return Value(1); // Return success for compatibility
    };
    
    // UNLOADLIB(filename) - Unload SAORI/Plugin library
    // Note: This requires integration with Swift PluginRegistry
    builtins_["UNLOADLIB"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value(0);
        // TODO: Integrate with Swift PluginRegistry through callback
        return Value(1); // Return success for compatibility
    };
    
    // REQUESTLIB(filename, request_text) - Request from SAORI/Plugin library
    // Note: This requires integration with Swift PluginRegistry
    builtins_["REQUESTLIB"] = [this](const std::vector<Value>& args) -> Value {
        if (args.size() < 2) return Value("");
        // TODO: Integrate with Swift PluginRegistry through callback
        // For now, return empty response
        return Value("");
    };
    
    // GETTYPEEX(value) - Get extended type information
    builtins_["GETTYPEEX"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("void");
        switch (args[0].getType()) {
            case Value::Type::Void: return Value("void");
            case Value::Type::Integer: return Value("int");
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
    
    // ISGLOBALDEFINE(name) - Check if global define exists (stub)
    builtins_["ISGLOBALDEFINE"] = [](const std::vector<Value>& args) -> Value {
        return Value(0);
    };
    
    // SETGLOBALDEFINE(name, value) - Set global define (stub)
    builtins_["SETGLOBALDEFINE"] = [](const std::vector<Value>& args) -> Value {
        return Value(1);
    };
    
    // UNDEFGLOBALDEFINE(name) - Undefine global define (stub)
    builtins_["UNDEFGLOBALDEFINE"] = [](const std::vector<Value>& args) -> Value {
        return Value(1);
    };
    
    // PROCESSGLOBALDEFINE(str) - Process global defines (stub)
    builtins_["PROCESSGLOBALDEFINE"] = [](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value("");
        return args[0];
    };
    
    // APPEND_RUNTIME_DIC(code) - Append runtime dictionary (stub)
    builtins_["APPEND_RUNTIME_DIC"] = [](const std::vector<Value>& args) -> Value {
        return Value(0);
    };
    
    // FUNCDECL_READ(funcname) - Read function declaration (stub)
    builtins_["FUNCDECL_READ"] = [](const std::vector<Value>& args) -> Value {
        return Value("");
    };
    
    // FUNCDECL_WRITE(funcname, decl) - Write function declaration (stub)
    builtins_["FUNCDECL_WRITE"] = [](const std::vector<Value>& args) -> Value {
        return Value(0);
    };
    
    // FUNCDECL_ERASE(funcname) - Erase function declaration (stub)
    builtins_["FUNCDECL_ERASE"] = [](const std::vector<Value>& args) -> Value {
        return Value(0);
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
std::string VM::interpolateString(const std::string& str) {
    std::string result;
    size_t pos = 0;
    
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
        
        // Find matching )
        size_t end = str.find(')', start + 2);
        if (end == std::string::npos) {
            // Malformed - just add the rest
            result += str.substr(start);
            break;
        }
        
        // Extract the embedded expression
        std::string expr = str.substr(start + 2, end - start - 2);
        
        // Try to evaluate as variable first
        Value val = getVariable(expr);
        if (!val.isVoid()) {
            result += val.asString();
        } else {
            // Try as function call - for now, just leave it as is
            // Full function call parsing would require re-parsing
            result += "%(" + expr + ")";
        }
        
        pos = end + 1;
    }
    
    return result;
}
