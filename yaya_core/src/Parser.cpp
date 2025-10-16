#include "Parser.hpp"
#include <stdexcept>

Parser::Parser(const std::vector<Token>& tokens) : tokens_(tokens), pos_(0) {}

const Token& Parser::current() const {
    if (pos_ >= tokens_.size()) {
        static Token eof(TokenType::EndOfFile);
        return eof;
    }
    return tokens_[pos_];
}

const Token& Parser::peek(int offset) const {
    size_t peekPos = pos_ + offset;
    if (peekPos >= tokens_.size()) {
        static Token eof(TokenType::EndOfFile);
        return eof;
    }
    return tokens_[peekPos];
}

void Parser::advance() {
    if (pos_ < tokens_.size()) pos_++;
}

bool Parser::match(TokenType type) {
    if (check(type)) {
        advance();
        return true;
    }
    return false;
}

bool Parser::check(TokenType type) const {
    return current().type == type;
}

void Parser::consume(TokenType type, const std::string& message) {
    if (!check(type)) {
        throw std::runtime_error(message + " at line " + std::to_string(current().line));
    }
    advance();
}

void Parser::skipNewlines() {
    while (match(TokenType::Newline)) {}
}

std::vector<std::shared_ptr<AST::FunctionNode>> Parser::parse() {
    std::vector<std::shared_ptr<AST::FunctionNode>> functions;
    
    skipNewlines();
    
    while (!check(TokenType::EndOfFile)) {
        auto func = parseFunction();
        if (func) {
            functions.push_back(func);
        }
        skipNewlines();
    }
    
    return functions;
}

std::shared_ptr<AST::FunctionNode> Parser::parseFunction() {
    // Function: FunctionName { statements }
    if (!check(TokenType::Identifier)) {
        return nullptr;
    }
    
    std::string name = current().value;
    advance();
    
    skipNewlines();
    consume(TokenType::LeftBrace, "Expected '{' after function name");
    skipNewlines();
    
    std::vector<std::shared_ptr<AST::Node>> body;
    
    while (!check(TokenType::RightBrace) && !check(TokenType::EndOfFile)) {
        auto stmt = parseStatement();
        if (stmt) {
            body.push_back(stmt);
        }
        skipNewlines();
    }
    
    consume(TokenType::RightBrace, "Expected '}' at end of function");
    
    return std::make_shared<AST::FunctionNode>(name, body);
}

std::shared_ptr<AST::Node> Parser::parseStatement() {
    skipNewlines();
    
    // If statement
    if (check(TokenType::If)) {
        return parseIf();
    }
    
    // While statement
    if (check(TokenType::While)) {
        return parseWhile();
    }
    
    // Assignment or expression
    if (check(TokenType::Identifier)) {
        // Check if this is an assignment
        if (peek().type == TokenType::Assign || peek().type == TokenType::LeftBracket) {
            return parseAssignment();
        }
    }
    
    // Expression statement (including literals which serve as return values in YAYA)
    return parseExpression();
}

std::shared_ptr<AST::Node> Parser::parseAssignment() {
    std::string varName = current().value;
    advance();
    
    // Array access assignment: var[index] = value
    if (match(TokenType::LeftBracket)) {
        auto index = parseExpression();
        consume(TokenType::RightBracket, "Expected ']' after array index");
        consume(TokenType::Assign, "Expected '=' in assignment");
        auto value = parseExpression();
        // For now, treat this as a simple assignment (array handling is Phase 2)
        return std::make_shared<AST::AssignmentNode>(varName, value);
    }
    
    // Simple assignment: var = value
    consume(TokenType::Assign, "Expected '=' in assignment");
    auto value = parseExpression();
    return std::make_shared<AST::AssignmentNode>(varName, value);
}

std::shared_ptr<AST::Node> Parser::parseIf() {
    consume(TokenType::If, "Expected 'if'");
    
    auto condition = parseExpression();
    
    skipNewlines();
    consume(TokenType::LeftBrace, "Expected '{' after if condition");
    skipNewlines();
    
    std::vector<std::shared_ptr<AST::Node>> thenBody;
    while (!check(TokenType::RightBrace) && !check(TokenType::EndOfFile)) {
        auto stmt = parseStatement();
        if (stmt) {
            thenBody.push_back(stmt);
        }
        skipNewlines();
    }
    
    consume(TokenType::RightBrace, "Expected '}' after if body");
    
    std::vector<std::shared_ptr<AST::Node>> elseBody;
    skipNewlines();
    
    if (match(TokenType::Else)) {
        skipNewlines();
        consume(TokenType::LeftBrace, "Expected '{' after else");
        skipNewlines();
        
        while (!check(TokenType::RightBrace) && !check(TokenType::EndOfFile)) {
            auto stmt = parseStatement();
            if (stmt) {
                elseBody.push_back(stmt);
            }
            skipNewlines();
        }
        
        consume(TokenType::RightBrace, "Expected '}' after else body");
    }
    
    return std::make_shared<AST::IfNode>(condition, thenBody, elseBody);
}

std::shared_ptr<AST::Node> Parser::parseWhile() {
    consume(TokenType::While, "Expected 'while'");
    
    auto condition = parseExpression();
    
    skipNewlines();
    consume(TokenType::LeftBrace, "Expected '{' after while condition");
    skipNewlines();
    
    std::vector<std::shared_ptr<AST::Node>> body;
    while (!check(TokenType::RightBrace) && !check(TokenType::EndOfFile)) {
        auto stmt = parseStatement();
        if (stmt) {
            body.push_back(stmt);
        }
        skipNewlines();
    }
    
    consume(TokenType::RightBrace, "Expected '}' after while body");
    
    return std::make_shared<AST::WhileNode>(condition, body);
}

