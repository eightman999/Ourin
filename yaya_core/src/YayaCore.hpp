#pragma once

#include <string>
#include <nlohmann/json.hpp>
#include "DictionaryManager.hpp"
#include "MessageManager.hpp"
#include "VM.hpp"

class YayaCore : public VMCallback {
public:
    YayaCore();
    std::string processCommand(const std::string &line);
    
    // VMCallback interface
    nlohmann::json fileOperation(const std::string& op, const nlohmann::json& params) override;
    nlohmann::json executeCommand(const std::string& command, bool wait) override;
    nlohmann::json executeCommandWithArguments(const std::string& command, bool wait, const std::string& arguments) override;
    bool requiresHostExecution() const override { return hostExecution_; }
    nlohmann::json pluginOperation(const std::string& op, const nlohmann::json& params) override;
    nlohmann::json fmoOperation(const std::string& op, const nlohmann::json& params) override;

    // Dynamic dictionary operations (Phase 6)
    bool dicLoad(const std::string& relativePath, const std::string& encoding) override;
    bool dicUnload(const std::string& relativePath) override;
    
private:
    bool hostExecution_ = false;
    DictionaryManager dictManager;
    MessageManager messageManager;
    std::string requestHostOperation(const std::string& type, const nlohmann::json& params);
    nlohmann::json handlePluginOperation(const std::string& op, const nlohmann::json& params);
};
