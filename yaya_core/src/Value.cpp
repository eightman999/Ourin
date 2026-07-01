#include "Value.hpp"
#include "RandomEngine.hpp"
#include <sstream>
#include <stdexcept>
#include <random>

Value::Value() : type_(Type::Void), intValue_(0) {}

Value::Value(const std::string& str) : type_(Type::String), strValue_(str), intValue_(0) {}

Value::Value(int num) : type_(Type::Integer), intValue_(num) {}

Value::Value(double num) : type_(Type::Real), intValue_(0), real_(num) {}

Value::Value(const std::vector<Value>& arr) : type_(Type::Array), arrayValue_(arr), intValue_(0) {}

Value::Value(const std::map<std::string, Value>& dict) : type_(Type::Dictionary), dictValue_(dict), intValue_(0) {}

namespace {
// Format a double trimming trailing zeros: 1.5 -> "1.5", 2.0 -> "2", 3.14 -> "3.14".
std::string formatReal(double v) {
    std::ostringstream oss;
    oss << v;
    std::string s = oss.str();
    // If there's a decimal point, strip trailing zeros (and a trailing '.').
    if (s.find('.') != std::string::npos && s.find('e') == std::string::npos &&
        s.find('E') == std::string::npos) {
        size_t last = s.find_last_not_of('0');
        if (s[last] == '.') last--; // drop the dangling dot too
        s.erase(last + 1);
    }
    return s;
}
} // namespace

std::string Value::asString() const {
    switch (type_) {
        case Type::String:
            return strValue_;
        case Type::Integer:
            return std::to_string(intValue_);
        case Type::Real:
            return formatReal(real_);
        case Type::Void:
            return "";
        case Type::Array:
            // For arrays, randomly select one element
            // This matches YAYA/SHIORI behavior where arrays are script candidates
            if (!arrayValue_.empty()) {
                std::uniform_int_distribution<size_t> dis(0, arrayValue_.size() - 1);
                size_t randomIndex = dis(yaya_rng::engine());
                return arrayValue_[randomIndex].asString();
            }
            return "";
        default:
            return "";
    }
}

int Value::asInt() const {
    switch (type_) {
        case Type::Integer:
            return intValue_;
        case Type::Real:
            return static_cast<int>(real_); // truncate toward zero
        case Type::String:
            try {
                return std::stoi(strValue_);
            } catch (...) {
                return 0;
            }
        default:
            return 0;
    }
}

double Value::asReal() const {
    switch (type_) {
        case Type::Real:
            return real_;
        case Type::Integer:
            return static_cast<double>(intValue_);
        case Type::String:
            try {
                return std::stod(strValue_);
            } catch (...) {
                return 0.0;
            }
        default:
            return 0.0;
    }
}

const std::vector<Value>& Value::asArray() const {
    if (type_ != Type::Array) {
        throw std::runtime_error("Value is not an array");
    }
    return arrayValue_;
}

std::vector<Value>& Value::asArrayMutable() {
    if (type_ != Type::Array) {
        throw std::runtime_error("Value is not an array");
    }
    return arrayValue_;
}

const std::map<std::string, Value>& Value::asDict() const {
    if (type_ != Type::Dictionary) {
        throw std::runtime_error("Value is not a dictionary");
    }
    return dictValue_;
}

bool Value::toBool() const {
    switch (type_) {
        case Type::Void:
            return false;
        case Type::Integer:
            return intValue_ != 0;
        case Type::Real:
            return real_ != 0.0;
        case Type::String:
            return !strValue_.empty();
        case Type::Array:
            return !arrayValue_.empty();
        case Type::Dictionary:
            return !dictValue_.empty();
        default:
            return false;
    }
}

