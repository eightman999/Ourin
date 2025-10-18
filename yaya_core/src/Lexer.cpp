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
    // Line comment -- (YAYA/Lua-style)
    if (current() == '-' && peek() == '-') {
        while (current() != '\0' && current() != '\n') {
            advance();
        }
        return;
    }
    // Line comment starting with '#'
    if (current() == '#') {
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
    else if (value == "elseif") type = TokenType::ElseIf;
    else if (value == "while") type = TokenType::While;
    else if (value == "foreach") type = TokenType::Foreach;
    else if (value == "for") type = TokenType::For;
    
    return Token(type, value, startLine, startCol);
}

std::vector<Token> Lexer::tokenize() {
    std::vector<Token> tokens;
    // Skip UTF-8 BOM if present
    if (pos_ == 0 && source_.size() >= 3 &&
        static_cast<unsigned char>(source_[0]) == 0xEF &&
        static_cast<unsigned char>(source_[1]) == 0xBB &&
        static_cast<unsigned char>(source_[2]) == 0xBF) {
        pos_ = 3;
        column_ = 4; // 1-based column; advanced by 3
    }

    while (current() != '\0') {
        skipWhitespace();
        
        // Skip comments
        if ((current() == '/' && (peek() == '/' || peek() == '*')) ||
            (current() == '-' && peek() == '-') ||
            (current() == '#')) {
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
        
        // Here-doc block starting with <<' or <<"
        if (ch == '<' && peek() == '<' && (peek(2) == '\'' || peek(2) == '"')) {
            char q = peek(2);
            // consume <<q
            advance(); advance(); advance();
            // consume optional end of line (CR/LF)
            if (current() == '\r') advance();
            if (current() == '\n') advance();
            tokens.push_back(readHereDoc(q));
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
        if (ch == '+' && peek() == '+') {
            tokens.push_back(Token(TokenType::PlusPlus, "++", startLine, startCol));
            advance(); advance();
            continue;
        }
        if (ch == '-' && peek() == '-') {
            tokens.push_back(Token(TokenType::MinusMinus, "--", startLine, startCol));
            advance(); advance();
            continue;
        }
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
        // Compound assignments
        if (ch == '+' && peek() == '=') {
            tokens.push_back(Token(TokenType::PlusAssign, "+=", startLine, startCol));
            advance(); advance();
            continue;
        }
        if (ch == '-' && peek() == '=') {
            tokens.push_back(Token(TokenType::MinusAssign, "-=", startLine, startCol));
            advance(); advance();
            continue;
        }
        if (ch == '*' && peek() == '=') {
            tokens.push_back(Token(TokenType::StarAssign, "*=", startLine, startCol));
            advance(); advance();
            continue;
        }
        if (ch == '/' && peek() == '=') {
            tokens.push_back(Token(TokenType::SlashAssign, "/=", startLine, startCol));
            advance(); advance();
            continue;
        }
        if (ch == '%' && peek() == '=') {
            tokens.push_back(Token(TokenType::PercentAssign, "%=", startLine, startCol));
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
            case ';': tokens.push_back(Token(TokenType::Semicolon, ";", startLine, startCol)); break;
            case '&': tokens.push_back(Token(TokenType::Ampersand, "&", startLine, startCol)); break;
            default:
                tokens.push_back(Token(TokenType::Unknown, std::string(1, ch), startLine, startCol));
                break;
        }
        
        advance();
    }
    
    tokens.push_back(Token(TokenType::EndOfFile, "", line_, column_));
    return tokens;
}

Token Lexer::readHereDoc(char quote) {
    int startLine = line_;
    int startCol = column_;
    std::string value;

    // Read until a line that begins (ignoring spaces/tabs) with quote + ">>"
    bool atLineStart = true;
    while (current() != '\0') {
        // Check for terminator only at the start of a line
        if (atLineStart) {
            // Skip spaces/tabs at the start of the line
            size_t k = pos_;
            while (k < source_.size() && (source_[k] == ' ' || source_[k] == '\t')) {
                k++;
            }
            if (k + 2 < source_.size() && source_[k] == quote && source_[k+1] == '>' && source_[k+2] == '>') {
                // Advance past the terminator
                pos_ = k + 3;
                column_ += static_cast<int>((k + 3) - pos_); // column_ will be corrected below on newline
                // Consume optional CR/LF after terminator
                if (current() == '\r') advance();
                if (current() == '\n') advance();
                break;
            }
        }

        char c = current();
        value += c;
        advance();

        if (c == '\n') {
            atLineStart = true;
        } else if (c == '\r') {
            // CR may be followed by LF
            atLineStart = true;
        } else {
            atLineStart = false;
        }
    }

    return Token(TokenType::String, value, startLine, startCol);
}
