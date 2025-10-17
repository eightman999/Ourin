#include "VM.hpp"
#include <random>
#include <stdexcept>
#include <ctime>
#include <cmath>
#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdlib>

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
