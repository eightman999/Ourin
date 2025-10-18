#include "Parser.hpp"
#include <stdexcept>
#include <iostream>

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
    while (match(TokenType::Newline) || match(TokenType::Semicolon)) {}
}

std::vector<std::shared_ptr<AST::FunctionNode>> Parser::parse() {
    std::vector<std::shared_ptr<AST::FunctionNode>> functions;

    skipNewlines();

    int safety_counter = 0;
    const int MAX_ITERATIONS = 1000000;  // 安全装置

    while (!check(TokenType::EndOfFile)) {
        size_t pos_before = pos_;  // 位置を記録

        auto func = parseFunction();
        if (func) {
            functions.push_back(func);
        }
        skipNewlines();

        // プログレス保証: 位置が進んでいない場合は強制的に進める
        if (pos_ == pos_before) {
            std::cerr << "[Parser::parse] WARNING: No progress at token '"
                      << current().value << "' (type=" << static_cast<int>(current().type)
                      << ") line " << current().line << ", advancing" << std::endl;
            advance();  // 強制的に進む
        }

        // 無限ループ検出
        if (++safety_counter > MAX_ITERATIONS) {
            std::cerr << "[Parser::parse] ERROR: Infinite loop detected, aborting" << std::endl;
            break;
        }
    }

    return functions;
}

std::shared_ptr<AST::FunctionNode> Parser::parseFunction() {
    if (!check(TokenType::Identifier)) {
        return nullptr;
    }

    // Function name can be dotted (e.g., E.EvalEmbedValue)
    std::string name = current().value;
    advance();
    while (check(TokenType::Dot) && peek().type == TokenType::Identifier) {
        advance(); // consume '.'
        name += "." + current().value;
        advance(); // consume identifier
    }

    skipNewlines();

    // Optional type annotation
    if (match(TokenType::Colon)) {
        skipNewlines();
        if (check(TokenType::Identifier)) {
            advance();
        }
        skipNewlines();
    }

    consume(TokenType::LeftBrace, "Expected '{' after function name");
    skipNewlines();

    std::vector<std::shared_ptr<AST::Node>> body;

    int safety_counter = 0;  // ★ 無限ループ検出用
    const int MAX_ITERATIONS = 100000;  // 10万回で異常判定

    while (!check(TokenType::RightBrace) && !check(TokenType::EndOfFile)) {
        size_t pos_before = pos_;  // ★ 現在位置を記録

        auto stmt = parseStatement();
        if (stmt) {
            body.push_back(stmt);
        }
        skipNewlines();

        // ★★ 重要: 位置が進んでいない場合は強制的に進める
        if (pos_ == pos_before) {
            std::cerr << "[Parser] WARNING: No progress in function '" << name
                      << "' at token '" << current().value
                      << "' (type=" << static_cast<int>(current().type)
                      << ") line " << current().line << std::endl;

            // 次のトークンへ強制的に進む
            advance();
        }

        // ★★ 安全装置: 無限ループ検出
        if (++safety_counter > MAX_ITERATIONS) {
            std::cerr << "[Parser] ERROR: Infinite loop detected in function '"
                      << name << "', aborting parse" << std::endl;
            break;
        }
    }

    if (check(TokenType::RightBrace)) {
        consume(TokenType::RightBrace, "Expected '}' at end of function");
        
        // Optional label after closing brace (e.g., }END_CHANGE)
        if (check(TokenType::Identifier)) {
            advance(); // consume the label
        }
    } else {
        std::cerr << "[Parser] WARNING: Function '" << name
                  << "' ended at EOF instead of '}'" << std::endl;
    }

    return std::make_shared<AST::FunctionNode>(name, body);
}

