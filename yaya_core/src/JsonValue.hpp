#pragma once

#include "Value.hpp"
#include <nlohmann/json.hpp>
#include <cmath>
#include <limits>
#include <stdexcept>

// YAYA JSON values: objects => hash, boolean => integer, null => VOID.
// Keep int64 values exact instead of passing them through double.
namespace YayaJson {
inline Value decode(const nlohmann::json& data, unsigned depth = 0) {
    if (depth > 128) throw std::runtime_error("JSON nesting limit");
    if (data.is_null()) return Value();
    if (data.is_boolean()) return Value(data.get<bool>() ? 1 : 0);
    if (data.is_string()) return Value(data.get<std::string>());
    if (data.is_number_unsigned()) {
        const auto n = data.get<std::uint64_t>();
        if (n <= static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max()))
            return Value(static_cast<std::int64_t>(n));
        return Value(static_cast<double>(n));
    }
    if (data.is_number_integer()) return Value(data.get<std::int64_t>());
    if (data.is_number_float()) {
        const double n = data.get<double>();
        if (std::floor(n) == n && n >= -9223372036854775808.0 && n < 9223372036854775808.0)
            return Value(static_cast<std::int64_t>(n));
        return Value(n);
    }
    if (data.is_array()) {
        std::vector<Value> values;
        for (const auto& v : data) values.push_back(decode(v, depth + 1));
        return Value(values);
    }
    std::map<std::string, Value> values;
    for (auto it = data.begin(); it != data.end(); ++it) values.emplace(it.key(), decode(it.value(), depth + 1));
    return Value(values);
}

inline nlohmann::json encode(const Value& value, unsigned depth = 0) {
    if (depth > 128) throw std::runtime_error("JSON nesting limit");
    switch (value.getType()) {
        case Value::Type::Void: return nullptr;
        case Value::Type::String: return value.asString();
        case Value::Type::Integer: return value.asInt64();
        case Value::Type::Real:
            if (!std::isfinite(value.asReal())) return nullptr;
            return value.asReal();
        case Value::Type::Array: {
            auto result = nlohmann::json::array();
            for (const auto& v : value.asArray()) result.push_back(encode(v, depth + 1));
            return result;
        }
        case Value::Type::Dictionary: {
            auto result = nlohmann::json::object();
            for (const auto& [k, v] : value.asDict()) result[k] = encode(v, depth + 1);
            return result;
        }
    }
    throw std::runtime_error("unsupported JSON value");
}

inline Value parse(const std::string& text) {
    auto limit = [](int depth, nlohmann::json::parse_event_t, nlohmann::json&) {
        if (depth > 128) throw std::runtime_error("JSON nesting limit");
        return true;
    };
    return decode(nlohmann::json::parse(text, limit, true, true)); // UTF-8 BOM and comments
}
} // namespace YayaJson
