#include "DictionaryManager.hpp"
#include "Lexer.hpp"
#include "Parser.hpp"
#include "Value.hpp"
#include <fstream>
#include <sstream>
#include <iostream>
#include <chrono>

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
        // std::cerr << "[DictionaryManager] Tokenizing..." << std::endl;
        auto start_time = std::chrono::steady_clock::now();

        // Tokenize
        Lexer lexer(content);
        auto tokens = lexer.tokenize();

        auto tokenize_time = std::chrono::steady_clock::now();
        auto tokenize_duration = std::chrono::duration_cast<std::chrono::milliseconds>(tokenize_time - start_time).count();
        // std::cerr << "[DictionaryManager] Got " << tokens.size() << " tokens in " << tokenize_duration << "ms, parsing AST..." << std::endl;

        // Parse with timeout check
        Parser parser(tokens);
        // std::cerr << "[DictionaryManager] Parser created, calling parse()..." << std::endl;
        auto functions = parser.parse();

        auto end_time = std::chrono::steady_clock::now();
        auto parse_duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - tokenize_time).count();
        auto total_duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time).count();

        // std::cerr << "[DictionaryManager] Parsed " << functions.size() << " functions" << std::endl;
        // std::cerr << "[DictionaryManager] Timing: tokenize=" << tokenize_duration << "ms, parse=" << parse_duration << "ms, total=" << total_duration << "ms" << std::endl;

        // ★ パフォーマンス警告（デバッグ用） - 重要なので残す
        if (total_duration > 3000) { // 3秒以上
            std::cerr << "[DictionaryManager] WARNING: Parsing took " << total_duration << "ms (>3s)" << std::endl;
        }

        // Register functions in VM
        // std::cerr << "[DictionaryManager] Registering " << functions.size() << " functions..." << std::endl;
        for (const auto& func : functions) {
            vm_->registerFunction(func->name, func);
        }

        // std::cerr << "[DictionaryManager] Registration complete" << std::endl;
        return true;
    } catch (const std::exception& e) {
        std::cerr << "[DictionaryManager] Parse error: " << e.what() << std::endl;
        return false;
    }
}

bool DictionaryManager::load(const std::vector<std::string>& dicPaths,
                             const std::string& encoding) {
    (void)encoding; // TODO: Handle encoding conversion (UTF-8/CP932)

    auto load_start = std::chrono::steady_clock::now();
    // std::cerr << "[DictionaryManager] Starting load of " << dicPaths.size() << " dictionaries" << std::endl;

    // Reset VM and loaded files list
    vm_ = std::make_unique<VM>();
    loadedDicFiles_.clear();

    int success_count = 0;
    int fail_count = 0;

    // Load and parse each dictionary file
    for (size_t i = 0; i < dicPaths.size(); ++i) {
        const auto& path = dicPaths[i];
        auto file_start = std::chrono::steady_clock::now();

        // ファイル名のみ表示（パスが長すぎる場合）
        std::string filename = path;
        auto lastSlash = path.find_last_of("/\\");
        if (lastSlash != std::string::npos) {
            filename = path.substr(lastSlash + 1);
        }

        // std::cerr << "[DictionaryManager] [" << (i+1) << "/" << dicPaths.size() << "] Loading: " << filename << std::endl;

        std::string content = loadFile(path);
        if (content.empty()) {
            std::cerr << "[DictionaryManager] Failed to load file: " << filename << std::endl;
            fail_count++;
            continue;
        }

        // std::cerr << "[DictionaryManager] Loaded " << content.size() << " bytes, parsing..." << std::endl;

        if (!parseDictionary(content)) {
            std::cerr << "[DictionaryManager] Failed to parse: " << filename << std::endl;
            fail_count++;
            // Continue loading other files even if one fails
        } else {
            auto file_end = std::chrono::steady_clock::now();
            auto file_duration = std::chrono::duration_cast<std::chrono::milliseconds>(file_end - file_start).count();
            // std::cerr << "[DictionaryManager] Successfully parsed: " << filename << " (took " << file_duration << "ms)" << std::endl;
            loadedDicFiles_.push_back(path);  // Store successfully loaded file path
            success_count++;
        }
    }

    auto load_end = std::chrono::steady_clock::now();
    auto total_duration = std::chrono::duration_cast<std::chrono::milliseconds>(load_end - load_start).count();

    // 簡潔なサマリーのみ出力
    std::cerr << "[DictionaryManager] Loaded " << success_count << "/" << dicPaths.size()
              << " dictionaries in " << total_duration << "ms" << std::endl;
    if (fail_count > 0) {
        std::cerr << "[DictionaryManager] " << fail_count << " failed" << std::endl;
    }

    return true;
}

void DictionaryManager::unload() {
    vm_.reset();
    loadedDicFiles_.clear();
}

std::string DictionaryManager::execute(const std::string& functionName,
                                       const std::vector<std::string>& args) {
    if (!vm_) {
        std::cerr << "[DictionaryManager::execute] ERROR: VM is null!" << std::endl;
        return "";
    }

    std::cerr << "[DictionaryManager::execute] Function: " << functionName << ", args: " << args.size() << std::endl;

    // Set SHIORI references
    vm_->setReferences(args);

    // Execute the function
    std::cerr << "[DictionaryManager::execute] Calling vm_->execute()..." << std::endl;
    Value result = vm_->execute(functionName, {});
    std::cerr << "[DictionaryManager::execute] VM execution complete, converting result..." << std::endl;

    // Return the result as a string
    std::string resultStr = result.asString();
    std::cerr << "[DictionaryManager::execute] Result length: " << resultStr.length() << std::endl;

    return resultStr;
}
