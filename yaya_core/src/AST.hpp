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
    For,
    Foreach,
    Switch,
    Case,
    WhenClause,
    Break,
    Continue,
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

struct ForNode : Node {
    std::shared_ptr<Node> init;   // optional (may be null)
    std::shared_ptr<Node> cond;   // optional (null == always true)
    std::shared_ptr<Node> incr;   // optional (may be null)
    std::vector<std::shared_ptr<Node>> body;

    ForNode(std::shared_ptr<Node> i, std::shared_ptr<Node> c, std::shared_ptr<Node> inc,
            const std::vector<std::shared_ptr<Node>>& b)
        : init(i), cond(c), incr(inc), body(b) {
        type = NodeType::For;
    }
};

struct ForeachNode : Node {
    std::shared_ptr<Node> arrayExpr; // expression yielding the array to iterate
    std::string varName;             // loop variable name
    std::vector<std::shared_ptr<Node>> body;

    ForeachNode(std::shared_ptr<Node> arr, const std::string& var,
                const std::vector<std::shared_ptr<Node>>& b)
        : arrayExpr(arr), varName(var), body(b) {
        type = NodeType::Foreach;
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
    // 関数の型修飾子（YAYA: void / array / sequential / nonoverload / when 等）。未指定は空。
    std::string functionType;

    FunctionNode(const std::string& n, const std::vector<std::shared_ptr<Node>>& b)
        : name(n), body(b) {
        type = NodeType::Function;
    }
};

struct SwitchNode : Node {
    std::shared_ptr<Node> expression;
    std::vector<std::shared_ptr<Node>> cases;  // Each case is an expression (the value to return)
    
    SwitchNode(std::shared_ptr<Node> expr, const std::vector<std::shared_ptr<Node>>& c)
        : expression(expr), cases(c) {
        type = NodeType::Switch;
    }
};

// A single 'when v1, v2, ... { body }' clause inside a case expression.
struct WhenClauseNode : Node {
    std::vector<std::shared_ptr<Node>> matchValues;  // comma-separated match expressions
    std::vector<std::shared_ptr<Node>> body;         // block body to run when any value matches

    WhenClauseNode(const std::vector<std::shared_ptr<Node>>& vals,
                   const std::vector<std::shared_ptr<Node>>& b)
        : matchValues(vals), body(b) {
        type = NodeType::WhenClause;
    }
};

// 'case expr { when ... { } ... others { } }' — evaluates expr once and runs the
// first matching when clause (or the others/default fallback).
struct CaseNode : Node {
    std::shared_ptr<Node> expression;                       // evaluated exactly once
    std::vector<std::shared_ptr<WhenClauseNode>> whenClauses;
    std::vector<std::shared_ptr<Node>> othersBody;          // optional others/default body

    CaseNode(std::shared_ptr<Node> expr,
             const std::vector<std::shared_ptr<WhenClauseNode>>& clauses,
             const std::vector<std::shared_ptr<Node>>& others)
        : expression(expr), whenClauses(clauses), othersBody(others) {
        type = NodeType::Case;
    }
};

struct BreakNode : Node {
    BreakNode() {
        type = NodeType::Break;
    }
};

struct ContinueNode : Node {
    ContinueNode() {
        type = NodeType::Continue;
    }
};

} // namespace AST
