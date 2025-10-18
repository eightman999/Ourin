#pragma once

#include <string>
#include <nlohmann/json.hpp>
#include "DictionaryManager.hpp"
#include "VM.hpp"

class YayaCore : public VMCallback {
public:
    YayaCore();
    std::string processCommand(const std::string &line);
    
    // VMCallback interface
    nlohmann::json fileOperation(const std::string& op, const nlohmann::json& params) override;
    nlohmann::json executeCommand(const std::string& command, bool wait) override;
    nlohmann::json pluginOperation(const std::string& op, const nlohmann::json& params) override;
    
private:
    DictionaryManager dictManager;
    std::string requestHostOperation(const std::string& type, const nlohmann::json& params);
};
