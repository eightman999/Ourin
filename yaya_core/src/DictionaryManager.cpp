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

void DictionaryManager::setCallback(VMCallback* callback) {
    if (vm_) {
        vm_->setCallback(callback);
    }
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
        std::cerr << "[DictionaryManager] Tokenizing..." << std::endl;
        // Tokenize
        Lexer lexer(content);
        auto tokens = lexer.tokenize();
        std::cerr << "[DictionaryManager] Got " << tokens.size() << " tokens, parsing AST..." << std::endl;

        // Parse
        Parser parser(tokens);
        std::cerr << "[DictionaryManager] Parser created, calling parse()..." << std::endl;
        auto functions = parser.parse();
        std::cerr << "[DictionaryManager] Parsed " << functions.size() << " functions, registering..." << std::endl;

        // Register functions in VM
        for (const auto& func : functions) {
            vm_->registerFunction(func->name, func);
        }

        std::cerr << "[DictionaryManager] Registration complete" << std::endl;
        return true;
    } catch (const std::exception& e) {
        std::cerr << "[DictionaryManager] Parse error: " << e.what() << std::endl;
        return false;
    }
}

bool DictionaryManager::load(const std::vector<std::string>& dicPaths,
                             const std::string& encoding) {
    (void)encoding; // TODO: Handle encoding conversion (UTF-8/CP932)

    std::cerr << "[DictionaryManager] Starting load of " << dicPaths.size() << " dictionaries" << std::endl;

    // Reset VM
    vm_ = std::make_unique<VM>();

    // Load and parse each dictionary file
    for (size_t i = 0; i < dicPaths.size(); ++i) {
        const auto& path = dicPaths[i];
        std::cerr << "[DictionaryManager] Loading " << (i+1) << "/" << dicPaths.size() << ": " << path << std::endl;

        std::string content = loadFile(path);
        if (content.empty()) {
            std::cerr << "[DictionaryManager] Failed to load: " << path << std::endl;
            continue;
        }

        std::cerr << "[DictionaryManager] Loaded " << content.size() << " bytes, parsing..." << std::endl;

        if (!parseDictionary(content)) {
            std::cerr << "[DictionaryManager] Failed to parse: " << path << std::endl;
            // Continue loading other files even if one fails
        } else {
            std::cerr << "[DictionaryManager] Successfully parsed: " << path << std::endl;
        }
    }

    std::cerr << "[DictionaryManager] Load complete" << std::endl;
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
