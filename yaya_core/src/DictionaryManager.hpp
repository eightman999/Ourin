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
    
    bool load(const std::vector<std::string>& dicPaths,
              const std::string& encoding);
    void unload();
    std::string execute(const std::string& functionName,
                        const std::vector<std::string>& args);

    // Get list of loaded dictionary files
    const std::vector<std::string>& getLoadedDicFiles() const { return loadedDicFiles_; }

private:
    std::unique_ptr<VM> vm_;
    std::vector<std::string> loadedDicFiles_;  // Paths of successfully loaded dic files
    std::string loadFile(const std::string& path);
    bool parseDictionary(const std::string& content);
};
