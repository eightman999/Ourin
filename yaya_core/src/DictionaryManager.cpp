#include "DictionaryManager.hpp"
#include "Lexer.hpp"
#include "Parser.hpp"
#include "Value.hpp"
#include <fstream>
#include <sstream>
#include <iostream>
#include <chrono>
#include <algorithm>
#include <cctype>
#include <cerrno>
#include <vector>
#include <iconv.h>

namespace {

// UTF-8 として妥当なバイト列かを検査する（構造チェックのみ）
bool isValidUTF8(const std::string& s) {
    const unsigned char* b = reinterpret_cast<const unsigned char*>(s.data());
    size_t n = s.size();
    size_t i = 0;
    while (i < n) {
        unsigned char c = b[i];
        size_t len;
        if (c < 0x80) { i++; continue; }
        else if ((c & 0xE0) == 0xC0) len = 2;
        else if ((c & 0xF0) == 0xE0) len = 3;
        else if ((c & 0xF8) == 0xF0) len = 4;
        else return false;
        if (i + len > n) return false;
        for (size_t j = 1; j < len; ++j) {
            if ((b[i + j] & 0xC0) != 0x80) return false;
        }
        i += len;
    }
    return true;
}

bool hasNonAscii(const std::string& s) {
    for (unsigned char c : s) {
        if (c >= 0x80) return true;
    }
    return false;
}

// yaya.txt の charset 表記ゆれを吸収する。戻り値: "UTF-8" / "CP932" / "AUTO"
std::string normalizeEncodingName(std::string enc) {
    std::transform(enc.begin(), enc.end(), enc.begin(),
                   [](unsigned char c) { return std::tolower(c); });
    enc.erase(std::remove_if(enc.begin(), enc.end(),
                             [](char c) { return c == '-' || c == '_' || c == ' '; }),
              enc.end());
    if (enc == "utf8") return "UTF-8";
    if (enc == "shiftjis" || enc == "sjis" || enc == "cp932" ||
        enc == "windows31j" || enc == "ms932" || enc == "ms_kanji") return "CP932";
    if (enc.empty() || enc == "auto" || enc == "default") return "AUTO";
    std::cerr << "[DictionaryManager] Unknown encoding name '" << enc
              << "', falling back to auto-detection" << std::endl;
    return "AUTO";
}

bool convertWithIconv(const std::string& input, const char* fromCode, std::string& output) {
    iconv_t cd = iconv_open("UTF-8", fromCode);
    if (cd == (iconv_t)-1) {
        std::cerr << "[DictionaryManager] iconv_open(UTF-8, " << fromCode
                  << ") failed: " << strerror(errno) << std::endl;
        return false;
    }
    std::string result;
    result.reserve(input.size() * 2);
    std::vector<char> buf(65536);
    char* inPtr = const_cast<char*>(input.data());
    size_t inLeft = input.size();
    bool ok = true;
    while (inLeft > 0) {
        char* outPtr = buf.data();
        size_t outLeft = buf.size();
        size_t rc = iconv(cd, &inPtr, &inLeft, &outPtr, &outLeft);
        result.append(buf.data(), buf.size() - outLeft);
        if (rc == (size_t)-1) {
            if (errno == E2BIG) continue; // 出力バッファ満杯 → 続行
            ok = false;
            break;
        }
    }
    iconv_close(cd);
    if (ok) output = std::move(result);
    return ok;
}

} // namespace

DictionaryManager::DictionaryManager() {
    vm_ = std::make_unique<VM>();
}

void DictionaryManager::setCallback(VMCallback* callback) {
    storedCallback_ = callback;
    if (vm_) {
        vm_->setCallback(callback);
    }
}

std::string DictionaryManager::loadFile(const std::string& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "[DictionaryManager] Failed to open file: " << path << std::endl;
        return "";
    }

    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

