#pragma once
#include <string>
#include <map>
#include <vector>

/// Manages error/warning/note messages from messagetxt files
class MessageManager {
public:
    MessageManager() = default;

    /// Load messages from a messagetxt file
    /// @param path Path to the messagetxt file (e.g., "japanese.txt")
    /// @return true if loaded successfully
    bool load(const std::string& path);

    /// Get a message by type and code
    /// @param type Message type: "error", "warning", "note", "log"
    /// @param code Message code (e.g., "E0001", "W0005")
    /// @return The message string, or empty if not found
    std::string getMessage(const std::string& type, const std::string& code) const;

    /// Clear all loaded messages
    void clear();

private:
    /// Parse messagetxt file content
    bool parseMessageTxt(const std::string& content);

    /// Message storage: type -> (code -> message)
    /// e.g., messages_["error"]["E0001"] = "対応する関数名が見つかりません."
    std::map<std::string, std::map<std::string, std::string>> messages_;
};
