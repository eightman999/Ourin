#include "VM.hpp"
#include <random>
#include <stdexcept>
#include <ctime>

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
                return Value(lit->value);
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
            return getVariable(var->name);
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
        // Interpolate the function name in case it contains variables
        funcName = interpolateString(funcName);
        return Value(functions_.find(funcName) != functions_.end() ? 1 : 0);
    };
    
    // EVAL(funcname) - Execute a function by name
    builtins_["EVAL"] = [this](const std::vector<Value>& args) -> Value {
        if (args.empty()) return Value();
        std::string funcName = args[0].asString();
        // Interpolate the function name in case it contains variables
        funcName = interpolateString(funcName);
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