// 辞書バイト列を UTF-8 テキストに正規化する。
// 優先順位: UTF-8 BOM → 指定エンコーディング → 自動判定（UTF-8妥当性 → CP932変換）。
// 既存の UTF-8 辞書を壊さないため、宣言が CP932 でも内容が妥当な非ASCII UTF-8 なら UTF-8 として扱う。
std::string DictionaryManager::decodeContent(const std::string& raw,
                                             const std::string& encoding,
                                             const std::string& filename) {
    // UTF-8 BOM があれば除去して UTF-8 として確定
    if (raw.size() >= 3 &&
        (unsigned char)raw[0] == 0xEF &&
        (unsigned char)raw[1] == 0xBB &&
        (unsigned char)raw[2] == 0xBF) {
        return raw.substr(3);
    }

    const std::string norm = normalizeEncodingName(encoding);

    if (norm == "UTF-8") {
        if (isValidUTF8(raw)) return raw;
        std::string converted;
        if (convertWithIconv(raw, "CP932", converted)) {
            std::cerr << "[DictionaryManager] WARNING: " << filename
                      << " declared UTF-8 but contains invalid UTF-8; converted from CP932" << std::endl;
            return converted;
        }
        std::cerr << "[DictionaryManager] ERROR: " << filename
                  << " is not valid UTF-8 and CP932 conversion failed; loading raw bytes (may mis-parse)" << std::endl;
        return raw;
    }

    if (norm == "CP932") {
        // 宣言と異なり実体が UTF-8 のケース（作者が charset 更新を忘れた等）を保護する
        if (hasNonAscii(raw) && isValidUTF8(raw)) {
            std::cerr << "[DictionaryManager] WARNING: " << filename
                      << " declared Shift_JIS/CP932 but content is valid UTF-8; using as UTF-8" << std::endl;
            return raw;
        }
        std::string converted;
        if (convertWithIconv(raw, "CP932", converted)) {
            return converted;
        }
        std::cerr << "[DictionaryManager] ERROR: " << filename
                  << ": CP932 -> UTF-8 conversion failed; loading raw bytes (may mis-parse)" << std::endl;
        return raw;
    }

    // AUTO: UTF-8 として妥当ならそのまま、そうでなければ CP932 とみなして変換
    if (isValidUTF8(raw)) return raw;
    std::string converted;
    if (convertWithIconv(raw, "CP932", converted)) {
        std::cerr << "[DictionaryManager] " << filename
                  << ": detected CP932/Shift_JIS, converted to UTF-8" << std::endl;
        return converted;
    }
    std::cerr << "[DictionaryManager] ERROR: " << filename
              << ": encoding detection failed (not UTF-8, CP932 conversion failed); loading raw bytes" << std::endl;
    return raw;
}

