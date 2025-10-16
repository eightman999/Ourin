#pragma once

#include "Lexer.hpp"
#include "AST.hpp"
#include <memory>

class Parser {
public:
    explicit Parser(const std::vector<Token>& tokens);
    std::vector<std::shared_ptr<AST::FunctionNode>> parse();
    
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
    std::shared_ptr<AST::Node> parseEquality();
    std::shared_ptr<AST::Node> parseComparison();
    std::shared_ptr<AST::Node> parseAddition();
    std::shared_ptr<AST::Node> parseMultiplication();
    std::shared_ptr<AST::Node> parseUnary();
    std::shared_ptr<AST::Node> parsePrimary();
    std::shared_ptr<AST::Node> parseAssignment();
    std::shared_ptr<AST::Node> parseIf();
    std::shared_ptr<AST::Node> parseWhile();
};
