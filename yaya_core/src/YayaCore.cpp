#include "YayaCore.hpp"
#include <iostream>

using json = nlohmann::json;

YayaCore::YayaCore() = default;

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
