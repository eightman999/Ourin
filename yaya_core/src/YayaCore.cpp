#include "YayaCore.hpp"
#include <iostream>
#include <chrono>
#include <unordered_set>

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
        if (cmd == "load_messages") {
            std::string messagePath = req.value("message_path", "");

            if (!messagePath.empty()) {
                bool ok = messageManager.load(messagePath);
                response["ok"] = ok;
                response["status"] = ok ? 200 : 500;
                if (!ok) {
                    response["error"] = "failed to load message file";
                }
            } else {
                response["ok"] = false;
                response["status"] = 400;
                response["error"] = "message_path required";
            }
        } else if (cmd == "load") {
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

            // Include list of successfully loaded dic files
            if (ok) {
                const auto& loadedFiles = dictManager.getLoadedDicFiles();
                response["loaded_dics"] = loadedFiles;
            }
        } else if (cmd == "request") {
            std::string id = req.value("id", "");
            auto refs = req.value("ref", std::vector<std::string>{});
            std::string method = req.value("method", "GET");

            // UKADOC Notify-only events whose return value must be ignored by host
            static const std::unordered_set<std::string> notifyReturnIgnored = {
                "basewareversion","hwnd","uniqueid","capability",
                "ownerghostname","otherghostname",
                "installedsakuraname","installedkeroname","installedghostname",
                "installedshellname","installedballoonname","installedheadlinename",
                "installedplugin","configuredbiffname",
                "ghostpathlist","balloonpathlist","headlinepathlist","pluginpathlist",
                "calendarskinpathlist","calendarpluginpathlist",
                "rateofusegraph","enable_log","enable_debug",
                "OnNotifySelfInfo","OnNotifyBalloonInfo","OnNotifyShellInfo",
                "OnNotifyDressupInfo","OnNotifyUserInfo","OnNotifyOSInfo",
                "OnNotifyFontInfo","OnNotifyInternationalInfo"
            };

            std::cerr << "[YayaCore] Executing request: method=" << method << ", id=" << id << ", refs=" << refs.size() << std::endl;
            auto exec_start = std::chrono::steady_clock::now();

            std::string value = dictManager.execute(id, refs);

            auto exec_end = std::chrono::steady_clock::now();
            auto exec_duration = std::chrono::duration_cast<std::chrono::milliseconds>(exec_end - exec_start).count();
            std::cerr << "[YayaCore] Request completed: id=" << id << ", took " << exec_duration << "ms, result length=" << value.length() << std::endl;

            // Debug: Show first 200 chars with backslashes visible
            if (value.length() > 0) {
                std::string preview = value.substr(0, std::min(size_t(200), value.length()));
                std::cerr << "[YayaCore] Result preview (raw): " << preview << std::endl;
                // Count backslashes in result
                size_t backslash_count = 0;
                for (char c : value) {
                    if (c == '\\') backslash_count++;
                }
                std::cerr << "[YayaCore] Backslash count in result: " << backslash_count << std::endl;
            }

            response["ok"] = true;
            response["headers"] = { {"Charset", "UTF-8"} };

            // For NOTIFY-only events, return 204 No Content with no value
            if (!method.empty() && (method == "NOTIFY" || method == "notify") && notifyReturnIgnored.count(id) > 0) {
                response["status"] = 204;
            } else {
                response["status"] = 200;
                response["value"] = value;
            }
        } else if (cmd == "get_loaded_dics") {
            const auto& loadedFiles = dictManager.getLoadedDicFiles();
            response["ok"] = true;
            response["status"] = 200;
            response["loaded_dics"] = loadedFiles;
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
