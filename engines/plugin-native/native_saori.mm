// SPDX-License-Identifier: Apache-2.0
// Ourin implementations of narrowly scoped legacy SAORI operations.
// No upstream dictionaries, executables or third-party implementation are embedded.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <arpa/inet.h>
#include <poll.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <unistd.h>
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <map>
#include <string>
#include <vector>

namespace {
thread_local std::string reply;
constexpr size_t maxRequest = 1024 * 1024;

std::string lower(std::string s) {
    for (char &c : s) if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
    return s;
}
std::string response(int status, const std::string &result = "", const std::string &error = "") {
    const char *reason = status == 200 ? "OK" : status == 400 ? "Bad Request" :
        status == 420 ? "Refuse" : status == 501 ? "Not Implemented" : "Service Unavailable";
    std::string out = "SAORI/1.0 " + std::to_string(status) + " " + reason + "\r\nCharset: UTF-8\r\n";
    if (status == 200) out += "Result: " + result + "\r\n";
    if (!error.empty()) out += "X-Ourin-Error: " + error + "\r\n";
    return out + "\r\n";
}

bool parse(const std::string &wire, std::map<std::string, std::string> &headers, bool &version) {
    size_t first = wire.find("\r\n");
    if (first == std::string::npos || wire.find('\0') != std::string::npos) return false;
    auto verb = wire.substr(0, first);
    version = verb == "GET Version SAORI/1.0";
    if (!version && verb != "EXECUTE SAORI/1.0") return false;
    size_t pos = first + 2;
    while (pos < wire.size()) {
        size_t end = wire.find("\r\n", pos);
        if (end == std::string::npos) return false;
        if (end == pos) return end + 2 == wire.size();
        auto line = wire.substr(pos, end - pos);
        size_t sep = line.find(':');
        if (sep == std::string::npos) return false;
        auto key = lower(line.substr(0, sep));
        if (key.empty() || key.find_first_not_of("abcdefghijklmnopqrstuvwxyz0123456789-") != std::string::npos || headers.count(key)) return false;
        size_t value = sep + 1;
        if (value < line.size() && line[value] == ' ') ++value;
        headers.emplace(key, line.substr(value));
        pos = end + 2;
    }
    return false;
}

// Preserve the author's window-title escaping: quotes/percent removed, slashes
// doubled. CR/LF are flattened so a desktop title cannot inject SAORI headers.
std::string titleResult(NSString *title) {
    NSMutableString *safe = [title mutableCopy];
    for (NSString *needle in @[@"'", @"\"", @"%"]) {
        [safe replaceOccurrencesOfString:needle withString:@"" options:0 range:NSMakeRange(0, safe.length)];
    }
    [safe replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, safe.length)];
    for (NSString *needle in @[@"\r", @"\n", @"\0"]) {
        [safe replaceOccurrencesOfString:needle withString:@" " options:0 range:NSMakeRange(0, safe.length)];
    }
    return std::string(safe.UTF8String ?: "");
}

std::string windowTitle() {
    // Never request or silently change TCC permissions from a plugin callback.
    if (!AXIsProcessTrusted()) return response(420, "", "accessibility_permission_required");
    AXUIElementRef system = AXUIElementCreateSystemWide();
    AXUIElementSetMessagingTimeout(system, 0.25f);
    CFTypeRef app = nullptr, window = nullptr, title = nullptr;
    AXError status = AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute, &app);
    CFRelease(system);
    if (status != kAXErrorSuccess || !app || CFGetTypeID(app) != AXUIElementGetTypeID()) {
        if (app) CFRelease(app);
        return response(503, "", "focused_application_unavailable");
    }
    AXUIElementSetMessagingTimeout((AXUIElementRef)app, 0.25f);
    status = AXUIElementCopyAttributeValue((AXUIElementRef)app, kAXFocusedWindowAttribute, &window);
    CFRelease(app);
    if (status != kAXErrorSuccess || !window || CFGetTypeID(window) != AXUIElementGetTypeID()) {
        if (window) CFRelease(window);
        return response(503, "", "focused_window_unavailable");
    }
    AXUIElementSetMessagingTimeout((AXUIElementRef)window, 0.25f);
    status = AXUIElementCopyAttributeValue((AXUIElementRef)window, kAXTitleAttribute, &title);
    CFRelease(window);
    if (status != kAXErrorSuccess || !title || CFGetTypeID(title) != CFStringGetTypeID()) {
        if (title) CFRelease(title);
        return response(503, "", "window_title_unavailable");
    }
    std::string value = titleResult((__bridge NSString *)title);
    CFRelease(title);
    return response(200, value);
}

