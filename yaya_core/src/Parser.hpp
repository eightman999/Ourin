#pragma once

#include "Lexer.hpp"
#include "AST.hpp"
#include <memory>

class Parser {
public:
    explicit Parser(const std::vector<Token>& tokens);
    std::vector<std::shared_ptr<AST::FunctionNode>> parse();

    // Parse exactly one expression and report whether the whole input was
    // consumed without error. Used by ISEVALUABLE. Returns false and sets
    // errorMsg on any parse failure or trailing tokens.
    bool parseExpressionOnly(std::string& errorMsg);
    
private:
    std::vector<Token> tokens_;
    size_t pos_;
    
    const Token& current() const;
    const Token& peek(int offset = 1) const;
    void advance();
    bool match(TokenType type);
    bool check(TokenType type) const;
    void consume(TokenType type, const std::string& message);
    void skipNewlines();
    
    std::shared_ptr<AST::FunctionNode> parseFunction();
    std::shared_ptr<AST::Node> parseStatement();
    std::shared_ptr<AST::Node> parseExpression();
    std::shared_ptr<AST::Node> parseTernary();
    std::shared_ptr<AST::Node> parseLogicalOr();
    std::shared_ptr<AST::Node> parseLogicalAnd();
    std::shared_ptr<AST::Node> parseBitwiseAnd();
    std::shared_ptr<AST::Node> parseEquality();
    std::shared_ptr<AST::Node> parseComparison();
    std::shared_ptr<AST::Node> parseAddition();
    std::shared_ptr<AST::Node> parseMultiplication();
    std::shared_ptr<AST::Node> parseUnary();
    std::shared_ptr<AST::Node> parsePrimary();
    std::shared_ptr<AST::Node> parseAssignment();
    std::shared_ptr<AST::Node> parseIf();
    std::shared_ptr<AST::Node> parseWhile();
    std::shared_ptr<AST::Node> parseFor();
    std::shared_ptr<AST::Node> parseForeach();
    std::shared_ptr<AST::Node> parseBlock();
    std::shared_ptr<AST::Node> parseSwitch();
    std::shared_ptr<AST::Node> parseCase();
    std::shared_ptr<AST::Node> parseStandaloneWhen();

    // When true, '--' is interpreted as a block-literal / switch-case separator
    // rather than postfix decrement. Set while parsing the element list inside
    // `{ a -- b -- c }` block literals and switch `--` blocks so that variable
    // elements (e.g. `{ _x -- _y }`) are not accidentally mutated by postfix --.
    bool blockLiteralMode_ = false;
};