std::shared_ptr<AST::Node> Parser::parseStatement() {
    skipNewlines();

    // デバッグ出力（最初の数回のみ）
    static int call_count = 0;
    if (call_count++ < 20) {
        std::cerr << "[parseStatement #" << call_count << "] token='"
                  << current().value << "' type=" << static_cast<int>(current().type)
                  << " line=" << current().line << std::endl;
    }

    // EOF チェック
    if (check(TokenType::EndOfFile)) {
        return nullptr;
    }

    // Block as a statement (tolerate stray '{ ... }')
    // Also handle {{LABEL pattern - double braces with label
    if (check(TokenType::LeftBrace)) {
        // Check if this is a labeled block pattern: { { IDENT or { IDENT {
        if (peek().type == TokenType::LeftBrace && peek(2).type == TokenType::Identifier) {
            // This is {{LABEL pattern - consume first brace and let label handling take over
            advance(); // consume first {
            // Now we should have {LABEL which will be handled below
            if (check(TokenType::LeftBrace) && peek().type == TokenType::Identifier) {
                advance(); // consume second {
                advance(); // consume label
                return parseBlock();
            }
        }
        return parseBlock();
    }

    // for statement (C-style)
    if (check(TokenType::For)) {
        return parseFor();
    }
    
    // foreach statement
    if (check(TokenType::Foreach)) {
        return parseForeach();
    }

    // If statement
    if (check(TokenType::If)) {
        return parseIf();
    }

    // While statement
    if (check(TokenType::While)) {
        return parseWhile();
    }

    // Label-like block forms: IDENT '{' or IDENT IDENT '{' (e.g., START_CHANGE { ... } / when X { ... })
    if (check(TokenType::Identifier)) {
        if (peek().type == TokenType::LeftBrace) {
            advance(); // consume label
            return parseBlock();
        }
        if (peek().type == TokenType::Identifier && peek(2).type == TokenType::LeftBrace) {
            advance(); // label 1
            advance(); // label 2
            return parseBlock();
        }
    }

    // Switch statement
    if (check(TokenType::Switch)) {
        return parseSwitch();
    }
    
    // Case statement (pattern matching)
    if (check(TokenType::Case)) {
        return parseCase();
    }
    
    // Standalone when statement (like case but without explicit test expr)
    if (check(TokenType::When)) {
        return parseStandaloneWhen();
    }
    
    // Break statement
    if (check(TokenType::Break)) {
        advance();
        return std::make_shared<AST::BreakNode>();
    }
    
    // Continue statement
    if (check(TokenType::Continue)) {
        advance();
        return std::make_shared<AST::ContinueNode>();
    }
    
    // Return statement
    if (check(TokenType::Return)) {
        advance();
        if (check(TokenType::Newline) || check(TokenType::EndOfFile) || check(TokenType::RightBrace)) {
            return std::make_shared<AST::ReturnNode>(nullptr);
        }
        auto expr = parseExpression();
        return std::make_shared<AST::ReturnNode>(expr);
    }
    
    // Assignment (simple, array, compound)
    // Need to look ahead more carefully to distinguish array access from array assignment
    if (check(TokenType::Identifier)) {
        TokenType nt = peek().type;
        
        // Handle dotted variable assignment: menu.sakura.portalsites = ...
        if (nt == TokenType::Dot) {
            // Look ahead across dotted segments to find the operator after the name
            int offset = 1; // at dot after identifier
            while (peek(offset).type == TokenType::Dot) {
                offset++; // skip dot
                if (peek(offset).type == TokenType::Identifier) {
                    offset++; // skip identifier
                } else {
                    break;
                }
            }
            TokenType next = peek(offset).type;
            if (next == TokenType::Assign ||
                next == TokenType::LeftBracket ||
                next == TokenType::CommaAssign ||
                next == TokenType::PlusAssign ||
                next == TokenType::MinusAssign ||
                next == TokenType::StarAssign ||
                next == TokenType::SlashAssign ||
                next == TokenType::PercentAssign) {
                return parseAssignment();
            }
            // Otherwise, fall through to expression parsing
        }
        else if (nt == TokenType::Assign ||
            nt == TokenType::CommaAssign ||
            nt == TokenType::PlusAssign ||
            nt == TokenType::MinusAssign ||
            nt == TokenType::StarAssign ||
            nt == TokenType::SlashAssign ||
            nt == TokenType::PercentAssign) {
            return parseAssignment();
        }
        // For array access, check if there's an assignment operator after the bracket
        else if (nt == TokenType::LeftBracket) {
            // Look ahead past the bracket expression to see if there's an assignment
            size_t saved_pos = pos_;
            advance(); // skip identifier
            advance(); // skip [
            int bracket_depth = 1;
            while (bracket_depth > 0 && !check(TokenType::EndOfFile)) {
                if (check(TokenType::LeftBracket)) bracket_depth++;
                if (check(TokenType::RightBracket)) bracket_depth--;
                advance();
            }
            // Now check if there's an assignment operator
            bool is_assignment = check(TokenType::Assign) ||
                                 check(TokenType::PlusAssign) ||
                                 check(TokenType::MinusAssign) ||
                                 check(TokenType::StarAssign) ||
                                 check(TokenType::SlashAssign) ||
                                 check(TokenType::PercentAssign) ||
                                 check(TokenType::CommaAssign);
            pos_ = saved_pos; // restore position
            
            if (is_assignment) {
                return parseAssignment();
            }
            // Otherwise, fall through to expression parsing
        }
    }
    // Support dot-prefixed variable assignment: .name(.sub)* op= ... or [] ...
    if (check(TokenType::Dot) && peek().type == TokenType::Identifier) {
        // Look ahead across dotted segments to find the operator after the name
        int offset = 1; // at identifier after initial dot
        while (peek(offset).type == TokenType::Identifier && peek(offset+1).type == TokenType::Dot) {
            offset += 2; // skip IDENT '.' and continue
        }
        // If ended on identifier, move one past it
        if (peek(offset).type == TokenType::Identifier) {
            offset += 1;
        }
        TokenType next = peek(offset).type;
        if (next == TokenType::Assign ||
            next == TokenType::LeftBracket ||
            next == TokenType::CommaAssign ||
            next == TokenType::PlusAssign ||
            next == TokenType::MinusAssign ||
            next == TokenType::StarAssign ||
            next == TokenType::SlashAssign ||
            next == TokenType::PercentAssign) {
            return parseAssignment();
        }
    }

    // ★ 不明なトークンをスキップ
    if (check(TokenType::Unknown)) {
        std::cerr << "[Parser] Skipping unknown token at line " << current().line << std::endl;
        advance();
        return nullptr;
    }

    // Expression statement
    try {
        return parseExpression();
    } catch (const std::exception& e) {
        std::cerr << "[Parser] Error parsing expression: " << e.what() << std::endl;
        // エラーでも nullptr を返して続行
        return nullptr;
    }
}

