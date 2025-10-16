#pragma once

#include <string>
#include <vector>
#include <map>
#include <memory>
#include <variant>

/// Represents a YAYA value (string, integer, array, or dictionary)
class Value {
public:
    enum class Type {
        Void,
        String,
        Integer,
        Array,
        Dictionary
    };

    Value();
    explicit Value(const std::string& str);
    explicit Value(int num);
    explicit Value(const std::vector<Value>& arr);
    explicit Value(const std::map<std::string, Value>& dict);

    Type getType() const { return type_; }
    bool isVoid() const { return type_ == Type::Void; }
    
    // Conversion methods
    std::string asString() const;
    int asInt() const;
    const std::vector<Value>& asArray() const;
    const std::map<std::string, Value>& asDict() const;
    
    // Operators
    bool toBool() const;
    Value operator+(const Value& other) const;
    Value operator-(const Value& other) const;
    Value operator*(const Value& other) const;
    Value operator/(const Value& other) const;
    Value operator%(const Value& other) const;
    
    bool operator==(const Value& other) const;
    bool operator!=(const Value& other) const;
    bool operator<(const Value& other) const;
    bool operator>(const Value& other) const;
    bool operator<=(const Value& other) const;
    bool operator>=(const Value& other) const;

private:
    Type type_;
    std::string strValue_;
    int intValue_;
    std::vector<Value> arrayValue_;
    std::map<std::string, Value> dictValue_;
};