std::shared_ptr<AST::Node> Parser::parseExpression() {
    return parseTernary();
}

std::shared_ptr<AST::Node> Parser::parseTernary() {
    auto expr = parseLogicalOr();
    
    if (match(TokenType::Question)) {
        auto trueBranch = parseExpression();
        consume(TokenType::Colon, "Expected ':' in ternary expression");
        auto falseBranch = parseExpression();
        return std::make_shared<AST::TernaryNode>(expr, trueBranch, falseBranch);
    }
    
    return expr;
}

std::shared_ptr<AST::Node> Parser::parseLogicalOr() {
    auto left = parseLogicalAnd();
    
    while (match(TokenType::Or)) {
        auto right = parseLogicalAnd();
        left = std::make_shared<AST::BinaryOpNode>("||", left, right);
    }
    
    return left;
}

std::shared_ptr<AST::Node> Parser::parseLogicalAnd() {
    auto left = parseEquality();
    
    while (match(TokenType::And)) {
        auto right = parseEquality();
        left = std::make_shared<AST::BinaryOpNode>("&&", left, right);
    }
    
    return left;
}

std::shared_ptr<AST::Node> Parser::parseEquality() {
    auto left = parseComparison();
    
    while (true) {
        if (match(TokenType::Equal)) {
            auto right = parseComparison();
            left = std::make_shared<AST::BinaryOpNode>("==", left, right);
        } else if (match(TokenType::NotEqual)) {
            auto right = parseComparison();
            left = std::make_shared<AST::BinaryOpNode>("!=", left, right);
        } else {
            break;
        }
    }
    
    return left;
}

std::shared_ptr<AST::Node> Parser::parseComparison() {
    auto left = parseAddition();
    
    while (true) {
        if (match(TokenType::Less)) {
            auto right = parseAddition();
            left = std::make_shared<AST::BinaryOpNode>("<", left, right);
        } else if (match(TokenType::Greater)) {
            auto right = parseAddition();
            left = std::make_shared<AST::BinaryOpNode>(">", left, right);
        } else if (match(TokenType::LessEqual)) {
            auto right = parseAddition();
            left = std::make_shared<AST::BinaryOpNode>("<=", left, right);
        } else if (match(TokenType::GreaterEqual)) {
            auto right = parseAddition();
            left = std::make_shared<AST::BinaryOpNode>(">=", left, right);
        } else {
            break;
        }
    }
    
    return left;
}

std::shared_ptr<AST::Node> Parser::parseAddition() {
    auto left = parseMultiplication();
    
    while (true) {
        if (match(TokenType::Plus)) {
            auto right = parseMultiplication();
            left = std::make_shared<AST::BinaryOpNode>("+", left, right);
        } else if (match(TokenType::Minus)) {
            auto right = parseMultiplication();
            left = std::make_shared<AST::BinaryOpNode>("-", left, right);
        } else {
            break;
        }
    }
    
    return left;
}

std::shared_ptr<AST::Node> Parser::parseMultiplication() {
    auto left = parseUnary();
    
    while (true) {
        if (match(TokenType::Star)) {
            auto right = parseUnary();
            left = std::make_shared<AST::BinaryOpNode>("*", left, right);
        } else if (match(TokenType::Slash)) {
            auto right = parseUnary();
            left = std::make_shared<AST::BinaryOpNode>("/", left, right);
        } else if (match(TokenType::Percent)) {
            auto right = parseUnary();
            left = std::make_shared<AST::BinaryOpNode>("%", left, right);
        } else {
            break;
        }
    }
    
    return left;
}

std::shared_ptr<AST::Node> Parser::parseUnary() {
    if (match(TokenType::Not)) {
        auto operand = parseUnary();
        return std::make_shared<AST::UnaryOpNode>("!", operand);
    }
    
    if (match(TokenType::Minus)) {
        auto operand = parseUnary();
        return std::make_shared<AST::UnaryOpNode>("-", operand);
    }
    
    return parsePrimary();
}

std::shared_ptr<AST::Node> Parser::parsePrimary() {
    // String literal
    if (check(TokenType::String)) {
        auto value = current().value;
        advance();
        return std::make_shared<AST::LiteralNode>(value, true);
    }
    
    // Integer literal
    if (check(TokenType::Integer)) {
        auto value = current().value;
        advance();
        return std::make_shared<AST::LiteralNode>(value, false);
    }
    
    // Identifier (variable or function call)
    if (check(TokenType::Identifier)) {
        std::string name = current().value;
        advance();
        
        // Array access: identifier[index]
        if (match(TokenType::LeftBracket)) {
            auto index = parseExpression();
            consume(TokenType::RightBracket, "Expected ']' after array index");
            return std::make_shared<AST::ArrayAccessNode>(name, index);
        }
        
        // Function call: identifier(args)
        if (match(TokenType::LeftParen)) {
            std::vector<std::shared_ptr<AST::Node>> args;
            
            if (!check(TokenType::RightParen)) {
                do {
                    args.push_back(parseExpression());
                } while (match(TokenType::Comma));
            }
            
            consume(TokenType::RightParen, "Expected ')' after function arguments");
            return std::make_shared<AST::CallNode>(name, args);
        }
        
        // Simple variable
        return std::make_shared<AST::VariableNode>(name);
    }
    
    // Parenthesized expression
    if (match(TokenType::LeftParen)) {
        auto expr = parseExpression();
        consume(TokenType::RightParen, "Expected ')' after expression");
        return expr;
    }
    
    throw std::runtime_error("Unexpected token in expression at line " + std::to_string(current().line));
}
