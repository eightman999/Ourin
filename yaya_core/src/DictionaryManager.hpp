#pragma once

#include <string>
#include <vector>
#include <memory>
#include "VM.hpp"

class DictionaryManager {
public:
    DictionaryManager();
    
    // Set VM callback for host operations
    void setCallback(VMCallback* callback);

    /// Structured dic entry: (relative path, optional per-file encoding hint).
    /// Empty encoding => inherit the default encoding passed to load().
    struct DicEntry {
        std::string path;
        std::string encoding;  // may be empty
    };

    // Load with a single global encoding (legacy/compat).
    bool load(const std::vector<std::string>& dicPaths,
              const std::string& encoding);
    // Load with per-file encoding metadata. Entries with empty encoding fall back to defaultEncoding.
    bool load(const std::vector<DicEntry>& dicEntries,
              const std::string& defaultEncoding);
    void unload();
    std::string execute(const std::string& functionName,
                        const std::vector<std::string>& args);

    // Check if a function exists in the loaded dictionaries
    bool hasFunction(const std::string& functionName) const;

    // Get list of loaded dictionary files
    const std::vector<std::string>& getLoadedDicFiles() const { return loadedDicFiles_; }

    // --- Dynamic dictionary operations (Phase 6) ---
    // Load a single dictionary file at runtime (DICLOAD). Resolves under ghostRoot.
    bool dicLoad(const std::string& relativePath, const std::string& encoding);
    // Unload a previously loaded dictionary file by relative/basename (DICUNLOAD).
    bool dicUnload(const std::string& relativePath);
    // Append runtime code as a synthetic dictionary (APPEND_RUNTIME_DIC).
    bool appendRuntimeDic(const std::string& code);
    // Set the base directory used to anchor relative paths.
    void setGhostRoot(const std::string& root);

private:
    std::unique_ptr<VM> vm_;
    VMCallback* storedCallback_ = nullptr;  // preserved across VM resets
    std::vector<std::string> loadedDicFiles_;  // Paths of successfully loaded dic files
    std::string ghostRoot_;
    std::string loadFile(const std::string& path);
    std::string decodeContent(const std::string& raw,
                              const std::string& encoding,
                              const std::string& filename);
    bool parseDictionary(const std::string& content, const std::string& sourceName);
};