// BouyomiChan command 1: little-endian int16 command/speed/tone/volume/voice,
// uint8 UTF-8 encoding marker and uint32 UTF-8 byte count. No shell or exe run.
std::vector<uint8_t> packet(const std::string &text) {
    std::vector<uint8_t> bytes = {1,0,255,255,255,255,255,255,0,0,0};
    uint32_t count = (uint32_t)text.size();
    for (unsigned shift = 0; shift < 32; shift += 8) bytes.push_back((count >> shift) & 255);
    bytes.insert(bytes.end(), text.begin(), text.end());
    return bytes;
}

std::string sendTalk(const std::string &text) {
    if (text.empty()) return response(400, "", "empty_speech");
    // Loopback only; a Windows service can be forwarded explicitly by the user.
    unsigned long port = 50001;
    if (const char *p = std::getenv("OURIN_BOUYOMI_PORT")) {
        char *end = nullptr;
        port = std::strtoul(p, &end, 10);
        if (!*p || *end || port < 1 || port > 65535) return response(400, "", "invalid_bouyomi_port");
    }
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return response(503, "", "socket_unavailable");
    struct Close { int fd; ~Close() { close(fd); } } closer{fd};
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) return response(503, "", "socket_configuration_failed");
    sockaddr_in address{};
    address.sin_family = AF_INET; address.sin_port = htons((uint16_t)port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int connected = connect(fd, (sockaddr *)&address, sizeof(address));
    if (connected < 0 && errno != EINPROGRESS) return response(503, "", "bouyomi_connection_failed");
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    auto waitWritable = [&]() {
        auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - std::chrono::steady_clock::now()).count();
        if (remaining <= 0) return false;
        pollfd pfd{fd, POLLOUT, 0};
        return poll(&pfd, 1, (int)remaining) > 0 && (pfd.revents & POLLOUT);
    };
    if (connected < 0) {
        if (!waitWritable()) return response(503, "", "bouyomi_connect_timeout");
        int error = 0; socklen_t size = sizeof(error);
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) < 0 || error) return response(503, "", "bouyomi_connection_failed");
    }
    auto bytes = packet(text);
    size_t sent = 0;
    while (sent < bytes.size()) {
        if (!waitWritable()) return response(503, "", "bouyomi_send_timeout");
        ssize_t amount = send(fd, bytes.data() + sent, bytes.size() - sent, 0);
        if (amount < 0 && (errno == EINTR || errno == EWOULDBLOCK || errno == EAGAIN)) continue;
        if (amount <= 0) return response(503, "", "bouyomi_send_failed");
        sent += (size_t)amount;
    }
    // TCP acceptance is not evidence that speech synthesis completed.
    return response(200, "1");
}

std::string dispatch(const std::string &wire) {
    std::map<std::string, std::string> h;
    bool version = false;
    if (!parse(wire, h, version)) return response(400, "", "malformed_request");
    auto charset = lower(h["charset"]);
    // Adapter passes VM strings as UTF-8 even when a legacy dictionary selects
    // a Windows charset. No second transcoding is applied at this boundary.
    if (!charset.empty() && charset != "utf-8" && charset != "utf8" && charset != "sjis" && charset != "shift_jis" && charset != "cp932") return response(400, "", "unsupported_charset");
    NSString *decoded = [[NSString alloc] initWithBytes:wire.data() length:wire.size() encoding:NSUTF8StringEncoding];
    if (!decoded) return response(400, "", "invalid_utf8");
    if (version) return response(200, "Ourin native SAORI/1.0");
#if defined(OURIN_SENDTALK)
    auto path = lower(h["argument1"]);
    std::replace(path.begin(), path.end(), '\\', '/');
    if (h["argument0"] != "hide" || path != "../sendtalk.exe" || h.count("argument3")) return response(501, "", "unsupported_exec_operation");
    return sendTalk(h["argument2"]);
#else
    auto path = lower(h["argument0"]);
    std::replace(path.begin(), path.end(), '\\', '/');
    if (path == "/charset" && !h.count("argument2")) {
        auto selected = lower(h["argument1"]);
        if (selected == "sjis" || selected == "shift_jis" || selected == "utf-8") return response(200, "1");
        return response(400, "", "unsupported_legacy_charset");
    }
    if ((path != "./getwindowtitle.exe" && path != "getwindowtitle.exe") || h.count("argument1")) return response(501, "", "unsupported_proxy_operation");
    return windowTitle();
#endif
}
}

// Ourin ABI: request input borrowed; returned bytes valid until next call on
// this thread. loadu consumes malloc-owned path, matching Plugin's host contract.
extern "C" int32_t loadu(char *path, size_t length) { (void)length; free(path); return 1; }
extern "C" void unload() { reply.clear(); }
extern "C" const uint8_t *request(const uint8_t *input, size_t length, size_t *outputLength) {
    @autoreleasepool {
        if (!outputLength) return nullptr;
        try {
            reply = !input || length > maxRequest ? response(400, "", "request_size_invalid") :
                dispatch(std::string((const char *)input, length));
        } catch (...) { reply = response(503, "", "native_backend_failure"); }
        *outputLength = reply.size();
        return (const uint8_t *)reply.data();
    }
}
