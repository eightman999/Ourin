#include "MessageManager.hpp"
#include <fstream>
#include <sstream>
#include <iostream>

bool MessageManager::load(const std::string& path) {
    std::ifstream file(path);
    if (!file.is_open()) {
        std::cerr << "[MessageManager] Failed to open message file: " << path << std::endl;
        return false;
    }

    std::stringstream buffer;
    buffer << file.rdbuf();
    std::string content = buffer.str();

    return parseMessageTxt(content);
}

bool MessageManager::parseMessageTxt(const std::string& content) {
    std::istringstream stream(content);
    std::string line;
    std::string currentSection;

    // Map section markers to message types
    std::map<std::string, std::string> sectionToType = {
        {"msgf", "fatal"},
        {"msge", "error"},
        {"msgw", "warning"},
        {"msgn", "note"},
        {"msgj", "log"}
    };

    while (std::getline(stream, line)) {
        // Skip BOM if present at start
        if (line.size() >= 3 &&
            static_cast<unsigned char>(line[0]) == 0xEF &&
            static_cast<unsigned char>(line[1]) == 0xBB &&
            static_cast<unsigned char>(line[2]) == 0xBF) {
            line = line.substr(3);
        }

        // Trim trailing whitespace and \r
        while (!line.empty() && (line.back() == '\r' || line.back() == '\n' || line.back() == ' ' || line.back() == '\t')) {
            line.pop_back();
        }

        // Skip empty lines and comments (lines starting with //)
        if (line.empty() || (line.size() >= 2 && line[0] == '/' && line[1] == '/')) {
            continue;
        }

        // Check for section marker (!!!)
        if (line.size() >= 3 && line.substr(0, 3) == "!!!") {
            std::string sectionName = line.substr(3);
            auto it = sectionToType.find(sectionName);
            if (it != sectionToType.end()) {
                currentSection = it->second;
                std::cerr << "[MessageManager] Entering section: " << currentSection << std::endl;
            }
            continue;
        }

        // Parse message line (starts with *)
        if (!line.empty() && line[0] == '*') {
            if (currentSection.empty()) {
                continue; // No section yet
            }

            std::string messageLine = line.substr(1); // Remove leading *

            // Parse format: "error E0001 : message text"
            // or: "warning W0005 : message text"
            // or: "note N0001 : message text"
            size_t colonPos = messageLine.find(" : ");
            if (colonPos == std::string::npos) {
                // No message text, just skip or store empty
                continue;
            }

            std::string prefix = messageLine.substr(0, colonPos);
            std::string messageText = messageLine.substr(colonPos + 3);

            // Extract code from prefix (e.g., "error E0001" -> "E0001")
            size_t spacePos = prefix.find(' ');
            if (spacePos == std::string::npos) {
                continue; // Invalid format
            }

            std::string typePrefix = prefix.substr(0, spacePos); // e.g., "error", "warning"
            std::string code = prefix.substr(spacePos + 1);      // e.g., "E0001"

            // Trim whitespace from code
            while (!code.empty() && (code.front() == ' ' || code.front() == '\t')) {
                code.erase(0, 1);
            }
            while (!code.empty() && (code.back() == ' ' || code.back() == '\t')) {
                code.pop_back();
            }

            // Store the message
            messages_[currentSection][code] = messageText;
            // std::cerr << "[MessageManager] Loaded " << currentSection << " " << code << ": " << messageText << std::endl;
        }
    }

    std::cerr << "[MessageManager] Loaded messages: ";
    for (const auto& pair : messages_) {
        std::cerr << pair.first << "=" << pair.second.size() << " ";
    }
    std::cerr << std::endl;

    return true;
}

std::string MessageManager::getMessage(const std::string& type, const std::string& code) const {
    auto typeIt = messages_.find(type);
    if (typeIt == messages_.end()) {
        return "";
    }

    auto codeIt = typeIt->second.find(code);
    if (codeIt == typeIt->second.end()) {
        return "";
    }

    return codeIt->second;
}

void MessageManager::clear() {
    messages_.clear();
}
