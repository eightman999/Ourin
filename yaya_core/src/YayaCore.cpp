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
            std::vector<std::string> dics = req.value("dics", std::vector<std::string>{});
            std::string encoding = req.value("encoding", "UTF-8");
            bool ok = dictManager.load(dics, encoding);
            response["ok"] = ok;
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
        } else {
            response["ok"] = false;
            response["error"] = "unknown command";
        }
    } catch (const std::exception &e) {
        response["ok"] = false;
        response["error"] = e.what();
    }
    return response.dump();
}
