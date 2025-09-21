#pragma once

#include <string>
#include <vector>

class DictionaryManager {
public:
    bool load(const std::vector<std::string>& dicPaths,
              const std::string& encoding);
    void unload();
    std::string execute(const std::string& functionName,
                        const std::vector<std::string>& args);
};
