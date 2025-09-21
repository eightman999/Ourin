#include "DictionaryManager.hpp"

bool DictionaryManager::load(const std::vector<std::string>& dicPaths,
                             const std::string& encoding) {
    (void)dicPaths;
    (void)encoding;
    return true;
}

void DictionaryManager::unload() {
}

std::string DictionaryManager::execute(const std::string& functionName,
                                       const std::vector<std::string>& args) {
    (void)functionName;
    (void)args;
    return "";
}
