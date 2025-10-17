#include "DictionaryManager.hpp"
#include "Lexer.hpp"
#include "Parser.hpp"
#include "Value.hpp"
#include <fstream>
#include <sstream>
#include <iostream>

DictionaryManager::DictionaryManager() {
    vm_ = std::make_unique<VM>();
}

std::string DictionaryManager::loadFile(const std::string& path) {
    std::ifstream file(path);
    if (!file.is_open()) {
        std::cerr << "[DictionaryManager] Failed to open file: " << path << std::endl;
        return "";
    }
    
    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

bool DictionaryManager::parseDictionary(const std::string& content) {
    try {
        // Tokenize
        Lexer lexer(content);
        auto tokens = lexer.tokenize();
        
        // Parse
        Parser parser(tokens);
        auto functions = parser.parse();
        
        // Register functions in VM
        for (const auto& func : functions) {
            vm_->registerFunction(func->name, func);
        }
        
        return true;
    } catch (const std::exception& e) {
        std::cerr << "[DictionaryManager] Parse error: " << e.what() << std::endl;
        return false;
    }
}

bool DictionaryManager::load(const std::vector<std::string>& dicPaths,
                             const std::string& encoding) {
    (void)encoding; // TODO: Handle encoding conversion (UTF-8/CP932)
    
    // Reset VM
    vm_ = std::make_unique<VM>();
    
    // Load and parse each dictionary file
    for (const auto& path : dicPaths) {
        std::string content = loadFile(path);
        if (content.empty()) {
            std::cerr << "[DictionaryManager] Failed to load: " << path << std::endl;
            continue;
        }
        
        if (!parseDictionary(content)) {
            std::cerr << "[DictionaryManager] Failed to parse: " << path << std::endl;
            // Continue loading other files even if one fails
        }
    }
    
    return true;
}

void DictionaryManager::unload() {
    vm_.reset();
}

std::string DictionaryManager::execute(const std::string& functionName,
                                       const std::vector<std::string>& args) {
    if (!vm_) return "";
    
    // Set SHIORI references
    vm_->setReferences(args);
    
    // Execute the function
    Value result = vm_->execute(functionName, {});
    
    // Return the result as a string
    return result.asString();
}
