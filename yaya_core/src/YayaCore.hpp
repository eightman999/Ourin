#pragma once

#include <string>
#include <nlohmann/json.hpp>
#include "DictionaryManager.hpp"

class YayaCore {
public:
    YayaCore();
    std::string processCommand(const std::string &line);
private:
    DictionaryManager dictManager;
};