// 行頭 #define / #globaldefine ディレクティブを解釈し、宣言行より後ろの行へ
// 登録順の単純テキスト置換を適用する（本家 YAYA プリプロセッサ互換の生置換）。
// - #define は当該ファイル内のみ有効
// - #globaldefine は以降にロードされる全ファイルにも有効（メンバに蓄積）
// - 適用順は「global（登録順）→ ファイル内 define（登録順）」
// - ディレクティブ行自体は残置する（Lexer の '#' 行コメント読み飛ばしが安全網）
std::string DictionaryManager::preprocessDirectives(const std::string& content) {
    std::vector<std::pair<std::string, std::string>> fileDefines;

    // "#keyword NAME value..." を分解。NAME は最初の空白まで、value は行末まで（前方空白除去）。
    auto parseDirective = [](const std::string& line, const char* keyword,
                             std::string& name, std::string& value) -> bool {
        size_t klen = std::char_traits<char>::length(keyword);
        if (line.compare(0, klen, keyword) != 0) return false;
        size_t p = klen;
        if (p >= line.size() || (line[p] != ' ' && line[p] != '\t')) return false;
        while (p < line.size() && (line[p] == ' ' || line[p] == '\t')) p++;
        size_t nameEnd = p;
        while (nameEnd < line.size() && line[nameEnd] != ' ' && line[nameEnd] != '\t') nameEnd++;
        if (nameEnd == p) return false;
        name = line.substr(p, nameEnd - p);
        size_t valStart = nameEnd;
        while (valStart < line.size() && (line[valStart] == ' ' || line[valStart] == '\t')) valStart++;
        value = line.substr(valStart);
        while (!value.empty() && value.back() == '\r') value.pop_back();
        while (!name.empty() && name.back() == '\r') name.pop_back();
        return true;
    };

    auto replaceAll = [](std::string& s, const std::string& from, const std::string& to) {
        if (from.empty()) return;
        size_t pos = 0;
        while ((pos = s.find(from, pos)) != std::string::npos) {
            s.replace(pos, from.size(), to);
            pos += to.size();
        }
    };

    std::string out;
    out.reserve(content.size());
    size_t lineStart = 0;
    while (lineStart <= content.size()) {
        size_t lineEnd = content.find('\n', lineStart);
        std::string line = (lineEnd == std::string::npos)
            ? content.substr(lineStart)
            : content.substr(lineStart, lineEnd - lineStart);

        std::string name, value;
        if (parseDirective(line, "#globaldefine", name, value)) {
            preprocessorGlobalDefines_.emplace_back(name, value);
            if (vm_) vm_->registerGlobalDefine(name, value);
        } else if (parseDirective(line, "#define", name, value)) {
            fileDefines.emplace_back(name, value);
        } else if (!preprocessorGlobalDefines_.empty() || !fileDefines.empty()) {
            for (const auto& def : preprocessorGlobalDefines_) {
                replaceAll(line, def.first, def.second);
            }
            for (const auto& def : fileDefines) {
                replaceAll(line, def.first, def.second);
            }
        }

        out += line;
        if (lineEnd == std::string::npos) break;
        out += '\n';
        lineStart = lineEnd + 1;
    }
    return out;
}

