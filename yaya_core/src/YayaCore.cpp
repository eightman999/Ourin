#include "YayaCore.hpp"
#include <iostream>
#include <chrono>
#include <unordered_set>
#include <set>
#include <algorithm>
#include <cctype>

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

bool YayaCore::dicLoad(const std::string& relativePath, const std::string& encoding) {
    return dictManager.dicLoad(relativePath, encoding);
}

bool YayaCore::dicUnload(const std::string& relativePath) {
    return dictManager.dicUnload(relativePath);
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
            std::string encoding = req.value("encoding", "auto");

            // Anchor relative paths (DICLOAD / SAVEVAR / DICUNLOAD) under the ghost root.
            dictManager.setGhostRoot(ghostRoot);

            // Build structured entries. Prefer "dic_entries" (per-dic encoding) over flat "dic".
            std::vector<DictionaryManager::DicEntry> dicEntries;
            bool usedStructured = false;
            if (req.contains("dic_entries") && req["dic_entries"].is_array()) {
                usedStructured = true;
                for (const auto& item : req["dic_entries"]) {
                    // Null-safe string access: a missing OR null field yields the default.
                    auto strOr = [&](const char* key, const char* def) -> std::string {
                        if (!item.contains(key) || item[key].is_null()) return def;
                        return item[key].is_string() ? item[key].get<std::string>() : def;
                    };
                    DictionaryManager::DicEntry e;
                    e.path = strOr("path", "");
                    e.encoding = strOr("encoding", "");
                    if (!e.path.empty()) {
                        std::string fullPath = ghostRoot + "/" + e.path;
                        dicEntries.push_back({fullPath, e.encoding});
                    }
                }
            }
            if (!usedStructured) {
                std::vector<std::string> dicNames = req.value("dic", std::vector<std::string>{});
                for (const auto& name : dicNames) {
                    std::string fullPath = ghostRoot + "/" + name;
                    dicEntries.push_back({fullPath, ""});
                }
            }

            bool ok = dicEntries.empty()
                ? dictManager.load(std::vector<std::string>{}, encoding)
                : dictManager.load(dicEntries, encoding);
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
            // Phase 9: include UKADOC headers. Deduplication is case-insensitive and the
            // `ref` array is overlaid on top of any Reference* present in `headers`.
            std::string shioriReq = method + " SHIORI/3.0\r\n";
            auto lower = [](std::string s) {
                std::transform(s.begin(), s.end(), s.begin(),
                               [](unsigned char c) { return std::tolower(c); });
                return s;
            };
            // Case-insensitive lookup of a header value in the caller map.
            auto findCI = [&](const std::string& key) -> const std::string* {
                for (const auto& kv : headers) {
                    if (lower(kv.first) == lower(key)) return &kv.second;
                }
                return nullptr;
            };
            auto emitCI = [&](const std::string& key, const std::string& val) {
                shioriReq += key + ": " + val + "\r\n";
            };
            auto emitDefault = [&](const std::string& key, const std::string& val) {
                if (!findCI(key)) emitCI(key, val);
            };
            emitDefault("Charset", "UTF-8");
            emitDefault("Sender", "Ourin");
            emitDefault("SenderType", "Plugin");
            emitDefault("SecurityLevel", "local");
            // ID: prefer caller-supplied value, else the `id` argument.
            if (const std::string* idHdr = findCI("ID")) emitCI("ID", *idHdr);
            else emitCI("ID", id);

            // Emit every caller header once (except ID, already emitted above),
            // case-insensitively deduplicated. This includes Status, BaseID,
            // SecurityOrigin, X-SSTP-PassThru-*, and Reference* from headers.
            std::set<std::string> emittedLower;
            emittedLower.insert("id");
            for (const auto& kv : headers) {
                std::string kl = lower(kv.first);
                if (emittedLower.count(kl)) continue;
                emittedLower.insert(kl);
                emitCI(kv.first, kv.second);
            }
            // Overlay the `ref` array: it overrides Reference* from headers and
            // extends to higher indices.
            for (size_t i = 0; i < refs.size(); i++) {
                emitCI("Reference" + std::to_string(i), refs[i]);
            }
            shioriReq += "\r\n";

            std::string value;
            // SHIORI 応答の全ヘッダ（Value 以外も Swift 側へ引き渡す: Reference0 / ValueNotify / Status / Balloon 等）
            json shioriHeaders = json::object();
            shioriHeaders["Charset"] = "UTF-8";
            int shioriStatus = 0;

            // Try YAYA framework's `request` function first (handles event dispatch, SHIORI3FW.* setup)
            bool usedFramework = false;
            if (dictManager.hasFunction("request")) {
                std::string raw = dictManager.execute("request", {shioriReq});
                usedFramework = true;
                // The YAYA framework returns a full SHIORI protocol response:
                //   "SHIORI/3.0 200 OK\r\nValue: <script>\r\nReference0: ...\r\n\r\n"
                // ヘッダ単位でパースする（"Value: " の部分文字列検索は本文中の同文字列を誤検出するため行わない）。
                size_t lineStart = 0;
                bool firstLine = true;
                while (lineStart <= raw.size()) {
                    size_t lineEnd = raw.find("\r\n", lineStart);
                    std::string line;
                    if (lineEnd == std::string::npos) {
                        line = raw.substr(lineStart);
                        lineStart = raw.size() + 1;
                    } else {
                        line = raw.substr(lineStart, lineEnd - lineStart);
                        lineStart = lineEnd + 2;
                    }
                    if (line.empty()) break; // 空行 = ヘッダ終端
                    if (firstLine) {
                        firstLine = false;
                        // "SHIORI/3.0 200 OK" からステータスコードを取り出す
                        auto sp1 = line.find(' ');
                        if (sp1 != std::string::npos) {
                            auto sp2 = line.find(' ', sp1 + 1);
                            std::string codeStr = (sp2 == std::string::npos)
                                ? line.substr(sp1 + 1)
                                : line.substr(sp1 + 1, sp2 - sp1 - 1);
                            try { shioriStatus = std::stoi(codeStr); } catch (...) {}
                        }
                        continue;
                    }
                    auto colon = line.find(':');
                    if (colon == std::string::npos) continue;
                    std::string key = line.substr(0, colon);
                    std::string val = line.substr(colon + 1);
                    // 先頭の空白を1つだけ除去（"Key: Value" 形式）
                    if (!val.empty() && val.front() == ' ') val.erase(0, 1);
                    if (key == "Value") {
                        value = val;
                    }
                    shioriHeaders[key] = val;
                }
                std::cerr << "[YayaCore] Used YAYA framework request() dispatcher (status="
                          << shioriStatus << ", headers=" << shioriHeaders.size() << ")" << std::endl;

                // Some framework scripts can currently evaluate to a malformed empty
                // response while the actual event function exists. Recover the script
                // for GET events instead of making the host fall back to a built-in
                // greeting.
                if ((method == "GET" || method == "get") &&
                    shioriStatus == 0 &&
                    value.empty() &&
                    dictManager.hasFunction(id)) {
                    std::cerr << "[YayaCore] Framework returned an empty malformed GET response; "
                              << "falling back to direct event call: " << id << std::endl;
                    value = dictManager.execute(id, refs);
                    if (!value.empty()) {
                        shioriStatus = 200;
                        shioriHeaders["Value"] = value;
                    }
                }
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
            response["headers"] = shioriHeaders;

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
                // フレームワークが返したステータス（200/204/400等）をそのまま伝える
                response["status"] = (usedFramework && shioriStatus > 0) ? shioriStatus : 200;
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
