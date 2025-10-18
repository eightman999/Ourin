#pragma once

#include <string>
#include <vector>

enum class TokenType {
    // Literals
    Identifier,
    String,
    Integer,
    
    // Operators
    Plus,
    Minus,
    Star,
    Slash,
    Percent,
    PlusPlus,     // ++
    MinusMinus,   // --
    
    // Comparison
    Equal,
    NotEqual,
    Less,
    Greater,
    LessEqual,
    GreaterEqual,
    
    // Assignment
    Assign,
    CommaAssign,  // ,= for array concatenation
    PlusAssign,   // +=
    MinusAssign,  // -=
    StarAssign,   // *=
    SlashAssign,  // /=
    PercentAssign,// %=
    
    // Logical
    And,
    Or,
    Not,
    In,           // _in_ operator for substring/array contains check
    
    // Delimiters
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    LeftBracket,
    RightBracket,
    Comma,
    Colon,
    Question,
    Dot,
    Semicolon,
    Ampersand,
    
    // Keywords
    If,
    Else,
    ElseIf,
    While,
    Foreach,
    For,
    Switch,
    Case,
    When,
    Default,
    Break,
    Continue,
    Return,
    
    // Special
    Newline,
    EndOfFile,
    Unknown
};

struct Token {
    TokenType type;
    std::string value;
    int line;
    int column;
    
    Token(TokenType t, const std::string& v = "", int l = 0, int c = 0)
        : type(t), value(v), line(l), column(c) {}
};

class Lexer {
public:
    explicit Lexer(const std::string& source);
    std::vector<Token> tokenize();
    
private:
    std::string source_;
    size_t pos_;
    int line_;
    int column_;
    
    char current() const;
    char peek(int offset = 1) const;
    void advance();
    void skipWhitespace();
    void skipComment();
    
    Token readString();
    Token readHereDoc(char quote);
    Token readNumber();
    Token readIdentifier();
};
