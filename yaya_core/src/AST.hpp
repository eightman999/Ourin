#pragma once

#include <string>
#include <vector>
#include <memory>

namespace AST {

enum class NodeType {
    Function,
    Block,
    Return,
    Assignment,
    If,
    While,
    BinaryOp,
    UnaryOp,
    Ternary,
    Call,
    Variable,
    Literal,
    ArrayAccess
};

struct Node {
    NodeType type;
    virtual ~Node() = default;
};

struct LiteralNode : Node {
    std::string value;
    bool isString;
    
    explicit LiteralNode(const std::string& v, bool str = false) : value(v), isString(str) {
        type = NodeType::Literal;
    }
};

struct VariableNode : Node {
    std::string name;
    
    explicit VariableNode(const std::string& n) : name(n) {
        type = NodeType::Variable;
    }
};

struct BinaryOpNode : Node {
    std::string op;
    std::shared_ptr<Node> left;
    std::shared_ptr<Node> right;
    
    BinaryOpNode(const std::string& o, std::shared_ptr<Node> l, std::shared_ptr<Node> r)
        : op(o), left(l), right(r) {
        type = NodeType::BinaryOp;
    }
};

struct UnaryOpNode : Node {
    std::string op;
    std::shared_ptr<Node> operand;
    
    UnaryOpNode(const std::string& o, std::shared_ptr<Node> operand)
        : op(o), operand(operand) {
        type = NodeType::UnaryOp;
    }
};

struct TernaryNode : Node {
    std::shared_ptr<Node> condition;
    std::shared_ptr<Node> trueBranch;
    std::shared_ptr<Node> falseBranch;
    
    TernaryNode(std::shared_ptr<Node> c, std::shared_ptr<Node> t, std::shared_ptr<Node> f)
        : condition(c), trueBranch(t), falseBranch(f) {
        type = NodeType::Ternary;
    }
};

struct CallNode : Node {
    std::string functionName;
    std::vector<std::shared_ptr<Node>> arguments;
    
    CallNode(const std::string& name, const std::vector<std::shared_ptr<Node>>& args)
        : functionName(name), arguments(args) {
        type = NodeType::Call;
    }
};

struct ArrayAccessNode : Node {
    std::string arrayName;
    std::shared_ptr<Node> index;
    
    ArrayAccessNode(const std::string& name, std::shared_ptr<Node> idx)
        : arrayName(name), index(idx) {
        type = NodeType::ArrayAccess;
    }
};

struct AssignmentNode : Node {
    std::string variableName;
    std::shared_ptr<Node> value;
    
    AssignmentNode(const std::string& name, std::shared_ptr<Node> val)
        : variableName(name), value(val) {
        type = NodeType::Assignment;
    }
};

struct ReturnNode : Node {
    std::shared_ptr<Node> value;
    
    explicit ReturnNode(std::shared_ptr<Node> val) : value(val) {
        type = NodeType::Return;
    }
};

struct IfNode : Node {
    std::shared_ptr<Node> condition;
    std::vector<std::shared_ptr<Node>> thenBody;
    std::vector<std::shared_ptr<Node>> elseBody;
    
    IfNode(std::shared_ptr<Node> cond,
           const std::vector<std::shared_ptr<Node>>& then,
           const std::vector<std::shared_ptr<Node>>& els)
        : condition(cond), thenBody(then), elseBody(els) {
        type = NodeType::If;
    }
};

struct WhileNode : Node {
    std::shared_ptr<Node> condition;
    std::vector<std::shared_ptr<Node>> body;
    
    WhileNode(std::shared_ptr<Node> cond, const std::vector<std::shared_ptr<Node>>& b)
        : condition(cond), body(b) {
        type = NodeType::While;
    }
};

struct BlockNode : Node {
    std::vector<std::shared_ptr<Node>> statements;
    
    explicit BlockNode(const std::vector<std::shared_ptr<Node>>& stmts)
        : statements(stmts) {
        type = NodeType::Block;
    }
};

struct FunctionNode : Node {
    std::string name;
    std::vector<std::shared_ptr<Node>> body;
    
    FunctionNode(const std::string& n, const std::vector<std::shared_ptr<Node>>& b)
        : name(n), body(b) {
        type = NodeType::Function;
    }
};

} // namespace AST
