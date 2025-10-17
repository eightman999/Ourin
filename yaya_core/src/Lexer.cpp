#include "Lexer.hpp"
#include <cctype>

Lexer::Lexer(const std::string& source)
    : source_(source), pos_(0), line_(1), column_(1) {}

char Lexer::current() const {
    if (pos_ >= source_.length()) return '\0';
    return source_[pos_];
}

char Lexer::peek(int offset) const {
    size_t peekPos = pos_ + offset;
    if (peekPos >= source_.length()) return '\0';
    return source_[peekPos];
}

void Lexer::advance() {
    if (pos_ < source_.length()) {
        if (source_[pos_] == '\n') {
            line_++;
            column_ = 1;
        } else {
            column_++;
        }
        pos_++;
    }
}

void Lexer::skipWhitespace() {
    while (current() != '\0' && std::isspace(current()) && current() != '\n') {
        advance();
    }
}

void Lexer::skipComment() {
    // Line comment //
    if (current() == '/' && peek() == '/') {
        while (current() != '\0' && current() != '\n') {
            advance();
        }
        return;
    }
    
    // Block comment /* */
    if (current() == '/' && peek() == '*') {
        advance(); // /
        advance(); // *
        while (current() != '\0') {
            if (current() == '*' && peek() == '/') {
                advance(); // *
                advance(); // /
                break;
            }
            advance();
        }
    }
}

Token Lexer::readString() {
    int startLine = line_;
    int startCol = column_;
    std::string value;
    char quote = current(); // Can be '"' or '\''
    
    advance(); // Skip opening quote
    
    while (current() != '\0' && current() != quote) {
        if (current() == '\\') {
            advance();
            if (current() != '\0') {
                // Handle escape sequences
                switch (current()) {
                    case 'n': value += '\n'; break;
                    case 't': value += '\t'; break;
                    case 'r': value += '\r'; break;
                    case '\\': value += '\\'; break;
                    case '"': value += '"'; break;
                    case '\'': value += '\''; break;
                    default: value += current(); break;
                }
                advance();
            }
        } else {
            value += current();
            advance();
        }
    }
    
    if (current() == quote) {
        advance(); // Skip closing quote
    }
    
    return Token(TokenType::String, value, startLine, startCol);
}

Token Lexer::readNumber() {
    int startLine = line_;
    int startCol = column_;
    std::string value;
    
    while (std::isdigit(current())) {
        value += current();
        advance();
    }
    
    return Token(TokenType::Integer, value, startLine, startCol);
}

Token Lexer::readIdentifier() {
    int startLine = line_;
    int startCol = column_;
    std::string value;
    
    while (current() != '\0' && (std::isalnum(current()) || current() == '_')) {
        value += current();
        advance();
    }
    
    // Check for keywords
    TokenType type = TokenType::Identifier;
    if (value == "if") type = TokenType::If;
    else if (value == "else") type = TokenType::Else;
    else if (value == "while") type = TokenType::While;
    else if (value == "foreach") type = TokenType::Foreach;
    
    return Token(type, value, startLine, startCol);
}

std::vector<Token> Lexer::tokenize() {
    std::vector<Token> tokens;
    
    while (current() != '\0') {
        skipWhitespace();
        
        // Skip comments
        if (current() == '/' && (peek() == '/' || peek() == '*')) {
            skipComment();
            continue;
        }
        
        int startLine = line_;
        int startCol = column_;
        char ch = current();
        
        // End of file
        if (ch == '\0') break;
        
        // Newline
        if (ch == '\n') {
            tokens.push_back(Token(TokenType::Newline, "\n", startLine, startCol));
            advance();
            continue;
        }
        
        // String (double or single quotes)
        if (ch == '"' || ch == '\'') {
            tokens.push_back(readString());
            continue;
        }
        
        // Number
        if (std::isdigit(ch)) {
            tokens.push_back(readNumber());
            continue;
        }
        
        // Identifier or keyword
        if (std::isalpha(ch) || ch == '_') {
            tokens.push_back(readIdentifier());
            continue;
        }
        
        // Two-character operators
        if (ch == '=' && peek() == '=') {
            tokens.push_back(Token(TokenType::Equal, "==", startLine, startCol));
            advance(); advance();
            continue;
        }
        if (ch == '!' && peek() == '=') {
            tokens.push_back(Token(TokenType::NotEqual, "!=", startLine, startCol));
            advance(); advance();
            continue;
        }
        if (ch == '<' && peek() == '=') {
            tokens.push_back(Token(TokenType::LessEqual, "<=", startLine, startCol));
            advance(); advance();
            continue;
        }
        if (ch == '>' && peek() == '=') {
            tokens.push_back(Token(TokenType::GreaterEqual, ">=", startLine, startCol));
            advance(); advance();
            continue;
        }
        if (ch == '&' && peek() == '&') {
            tokens.push_back(Token(TokenType::And, "&&", startLine, startCol));
            advance(); advance();
            continue;
        }
        if (ch == '|' && peek() == '|') {
            tokens.push_back(Token(TokenType::Or, "||", startLine, startCol));
            advance(); advance();
            continue;
        }
        if (ch == ',' && peek() == '=') {
            tokens.push_back(Token(TokenType::CommaAssign, ",=", startLine, startCol));
            advance(); advance();
            continue;
        }
        
        // Single-character tokens
        switch (ch) {
            case '+': tokens.push_back(Token(TokenType::Plus, "+", startLine, startCol)); break;
            case '-': tokens.push_back(Token(TokenType::Minus, "-", startLine, startCol)); break;
            case '*': tokens.push_back(Token(TokenType::Star, "*", startLine, startCol)); break;
            case '/': tokens.push_back(Token(TokenType::Slash, "/", startLine, startCol)); break;
            case '%': tokens.push_back(Token(TokenType::Percent, "%", startLine, startCol)); break;
            case '=': tokens.push_back(Token(TokenType::Assign, "=", startLine, startCol)); break;
            case '!': tokens.push_back(Token(TokenType::Not, "!", startLine, startCol)); break;
            case '<': tokens.push_back(Token(TokenType::Less, "<", startLine, startCol)); break;
            case '>': tokens.push_back(Token(TokenType::Greater, ">", startLine, startCol)); break;
            case '(': tokens.push_back(Token(TokenType::LeftParen, "(", startLine, startCol)); break;
            case ')': tokens.push_back(Token(TokenType::RightParen, ")", startLine, startCol)); break;
            case '{': tokens.push_back(Token(TokenType::LeftBrace, "{", startLine, startCol)); break;
            case '}': tokens.push_back(Token(TokenType::RightBrace, "}", startLine, startCol)); break;
            case '[': tokens.push_back(Token(TokenType::LeftBracket, "[", startLine, startCol)); break;
            case ']': tokens.push_back(Token(TokenType::RightBracket, "]", startLine, startCol)); break;
            case ',': tokens.push_back(Token(TokenType::Comma, ",", startLine, startCol)); break;
            case ':': tokens.push_back(Token(TokenType::Colon, ":", startLine, startCol)); break;
            case '?': tokens.push_back(Token(TokenType::Question, "?", startLine, startCol)); break;
            case '.': tokens.push_back(Token(TokenType::Dot, ".", startLine, startCol)); break;
            default:
                tokens.push_back(Token(TokenType::Unknown, std::string(1, ch), startLine, startCol));
                break;
        }
        
        advance();
    }
    
    tokens.push_back(Token(TokenType::EndOfFile, "", line_, column_));
    return tokens;
}