std::shared_ptr<AST::Node> Parser::parseAssignment() {
    // Parse variable name which may be identifier or dot-prefixed dotted name
    std::string varName;
    if (check(TokenType::Dot)) {
        // .name(.sub)*
        varName += ".";
        advance(); // consume '.'
        if (!check(TokenType::Identifier)) {
            throw std::runtime_error("Expected identifier after '.' in assignment at line " + std::to_string(current().line));
        }
        varName += current().value;
        advance();
        while (match(TokenType::Dot)) {
            if (!check(TokenType::Identifier)) {
                throw std::runtime_error("Expected identifier after '.' in assignment at line " + std::to_string(current().line));
            }
            varName += "." + current().value;
            advance();
        }
    } else if (check(TokenType::Identifier)) {
        // name(.sub)*
        varName = current().value;
        advance();
        while (match(TokenType::Dot)) {
            if (!check(TokenType::Identifier)) {
                throw std::runtime_error("Expected identifier after '.' in assignment at line " + std::to_string(current().line));
            }
            varName += "." + current().value;
            advance();
        }
    } else {
        throw std::runtime_error("Expected variable name in assignment at line " + std::to_string(current().line));
    }
    
    // Array access assignment: var[index] = value or var[index] op= value
    if (match(TokenType::LeftBracket)) {
        // Support single index or comma-separated indices (slice-like)
        // Parse at least one expression
        auto firstIndex = parseExpression();
        std::vector<std::shared_ptr<AST::Node>> indices;
        indices.push_back(firstIndex);
        while (match(TokenType::Comma)) {
            // Allow additional indices
            indices.push_back(parseExpression());
        }
        consume(TokenType::RightBracket, "Expected ']' after array index");
        
        // Check for compound assignment operators
        if (match(TokenType::PlusAssign) || match(TokenType::MinusAssign) ||
            match(TokenType::StarAssign) || match(TokenType::SlashAssign) ||
            match(TokenType::PercentAssign)) {
            TokenType lastOpType = tokens_[pos_-1].type;
            std::string op;
            switch (lastOpType) {
                case TokenType::PlusAssign: op = "+"; break;
                case TokenType::MinusAssign: op = "-"; break;
                case TokenType::StarAssign: op = "*"; break;
                case TokenType::SlashAssign: op = "/"; break;
                case TokenType::PercentAssign: op = "%"; break;
                default: op = "+"; break;
            }
            auto rhs = parseExpression();
            // Create array access node for left side (use first index)
            auto leftAccess = std::make_shared<AST::ArrayAccessNode>(varName, firstIndex);
            auto bin = std::make_shared<AST::BinaryOpNode>(op, leftAccess, rhs);
            // Store the result back to the array element - create a special assignment
            // For now, we'll treat array element compound assignment as a regular compound assignment
            return std::make_shared<AST::AssignmentNode>(varName, bin);
        } else if (match(TokenType::Assign)) {
            // Simple assignment
            auto value = parseExpression();
            // For now, treat this as a simple assignment (array handling is Phase 2)
            return std::make_shared<AST::AssignmentNode>(varName, value);
        } else {
            // No assignment operator - this is an array access expression, not assignment
            // We should not have gotten here - this should be handled as an expression
            throw std::runtime_error("Internal error: array access without assignment at line " + std::to_string(current().line));
        }
    }
    
    // Compound assignment: var op= value
    if (match(TokenType::PlusAssign) || match(TokenType::MinusAssign) ||
        match(TokenType::StarAssign) || match(TokenType::SlashAssign) ||
        match(TokenType::PercentAssign)) {
        // The previous advance() consumed the identifier; current() is after the op token
        // Determine which operator we matched by looking back one token would be complex;
        // Instead, check the previous token type via peek(-1) is not available.
        // Work around: we re-derive operator by looking at tokens_[pos_-1].
        TokenType lastOpType = tokens_[pos_-1].type;
        std::string op;
        switch (lastOpType) {
            case TokenType::PlusAssign: op = "+"; break;
            case TokenType::MinusAssign: op = "-"; break;
            case TokenType::StarAssign: op = "*"; break;
            case TokenType::SlashAssign: op = "/"; break;
            case TokenType::PercentAssign: op = "%"; break;
            default: op = "+"; break;
        }
        auto rhs = parseExpression();
        auto leftVar = std::make_shared<AST::VariableNode>(varName);
        auto bin = std::make_shared<AST::BinaryOpNode>(op, leftVar, rhs);
        return std::make_shared<AST::AssignmentNode>(varName, bin);
    }

    // Array concatenation assignment: var ,= value
    if (match(TokenType::CommaAssign)) {
        auto value = parseExpression();
        // Create a special node for array concatenation
        return std::make_shared<AST::CallNode>("__array_concat_assign__", 
            std::vector<std::shared_ptr<AST::Node>>{
                std::make_shared<AST::VariableNode>(varName),
                value
            });
    }
    
    // Simple assignment: var = value
    consume(TokenType::Assign, "Expected '=' in assignment");
    auto value = parseExpression();
    return std::make_shared<AST::AssignmentNode>(varName, value);
}

