#include "YayaCore.hpp"
#include <iostream>

using json = nlohmann::json;

YayaCore::YayaCore() {
    // Set this instance as the callback for VM operations
    dictManager.setCallback(this);
}

// Request operation from host (Swift) via stdout/stdin
std::string YayaCore::requestHostOperation(const std::string& type, const json& params) {
    json request;
    request["host_op"] = type;
    request["params"] = params;
    
    // Send request to stdout for host to intercept
    std::cout << request.dump() << std::endl;
    std::cout.flush();
    
    // Read response from stdin
    std::string responseLine;
    if (std::getline(std::cin, responseLine)) {
        try {
            auto response = json::parse(responseLine);
            return response.dump();
        } catch (...) {
            return "{}";
        }
    }
    return "{}";
}

json YayaCore::fileOperation(const std::string& op, const json& params) {
    json req;
    req["operation"] = op;
    req["params"] = params;
    
    std::string response = requestHostOperation("file", req);
    try {
        return json::parse(response);
    } catch (...) {
        return json{{"error", "failed to parse response"}};
    }
}

json YayaCore::executeCommand(const std::string& command, bool wait) {
    json req;
    req["command"] = command;
    req["wait"] = wait;
    
    std::string response = requestHostOperation("execute", req);
    try {
        return json::parse(response);
    } catch (...) {
        return json{{"error", "failed to parse response"}};
    }
}

json YayaCore::pluginOperation(const std::string& op, const json& params) {
    json req;
    req["operation"] = op;
    req["params"] = params;
    
    std::string response = requestHostOperation("plugin", req);
    try {
        return json::parse(response);
    } catch (...) {
        return json{{"error", "failed to parse response"}};
    }
}

std::string YayaCore::processCommand(const std::string &line) {
    json response;
    try {
        auto req = json::parse(line);
        std::string cmd = req.value("cmd", "");
        if (cmd == "load") {
            std::string ghostRoot = req.value("ghost_root", "");
            std::vector<std::string> dicNames = req.value("dic", std::vector<std::string>{});
            std::string encoding = req.value("encoding", "UTF-8");
            
            // Build full paths from ghost_root and dic names
            std::vector<std::string> dicPaths;
            for (const auto& name : dicNames) {
                std::string fullPath = ghostRoot + "/" + name;
                dicPaths.push_back(fullPath);
            }
            
            bool ok = dictManager.load(dicPaths, encoding);
            response["ok"] = ok;
            response["status"] = ok ? 200 : 500;
        } else if (cmd == "request") {
            std::string id = req.value("id", "");
            auto refs = req.value("ref", std::vector<std::string>{});
            std::string value = dictManager.execute(id, refs);
            response["ok"] = true;
            response["status"] = 200;
            response["headers"] = { {"Charset", "UTF-8"} };
            response["value"] = value;
        } else if (cmd == "unload") {
            dictManager.unload();
            response["ok"] = true;
            response["status"] = 200;
        } else {
            response["ok"] = false;
            response["status"] = 400;
            response["error"] = "unknown command";
        }
    } catch (const std::exception &e) {
        response["ok"] = false;
        response["status"] = 500;
        response["error"] = e.what();
    }
    return response.dump();
}