bool DictionaryManager::parseDictionary(const std::string& content, const std::string& sourceName) {
    try {
        // std::cerr << "[DictionaryManager] Tokenizing..." << std::endl;
        auto start_time = std::chrono::steady_clock::now();

        // 行頭 #define / #globaldefine を解釈・置換してから字句解析へ
        std::string preprocessed = preprocessDirectives(content);

        // Tokenize
        Lexer lexer(preprocessed);
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

        // Register functions in VM under a fresh source scope (for DICLOAD/DICUNLOAD ownership).
        // std::cerr << "[DictionaryManager] Registering " << functions.size() << " functions..." << std::endl;
        vm_->beginSource(sourceName);
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
    // Legacy entry point: convert flat paths to entries with inherited default encoding.
    std::vector<DicEntry> entries;
    entries.reserve(dicPaths.size());
    for (const auto& p : dicPaths) {
        entries.push_back({p, ""});
    }
    return load(entries, encoding);
}

bool DictionaryManager::load(const std::vector<DicEntry>& dicEntries,
                             const std::string& defaultEncoding) {
    auto load_start = std::chrono::steady_clock::now();
    // std::cerr << "[DictionaryManager] Starting load of " << dicEntries.size() << " dictionaries" << std::endl;

    // Reset VM and loaded files list
    vm_ = std::make_unique<VM>();
    if (storedCallback_) vm_->setCallback(storedCallback_);  // preserve callback through reset
    if (!ghostRoot_.empty()) vm_->setGhostRootPath(ghostRoot_);
    loadedDicFiles_.clear();
    preprocessorGlobalDefines_.clear();

    int success_count = 0;
    int fail_count = 0;

    // Load and parse each dictionary file
    for (size_t i = 0; i < dicEntries.size(); ++i) {
        const auto& entry = dicEntries[i];
        const auto& path = entry.path;
        auto file_start = std::chrono::steady_clock::now();

        // ファイル名のみ表示（パスが長すぎる場合）
        std::string filename = path;
        auto lastSlash = path.find_last_of("/\\");
        if (lastSlash != std::string::npos) {
            filename = path.substr(lastSlash + 1);
        }

        // std::cerr << "[DictionaryManager] [" << (i+1) << "/" << dicEntries.size() << "] Loading: " << filename << std::endl;

        std::string content = loadFile(path);
        if (content.empty()) {
            std::cerr << "[DictionaryManager] Failed to load file: " << filename << std::endl;
            fail_count++;
            continue;
        }

        // 文字コードを UTF-8 に正規化。per-dic エンコーディング優先、次にデフォルト。
        std::string effectiveEncoding = entry.encoding.empty() ? defaultEncoding : entry.encoding;
        content = decodeContent(content, effectiveEncoding, filename);

        // std::cerr << "[DictionaryManager] Loaded " << content.size() << " bytes, parsing..." << std::endl;

        if (!parseDictionary(content, path)) {
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
    std::cerr << "[DictionaryManager] Loaded " << success_count << "/" << dicEntries.size()
              << " dictionaries in " << total_duration << "ms" << std::endl;
    if (fail_count > 0) {
        std::cerr << "[DictionaryManager] " << fail_count << " failed" << std::endl;
    }

    // 全辞書が読めなかった場合のみ失敗扱い（一部失敗は継続）
    return success_count > 0 || dicEntries.empty();
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

    // Convert string args to Value args for _argv
    std::vector<Value> valueArgs;
    for (const auto& a : args) {
        valueArgs.push_back(Value(a));
    }

    // Execute the function
    std::cerr << "[DictionaryManager::execute] Calling vm_->execute()..." << std::endl;
    Value result = vm_->execute(functionName, valueArgs);
    std::cerr << "[DictionaryManager::execute] VM execution complete, converting result..." << std::endl;

    // Return the result as a string
    std::string resultStr = result.asString();
    std::cerr << "[DictionaryManager::execute] Result length: " << resultStr.length() << std::endl;

    return resultStr;
}

void DictionaryManager::setGhostRoot(const std::string& root) {
    ghostRoot_ = root;
    if (vm_) vm_->setGhostRootPath(root);
}

bool DictionaryManager::dicLoad(const std::string& relativePath, const std::string& encoding) {
    if (!vm_) return false;
    // Sandbox: reject absolute paths and parent traversal.
    if (relativePath.empty() || relativePath[0] == '/' ||
        relativePath.find("..") != std::string::npos) {
        return false;
    }
    std::string fullPath = ghostRoot_;
    if (!fullPath.empty() && fullPath.back() != '/') fullPath += '/';
    fullPath += relativePath;

    std::string content = loadFile(fullPath);
    if (content.empty()) return false;
    content = decodeContent(content, encoding.empty() ? "auto" : encoding, relativePath);
    if (!parseDictionary(content, fullPath)) return false;
    // Avoid duplicate tracking in the loaded-files list.
    if (std::find(loadedDicFiles_.begin(), loadedDicFiles_.end(), fullPath) == loadedDicFiles_.end()) {
        loadedDicFiles_.push_back(fullPath);
    }
    return true;
}

bool DictionaryManager::dicUnload(const std::string& relativePath) {
    if (!vm_) return false;
    int sourceId = vm_->findSource(relativePath);
    if (sourceId <= 0) return false;
    vm_->unloadSource(sourceId);
    // Remove from loaded-files list (match by basename).
    auto basename = [](const std::string& p) -> std::string {
        auto pos = p.find_last_of("/\\");
        return (pos == std::string::npos) ? p : p.substr(pos + 1);
    };
    std::string want = basename(relativePath);
    loadedDicFiles_.erase(std::remove_if(loadedDicFiles_.begin(), loadedDicFiles_.end(),
        [&](const std::string& p) { return basename(p) == want; }), loadedDicFiles_.end());
    return true;
}

bool DictionaryManager::appendRuntimeDic(const std::string& code) {
    if (!vm_) return false;
    return parseDictionary(code, "__runtime__");
}

bool DictionaryManager::hasFunction(const std::string& functionName) const {
    if (!vm_) return false;
    return vm_->hasFunction(functionName);
}
