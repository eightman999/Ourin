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
    static const std::unordered_set<std::string> supportedOps = {
        "saori_load",
        "saori_unload",
        "saori_request"
    };
    if (supportedOps.find(op) == supportedOps.end()) {
        return json{
            {"ok", false},
            {"error", "unsupported plugin operation: " + op}
        };
    }

    return handlePluginOperation(op, params);
}

json YayaCore::handlePluginOperation(const std::string& op, const json& params) {
    json req;
    req["operation"] = op;
    req["params"] = params;

    std::string response = requestHostOperation("plugin", req);
    try {
        auto parsed = json::parse(response);
        // Allow either a direct plugin response, or a wrapped host_op response.
        if (parsed.contains("host_op") && parsed.value("host_op", "") == "plugin" &&
            parsed.contains("params") && parsed["params"].is_object()) {
            parsed = parsed["params"];
        }
        if (!parsed.contains("ok")) {
            return json{
                {"ok", false},
                {"error", "invalid plugin response: missing ok"}
            };
        }
        return parsed;
    } catch (const std::exception& e) {
        return json{
            {"ok", false},
            {"error", std::string("failed to parse response: ") + e.what()}
        };
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

                // Call YAYA framework's `load` function if it exists (sets SHIORI3FW.Path etc.)
                if (dictManager.hasFunction("load")) {
                    std::string ghostPath = ghostRoot;
                    if (!ghostPath.empty() && ghostPath.back() != '/') {
                        ghostPath += '/';
                    }
                    std::cerr << "[YayaCore] Calling YAYA framework load() with path: " << ghostPath << std::endl;
                    dictManager.execute("load", {ghostPath});
                }
            }
        } else if (cmd == "request") {
            std::string id = req.value("id", "");
            auto refs = req.value("ref", std::vector<std::string>{});
            std::string method = req.value("method", "GET");
            auto headers = req.value("headers", std::map<std::string, std::string>{});

            std::cerr << "[YayaCore] Executing request: method=" << method << ", id=" << id << ", refs=" << refs.size() << std::endl;
            auto exec_start = std::chrono::steady_clock::now();

            // Build raw SHIORI protocol request to pass through YAYA framework's `request` function.
            // The framework parses this text to set SHIORI3FW.* variables and dispatch to SHIORI3EV.* handlers.
            std::string shioriReq = method + " SHIORI/3.0\r\n";
            shioriReq += "Charset: UTF-8\r\n";
            shioriReq += "Sender: Ourin\r\n";
            shioriReq += "SecurityLevel: local\r\n";
            shioriReq += "ID: " + id + "\r\n";
            for (auto& kv : headers) {
                if (kv.first != "Charset" && kv.first != "ID") {
                    shioriReq += kv.first + ": " + kv.second + "\r\n";
                }
            }
            for (size_t i = 0; i < refs.size(); i++) {
                shioriReq += "Reference" + std::to_string(i) + ": " + refs[i] + "\r\n";
            }
            shioriReq += "\r\n";

            std::string value;
            // Try YAYA framework's `request` function first (handles event dispatch, SHIORI3FW.* setup)
            bool usedFramework = false;
            if (dictManager.hasFunction("request")) {
                value = dictManager.execute("request", {shioriReq});
                usedFramework = true;
                // The YAYA framework returns a full SHIORI protocol response.
                // For GET: "SHIORI/3.0 200 OK\r\nValue: <script>\r\n...\r\n"
                // For NOTIFY: "SHIORI/3.0 204 No Content\r\n...\r\n"
                // Extract the Value: header content as the script.
                std::string extracted;
                std::string searchKey = "Value: ";
                auto valPos = value.find(searchKey);
                if (valPos != std::string::npos) {
                    auto valStart = valPos + searchKey.length();
                    auto valEnd = value.find("\r\n", valStart);
                    if (valEnd != std::string::npos) {
                        extracted = value.substr(valStart, valEnd - valStart);
                    } else {
                        extracted = value.substr(valStart);
                    }
                }
                value = extracted;
                std::cerr << "[YayaCore] Used YAYA framework request() dispatcher" << std::endl;
            } else {
                // Fallback: call function directly (for simple ghosts without YAYA framework)
                value = dictManager.execute(id, refs);
                std::cerr << "[YayaCore] Direct function call (no YAYA framework)" << std::endl;
            }

            auto exec_end = std::chrono::steady_clock::now();
            auto exec_duration = std::chrono::duration_cast<std::chrono::milliseconds>(exec_end - exec_start).count();
            std::cerr << "[YayaCore] Request completed: id=" << id << ", took " << exec_duration << "ms, result length=" << value.length() << std::endl;

            if (value.length() > 0) {
                std::string preview = value.substr(0, std::min(size_t(200), value.length()));
                std::cerr << "[YayaCore] Result preview (raw): " << preview << std::endl;
            }

            response["ok"] = true;
            response["headers"] = { {"Charset", "UTF-8"} };

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
            // Call YAYA framework's `unload` function before teardown
            if (dictManager.hasFunction("unload")) {
                std::cerr << "[YayaCore] Calling YAYA framework unload()" << std::endl;
                dictManager.execute("unload", {});
            }
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