std::shared_ptr<AST::Node> Parser::parseIf() {
    // Parse initial if
    consume(TokenType::If, "Expected 'if'");
    std::shared_ptr<AST::Node> condition;
    try {
        condition = parseExpression();
    } catch (...) {
        // Tolerant: fast-forward to '{'
        while (!check(TokenType::LeftBrace) && !check(TokenType::EndOfFile)) {
            advance();
        }
        // Use dummy condition
        condition = std::make_shared<AST::LiteralNode>("1", false);
    }
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

    // Build the root If node
    auto root = std::make_shared<AST::IfNode>(condition, thenBody, std::vector<std::shared_ptr<AST::Node>>{});
    auto currentIf = root;

    // Handle zero or more elseif chains: elseif <cond> { ... }
    while (true) {
        skipNewlines();

        if (match(TokenType::ElseIf)) {
            // Parse elseif condition and block
            std::shared_ptr<AST::Node> elifCond;
            try {
                elifCond = parseExpression();
            } catch (...) {
                while (!check(TokenType::LeftBrace) && !check(TokenType::EndOfFile)) advance();
                elifCond = std::make_shared<AST::LiteralNode>("1", false);
            }
            skipNewlines();
            consume(TokenType::LeftBrace, "Expected '{' after elseif condition");
            skipNewlines();

            std::vector<std::shared_ptr<AST::Node>> elifBody;
            while (!check(TokenType::RightBrace) && !check(TokenType::EndOfFile)) {
                auto stmt = parseStatement();
                if (stmt) {
                    elifBody.push_back(stmt);
                }
                skipNewlines();
            }
            consume(TokenType::RightBrace, "Expected '}' after elseif body");

            // Chain: else { if (...) { ... } }
            auto chained = std::make_shared<AST::IfNode>(elifCond, elifBody, std::vector<std::shared_ptr<AST::Node>>{});
            currentIf->elseBody = { chained };
            currentIf = chained;
            continue;
        }

        // Final else block (optional)
        if (match(TokenType::Else)) {
            skipNewlines();
            // Support "else if ..." as a synonym of "elseif ..."
            if (match(TokenType::If)) {
                std::shared_ptr<AST::Node> elifCond;
                try {
                    elifCond = parseExpression();
                } catch (...) {
                    while (!check(TokenType::LeftBrace) && !check(TokenType::EndOfFile)) advance();
                    elifCond = std::make_shared<AST::LiteralNode>("1", false);
                }
                skipNewlines();
                consume(TokenType::LeftBrace, "Expected '{' after else-if condition");
                skipNewlines();

                std::vector<std::shared_ptr<AST::Node>> elifBody;
                while (!check(TokenType::RightBrace) && !check(TokenType::EndOfFile)) {
                    auto stmt = parseStatement();
                    if (stmt) {
                        elifBody.push_back(stmt);
                    }
                    skipNewlines();
                }
                consume(TokenType::RightBrace, "Expected '}' after else-if body");

                auto chained = std::make_shared<AST::IfNode>(elifCond, elifBody, std::vector<std::shared_ptr<AST::Node>>{});
                currentIf->elseBody = { chained };
                currentIf = chained;
                // Continue loop to allow further elseif/else
                continue;
            } else {
                consume(TokenType::LeftBrace, "Expected '{' after else");
                skipNewlines();

                std::vector<std::shared_ptr<AST::Node>> elseBody;
                while (!check(TokenType::RightBrace) && !check(TokenType::EndOfFile)) {
                    auto stmt = parseStatement();
                    if (stmt) {
                        elseBody.push_back(stmt);
                    }
                    skipNewlines();
                }
                consume(TokenType::RightBrace, "Expected '}' after else body");
                currentIf->elseBody = elseBody;
            }
        }

        break;
    }

    return root;
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

std::shared_ptr<AST::Node> Parser::parseFor() {
    consume(TokenType::For, "Expected 'for'");

    // for initializer: best-effort consume until ';'
    // Support simple assignment initializer, otherwise skip tokens to ';'
    if (check(TokenType::Identifier) && (peek().type == TokenType::Assign ||
        peek().type == TokenType::PlusAssign || peek().type == TokenType::MinusAssign ||
        peek().type == TokenType::StarAssign || peek().type == TokenType::SlashAssign ||
        peek().type == TokenType::PercentAssign)) {
        parseAssignment();
    }
    // Consume until ';'
    while (!check(TokenType::Semicolon) && !check(TokenType::EndOfFile) && !check(TokenType::LeftBrace)) {
        advance();
    }
    if (match(TokenType::Semicolon)) {
        // proceed
    }

    // condition: parse an expression best-effort until ';'
    if (!check(TokenType::Semicolon)) {
        try { (void)parseExpression(); } catch (...) {}
    }
    while (!check(TokenType::Semicolon) && !check(TokenType::EndOfFile) && !check(TokenType::LeftBrace)) {
        advance();
    }
    match(TokenType::Semicolon);

    // increment: allow i++/i-- or assignment; otherwise fast-forward to '{'
    if (check(TokenType::Identifier)) {
        // i++ / i-- pattern
        if (peek().type == TokenType::PlusPlus || peek().type == TokenType::MinusMinus) {
            advance(); // ident
            advance(); // ++ / --
        } else if (peek().type == TokenType::Assign || peek().type == TokenType::PlusAssign ||
                   peek().type == TokenType::MinusAssign || peek().type == TokenType::StarAssign ||
                   peek().type == TokenType::SlashAssign || peek().type == TokenType::PercentAssign) {
            parseAssignment();
        } else {
            // best-effort expression
            try { (void)parseExpression(); } catch (...) {}
        }
    }
    
    // Consume any remaining tokens before the '{'
    while (!check(TokenType::LeftBrace) && !check(TokenType::EndOfFile) && !check(TokenType::Newline)) {
        advance();
    }

    skipNewlines();
    consume(TokenType::LeftBrace, "Expected '{' after for header");
    skipNewlines();

    std::vector<std::shared_ptr<AST::Node>> body;
    while (!check(TokenType::RightBrace) && !check(TokenType::EndOfFile)) {
        auto stmt = parseStatement();
        if (stmt) body.push_back(stmt);
        skipNewlines();
    }
    consume(TokenType::RightBrace, "Expected '}' after for body");

    // Represent 'for' as a while node for now (condition not preserved)
    // Use 'true' literal as condition to keep AST simple
    auto cond = std::make_shared<AST::LiteralNode>("1", false);
    return std::make_shared<AST::WhileNode>(cond, body);
}

std::shared_ptr<AST::Node> Parser::parseForeach() {
    consume(TokenType::Foreach, "Expected 'foreach'");
    
    // Parse: foreach array ; variable { body }
    // The array expression - just parse identifier for now
    skipNewlines();
    if (!check(TokenType::Identifier)) {
        throw std::runtime_error("Expected identifier for array in foreach at line " + std::to_string(current().line));
    }
    std::string arrayName = current().value;
    advance();
    auto arrayExpr = std::make_shared<AST::VariableNode>(arrayName);
    
    // Expect semicolon separator (don't skip newlines before it!)
    if (!check(TokenType::Semicolon)) {
        throw std::runtime_error("Expected ';' after array in foreach (got '" + current().value + "' type=" + std::to_string(static_cast<int>(current().type)) + ") at line " + std::to_string(current().line));
    }
    advance(); // consume semicolon
    skipNewlines();
    
    // The loop variable (identifier)
    if (!check(TokenType::Identifier)) {
        throw std::runtime_error("Expected identifier after ';' in foreach at line " + std::to_string(current().line));
    }
    std::string varName = current().value;
    advance();
    skipNewlines();
    
    // Parse the body
    consume(TokenType::LeftBrace, "Expected '{' after foreach header");
    skipNewlines();
    
    std::vector<std::shared_ptr<AST::Node>> body;
    while (!check(TokenType::RightBrace) && !check(TokenType::EndOfFile)) {
        auto stmt = parseStatement();
        if (stmt) body.push_back(stmt);
        skipNewlines();
    }
    consume(TokenType::RightBrace, "Expected '}' after foreach body");
    
    // Represent 'foreach' as a while node for now (simplified)
    auto cond = std::make_shared<AST::LiteralNode>("1", false);
    return std::make_shared<AST::WhileNode>(cond, body);
}

std::shared_ptr<AST::Node> Parser::parseBlock() {
    consume(TokenType::LeftBrace, "Expected '{' to start block");
    skipNewlines();
    std::vector<std::shared_ptr<AST::Node>> stmts;
    while (!check(TokenType::RightBrace) && !check(TokenType::EndOfFile)) {
        auto s = parseStatement();
        if (s) stmts.push_back(s);
        skipNewlines();
    }
    consume(TokenType::RightBrace, "Expected '}' to close block");
    
    // Optional label after closing brace (e.g., }END_CHANGE)
    if (check(TokenType::Identifier)) {
        advance(); // consume the label
    }
    
    return std::make_shared<AST::BlockNode>(stmts);
}

std::shared_ptr<AST::Node> Parser::parseSwitch() {
    consume(TokenType::Switch, "Expected 'switch'");
    skipNewlines();
    
    // Parse the switch expression
    auto expr = parseExpression();
    skipNewlines();
    
    consume(TokenType::LeftBrace, "Expected '{' after switch expression");
    skipNewlines();
    
    // Parse case values (in YAYA, these are just expressions, one per line)
    // The switch returns the expression at index equal to the switch value
    std::vector<std::shared_ptr<AST::Node>> cases;
    while (!check(TokenType::RightBrace) && !check(TokenType::EndOfFile)) {
        // Each line in the switch block is a potential return value
        auto caseExpr = parseExpression();
        if (caseExpr) {
            cases.push_back(caseExpr);
        }
        skipNewlines();
    }
    
    consume(TokenType::RightBrace, "Expected '}' after switch cases");
    
    return std::make_shared<AST::SwitchNode>(expr, cases);
}

std::shared_ptr<AST::Node> Parser::parseCase() {
    consume(TokenType::Case, "Expected 'case'");
    skipNewlines();
    
    // Parse the case expression (value to match against)
    auto expr = parseExpression();
    skipNewlines();
    
    consume(TokenType::LeftBrace, "Expected '{' after case expression");
    skipNewlines();
    
    // Parse when clauses
    // Syntax: when val1, val2, val3 { block }
    // We'll implement this as a series of if-else checks
    std::vector<std::shared_ptr<AST::Node>> whenClauses;
    
    while (!check(TokenType::RightBrace) && !check(TokenType::EndOfFile)) {
        if (check(TokenType::When)) {
            advance(); // consume 'when'
            skipNewlines();
            
            // Parse comma-separated match values
            std::vector<std::shared_ptr<AST::Node>> matchValues;
            matchValues.push_back(parseExpression());
            
            while (match(TokenType::Comma)) {
                skipNewlines();
                matchValues.push_back(parseExpression());
            }
            
            skipNewlines();
            
            // Parse the when block
            auto block = parseBlock();
            
            // Create an if-else chain: if (expr == val1 || expr == val2 ...) { block }
            // We need to clone the expr node for each comparison
            // For simplicity, we'll use a variable node if expr is an identifier
            std::shared_ptr<AST::Node> condition = nullptr;
            for (size_t i = 0; i < matchValues.size(); i++) {
                // Create a new comparison for each value
                // Note: This assumes expr is side-effect free (typically a variable)
                auto comparison = std::make_shared<AST::BinaryOpNode>("==", expr, matchValues[i]);
                if (condition == nullptr) {
                    condition = comparison;
                } else {
                    condition = std::make_shared<AST::BinaryOpNode>("||", condition, comparison);
                }
            }
            
            std::vector<std::shared_ptr<AST::Node>> blockBody = { block };
            whenClauses.push_back(std::make_shared<AST::IfNode>(condition, blockBody, std::vector<std::shared_ptr<AST::Node>>()));
            
            skipNewlines();
        } else if (check(TokenType::Default)) {
            advance(); // consume 'default'
            skipNewlines();
            auto block = parseBlock();
            whenClauses.push_back(block);
            skipNewlines();
        } else if (check(TokenType::Identifier) && current().value == "others") {
            // 'others' is an alias for 'default'
            advance(); // consume 'others'
            skipNewlines();
            auto block = parseBlock();
            whenClauses.push_back(block);
            skipNewlines();
        } else {
            // Skip unexpected tokens
            advance();
        }
    }
    
    consume(TokenType::RightBrace, "Expected '}' after case body");
    
    // Return a block containing all the when clauses
    return std::make_shared<AST::BlockNode>(whenClauses);
}

std::shared_ptr<AST::Node> Parser::parseStandaloneWhen() {
    // Standalone when statement: when val1, val2 { block }
    // This is like a case clause without an explicit test expression
    // We'll treat it as if it's checking against some implicit state variable
    
    advance(); // consume 'when'
    skipNewlines();
    
    // Parse comma-separated match values
    std::vector<std::shared_ptr<AST::Node>> matchValues;
    matchValues.push_back(parseExpression());
    
    while (match(TokenType::Comma)) {
        skipNewlines();
        matchValues.push_back(parseExpression());
    }
    
    skipNewlines();
    
    // Parse the when block
    auto block = parseBlock();
    
    // For standalone when, we can't build a proper condition without knowing
    // what to compare against. We'll just return the block for now.
    // In actual YAYA, these are typically handled by runtime context.
    // For parsing purposes, we'll wrap it in a labeled block.
    return block;
}

std::shared_ptr<AST::Node> Parser::parseExpression() {
    return parseTernary();
}

std::shared_ptr<AST::Node> Parser::parseTernary() {
    auto expr = parseLogicalOr();
    
    // Check for assignment operators (in YAYA, assignment can be an expression)
    if (check(TokenType::Assign) || check(TokenType::CommaAssign) ||
        check(TokenType::PlusAssign) || check(TokenType::MinusAssign) ||
        check(TokenType::StarAssign) || check(TokenType::SlashAssign) ||
        check(TokenType::PercentAssign)) {
        // This is an assignment expression
        // For now, just parse it as a special function call: __assign__(lhs, rhs)
        TokenType assignOp = current().type;
        advance();
        auto rhs = parseExpression();
        
        // Create assignment as a function call (simplified approach)
        std::string assignFunc = "__assign__";
        if (assignOp == TokenType::CommaAssign) assignFunc = "__concat_assign__";
        else if (assignOp == TokenType::PlusAssign) assignFunc = "__plus_assign__";
        else if (assignOp == TokenType::MinusAssign) assignFunc = "__minus_assign__";
        else if (assignOp == TokenType::StarAssign) assignFunc = "__star_assign__";
        else if (assignOp == TokenType::SlashAssign) assignFunc = "__slash_assign__";
        else if (assignOp == TokenType::PercentAssign) assignFunc = "__percent_assign__";
        
        return std::make_shared<AST::CallNode>(assignFunc, std::vector<std::shared_ptr<AST::Node>>{ expr, rhs });
    }
    
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
        } else if (check(TokenType::Not) && peek().type == TokenType::In) {
            // Handle !_in_ as negated _in_ operator
            advance(); // consume '!'
            advance(); // consume '_in_'
            auto right = parseComparison();
            auto inNode = std::make_shared<AST::BinaryOpNode>("_in_", left, right);
            left = std::make_shared<AST::UnaryOpNode>("!", inNode);
        } else if (match(TokenType::In)) {
            auto right = parseComparison();
            left = std::make_shared<AST::BinaryOpNode>("_in_", left, right);
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
    // Unary plus (no-op)
    if (match(TokenType::Plus)) {
        return parseUnary();
    }
    // Address-of or byref indicator '&'
    if (match(TokenType::Ampersand)) {
        auto operand = parseUnary();
        return std::make_shared<AST::UnaryOpNode>("&", operand);
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
    
    // Identifier (variable, member, function call) with postfix support ([], etc.)
    if (check(TokenType::Identifier)) {
        std::string name = current().value;
        advance();

        // Member access: identifier.member (flatten into dotted name)
        while (match(TokenType::Dot)) {
            if (check(TokenType::Identifier)) {
                name += "." + current().value;
                advance();
            } else {
                throw std::runtime_error("Expected identifier after '.' at line " + std::to_string(current().line));
            }
        }

        // Start with a simple variable node
        std::shared_ptr<AST::Node> node = std::make_shared<AST::VariableNode>(name);

        // Postfix increment/decrement apply only to identifiers
        if (match(TokenType::PlusPlus) || match(TokenType::MinusMinus)) {
            TokenType last = tokens_[pos_-1].type;
            std::string kind = (last == TokenType::PlusPlus) ? "__postinc__" : "__postdec__";
            return std::make_shared<AST::CallNode>(kind, std::vector<std::shared_ptr<AST::Node>>{ std::make_shared<AST::VariableNode>(name)});
        }

        // Optional function call immediately after identifier
        if (match(TokenType::LeftParen)) {
            std::vector<std::shared_ptr<AST::Node>> args;
            if (!check(TokenType::RightParen)) {
                do {
                    args.push_back(parseExpression());
                } while (match(TokenType::Comma));
            }
            consume(TokenType::RightParen, "Expected ')' after function arguments");
            node = std::make_shared<AST::CallNode>(name, args);
        }

        // Support chained indexing after variable or call result: foo[0], foo()[0], a[0][1], ...
        while (match(TokenType::LeftBracket)) {
            auto indexExpr = parseExpression();
            
            // Check for array range syntax: [start, end]
            if (match(TokenType::Comma)) {
                auto endExpr = parseExpression();
                // Create a special range access using __range__ call
                if (auto* var = dynamic_cast<AST::VariableNode*>(node.get())) {
                    node = std::make_shared<AST::CallNode>(
                        "__range__",
                        std::vector<std::shared_ptr<AST::Node>>{ 
                            std::make_shared<AST::VariableNode>(var->name), 
                            indexExpr, 
                            endExpr 
                        }
                    );
                } else {
                    node = std::make_shared<AST::CallNode>(
                        "__range__",
                        std::vector<std::shared_ptr<AST::Node>>{ node, indexExpr, endExpr }
                    );
                }
            } else {
                // Regular array access
                // If current node is a plain variable, keep using ArrayAccessNode for compatibility
                if (auto* var = dynamic_cast<AST::VariableNode*>(node.get())) {
                    node = std::make_shared<AST::ArrayAccessNode>(var->name, indexExpr);
                } else {
                    // For call results or nested accesses, use special __index__ call: __index__(base, index)
                    node = std::make_shared<AST::CallNode>(
                        "__index__",
                        std::vector<std::shared_ptr<AST::Node>>{ node, indexExpr }
                    );
                }
            }
            
            consume(TokenType::RightBracket, "Expected ']' after array index");
        }

        return node;
    }
    
    // Block literal with -- separator: { expr1 -- expr2 -- expr3 }
    if (match(TokenType::LeftBrace)) {
        std::vector<std::shared_ptr<AST::Node>> elements;
        skipNewlines();
        
        while (!check(TokenType::RightBrace) && !check(TokenType::EndOfFile)) {
            // Parse an expression
            auto expr = parseExpression();
            elements.push_back(expr);
            skipNewlines();
            
            // Check for -- separator (treated as MinusMinus token in this context)
            if (check(TokenType::MinusMinus)) {
                advance(); // consume --
                skipNewlines();
            }
            
            // If we hit a closing brace or another expression separator, continue
            if (check(TokenType::RightBrace)) {
                break;
            }
        }
        
        consume(TokenType::RightBrace, "Expected '}' after block literal");
        
        // Create an array literal from the block
        return std::make_shared<AST::CallNode>("__array_literal__", elements);
    }
    
    // Parenthesized expression or array literal; allow postfix indexing after ')'
    if (match(TokenType::LeftParen)) {
        // Check if this is an array literal by looking for comma
        auto firstExpr = parseExpression();

        if (match(TokenType::Comma)) {
            // This is an array literal
            std::vector<std::shared_ptr<AST::Node>> elements;
            elements.push_back(firstExpr);

            do {
                // Allow empty elements or trailing commas
                if (!check(TokenType::RightParen)) {
                    elements.push_back(parseExpression());
                }
            } while (match(TokenType::Comma) && !check(TokenType::RightParen));

            consume(TokenType::RightParen, "Expected ')' after array literal");

            // Create an array literal node
            std::shared_ptr<AST::Node> node = std::make_shared<AST::CallNode>("__array_literal__", elements);

            // Allow indexing on the array literal result: (1,2,3)[0]
            while (match(TokenType::LeftBracket)) {
                auto indexExpr = parseExpression();
                consume(TokenType::RightBracket, "Expected ']' after array index");
                node = std::make_shared<AST::CallNode>(
                    "__index__",
                    std::vector<std::shared_ptr<AST::Node>>{ node, indexExpr }
                );
            }
            return node;
        } else {
            // Regular parenthesized expression
            consume(TokenType::RightParen, "Expected ')' after expression");

            // Support indexing after a parenthesized expression: (expr)[idx]
            std::shared_ptr<AST::Node> node = firstExpr;
            while (match(TokenType::LeftBracket)) {
                auto indexExpr = parseExpression();
                consume(TokenType::RightBracket, "Expected ']' after array index");
                node = std::make_shared<AST::CallNode>(
                    "__index__",
                    std::vector<std::shared_ptr<AST::Node>>{ node, indexExpr }
                );
            }
            return node;
        }
    }

    // ★ More detailed error message
    std::string error_msg = "Unexpected token '";
    error_msg += current().value;
    error_msg += "' (type: " + std::to_string(static_cast<int>(current().type)) + ")";
    error_msg += " in expression at line " + std::to_string(current().line);

    // ★ Debug: show surrounding tokens for context
    std::cerr << "[Parser] Context: ";
    for (int i = -2; i <= 2; i++) {
        const Token& t = peek(i);
        std::cerr << "'" << t.value << "' ";
    }
    std::cerr << std::endl;

    throw std::runtime_error(error_msg);
}