Value Value::operator+(const Value& other) const {
    // String concatenation takes precedence
    if (type_ == Type::String || other.type_ == Type::String) {
        return Value(asString() + other.asString());
    }
    // Numeric promotion: if either operand is Real, result is Real
    if (type_ == Type::Real || other.type_ == Type::Real) {
        return Value(asReal() + other.asReal());
    }
    // Integer addition
    if (type_ == Type::Integer && other.type_ == Type::Integer) {
        return Value(intValue_ + other.intValue_);
    }
    return Value();
}

Value Value::operator-(const Value& other) const {
    if (type_ == Type::Real || other.type_ == Type::Real) {
        return Value(asReal() - other.asReal());
    }
    return Value(asInt() - other.asInt());
}

Value Value::operator*(const Value& other) const {
    if (type_ == Type::Real || other.type_ == Type::Real) {
        return Value(asReal() * other.asReal());
    }
    return Value(asInt() * other.asInt());
}

Value Value::operator/(const Value& other) const {
    // Real division if either operand is Real
    if (type_ == Type::Real || other.type_ == Type::Real) {
        double divisor = other.asReal();
        if (divisor == 0.0) return Value(0.0);
        return Value(asReal() / divisor);
    }
    int divisor = other.asInt();
    if (divisor == 0) return Value(0);
    return Value(asInt() / divisor);
}

Value Value::operator%(const Value& other) const {
    int divisor = other.asInt();
    if (divisor == 0) return Value(0);
    return Value(asInt() % divisor);
}

bool Value::operator==(const Value& other) const {
    // Numeric comparison across Int/Real
    bool thisNum = (type_ == Type::Integer || type_ == Type::Real);
    bool otherNum = (other.type_ == Type::Integer || other.type_ == Type::Real);
    if (thisNum && otherNum) {
        if (type_ == Type::Real || other.type_ == Type::Real) {
            return asReal() == other.asReal();
        }
        return intValue_ == other.intValue_;
    }
    if (type_ != other.type_) {
        // Allow comparison between string and int
        return asString() == other.asString();
    }
    switch (type_) {
        case Type::String:
            return strValue_ == other.strValue_;
        case Type::Integer:
            return intValue_ == other.intValue_;
        case Type::Void:
            return true;
        default:
            return false;
    }
}

bool Value::operator!=(const Value& other) const {
    return !(*this == other);
}

bool Value::operator<(const Value& other) const {
    // Numeric comparison across Int/Real
    bool thisNum = (type_ == Type::Integer || type_ == Type::Real);
    bool otherNum = (other.type_ == Type::Integer || other.type_ == Type::Real);
    if (thisNum && otherNum) {
        if (type_ == Type::Real || other.type_ == Type::Real) {
            return asReal() < other.asReal();
        }
        return intValue_ < other.intValue_;
    }
    return asString() < other.asString();
}

bool Value::operator>(const Value& other) const {
    return other < *this;
}

bool Value::operator<=(const Value& other) const {
    return !(*this > other);
}

bool Value::operator>=(const Value& other) const {
    return !(*this < other);
}

// Array operations
size_t Value::arraySize() const {
    if (type_ == Type::Array) {
        return arrayValue_.size();
    }
    return 0;
}

Value Value::arrayGet(size_t index) const {
    if (type_ == Type::Array && index < arrayValue_.size()) {
        return arrayValue_[index];
    }
    return Value();
}

void Value::arraySet(size_t index, const Value& value) {
    if (type_ == Type::Array) {
        if (index >= arrayValue_.size()) {
            arrayValue_.resize(index + 1);
        }
        arrayValue_[index] = value;
    }
}

void Value::arrayPush(const Value& value) {
    if (type_ == Type::Array) {
        arrayValue_.push_back(value);
    }
}

void Value::arrayConcat(const Value& other) {
    if (type_ == Type::Array) {
        if (other.type_ == Type::Array) {
            // Concatenate arrays
            const auto& otherArray = other.asArray();
            arrayValue_.insert(arrayValue_.end(), otherArray.begin(), otherArray.end());
        } else {
            // Add single element
            arrayValue_.push_back(other);
        }
    }
}
