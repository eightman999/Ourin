// SPDX-License-Identifier: Apache-2.0
// Independent TMIDI event/template implementation; Windows DDE is supplied by
// the explicitly configured loopback bridge, never simulated as successful.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <poll.h>
#include <fcntl.h>
#include <unistd.h>
#include <chrono>
#include <cstdlib>
#include <map>
#include <mutex>
#include <string>
#include <vector>

namespace {
std::mutex lock;
thread_local std::string output;
std::map<std::string, std::string> lastFiles;
bool initialized = false;
std::string bridgeSession;
constexpr size_t maxBytes = 1024 * 1024;

NSString *resources() {
    Dl_info info{};
    if (!dladdr((void *)&resources, &info) || !info.dli_fname) return nil;
    NSString *binary = [NSString stringWithUTF8String:info.dli_fname];
    return [[[binary stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Resources"];
}

std::string wire(int status, const std::string &key = "", const std::string &value = "") {
    const char *reason = status == 200 ? "OK" : status == 204 ? "No Content" : status == 400 ? "Bad Request" : "Service Unavailable";
    std::string s = "PLUGIN/2.0 " + std::to_string(status) + " " + reason + "\r\nCharset: UTF-8\r\n";
    if (!key.empty()) s += key + ": " + value + "\r\n";
    return s + "\r\n";
}
std::string error(const char *message) { return wire(503, "X-Ourin-Error", message); }

int port() {
    const char *env = std::getenv("OURIN_TMIDI_BRIDGE_PORT");
    if (env) {
        char *end = nullptr;
        long n = std::strtol(env, &end, 10);
        return *env && !*end && n > 0 && n <= 65535 ? (int)n : -1;
    }
    NSString *path = [resources() stringByAppendingPathComponent:@"tmidi-bridge.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return 0;
    if (data.length > 4096) return -1;
    id config = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![config isKindOfClass:[NSDictionary class]]) return -1;
    id n = config[@"port"];
    if (![n isKindOfClass:[NSNumber class]] || CFGetTypeID((__bridge CFTypeRef)n) == CFBooleanGetTypeID()) return -1;
    double number = [n doubleValue];
    return number >= 1 && number <= 65535 && number == [n intValue] ? [n intValue] : -1;
}

NSDictionary *query(int number) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return nil;
    struct Close { int fd; ~Close() { close(fd); } } closeSocket{fd};
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) return nil;
    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    auto wait = [&](short events) {
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - std::chrono::steady_clock::now()).count();
        if (ms <= 0) return false;
        pollfd p{fd, events, 0};
        return poll(&p, 1, (int)ms) > 0 && (p.revents & events);
    };
    sockaddr_in addr{};
    addr.sin_family = AF_INET; addr.sin_port = htons(number); addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (connect(fd, (sockaddr *)&addr, sizeof(addr)) < 0) {
        if (errno != EINPROGRESS || !wait(POLLOUT)) return nil;
        int value = 0; socklen_t len = sizeof(value);
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &value, &len) < 0 || value) return nil;
    }
    const std::string question = "{\"protocol\":\"ourin-tmidi-dde/1\",\"service\":\"TMIDI\",\"topic\":\"TMIDI\",\"query\":\"snapshot\"}\n";
    size_t written = 0;
    while (written < question.size()) {
        if (!wait(POLLOUT)) return nil;
        ssize_t n = send(fd, question.data() + written, question.size() - written, 0);
        if (n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        if (n <= 0) return nil;
        written += n;
    }
    std::string bytes;
    while (bytes.size() <= maxBytes) {
        if (!wait(POLLIN)) return nil;
        char buffer[4096];
        ssize_t n = recv(fd, buffer, sizeof(buffer), 0);
        if (n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        if (n <= 0) return nil;
        bytes.append(buffer, n);
        if (bytes.size() > maxBytes) return nil;
        auto newline = bytes.find('\n');
        if (newline != std::string::npos) {
            if (newline + 1 != bytes.size()) return nil;
            NSData *data = [NSData dataWithBytes:bytes.data() length:newline];
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            return [json isKindOfClass:[NSDictionary class]] ? json : nil;
        }
    }
    return nil;
}

std::string safe(NSString *text, bool escapeSlash) {
    NSMutableString *s = [text mutableCopy];
    if (escapeSlash) [s replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0,s.length)];
    for (NSString *c in @[@"\r", @"\n", @"\0"]) [s replaceOccurrencesOfString:c withString:@" " options:0 range:NSMakeRange(0,s.length)];
    return s.UTF8String ?: "";
}

std::string makeScript(NSDictionary *instance) {
    NSString *path = [resources() stringByAppendingPathComponent:@"payload/sstp_sample.txt"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) path = [resources() stringByAppendingPathComponent:@"sstp_sample.txt"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSString *text = nil;
    if (data.length <= 65536) {
        text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!text && data) text = [[NSString alloc] initWithData:data encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingDOSJapanese)];
    }
    std::map<std::string,std::string> templates;
    std::string section;
    for (NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        if ([line hasPrefix:@"#"]) {
            NSString *name = [[[line substringFromIndex:1] componentsSeparatedByString:@","] firstObject];
            section = [[name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] UTF8String];
        } else if ([line hasPrefix:@"Script:"] && !templates.count(section)) {
            templates[section] = safe([[line substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]], false);
        }
    }
    NSString *filename = instance[@"getfilename"];
    NSString *ext = filename.pathExtension.uppercaseString;
    NSString *wrd = instance[@"wrd"];
    if (![wrd isKindOfClass:[NSString class]]) wrd = [ext isEqualToString:@"NEO"] ? @"NeoWRD" : @"NoWRD";
    std::string selected = safe(wrd,false);
    std::string source = templates.count(selected) && !templates[selected].empty() ? templates[selected] : templates["NoWRD"];
    if (source.empty()) source = "\\0\\s[0]$title\\n\\e";
    std::string title = safe(instance[@"gettitle"],true);
    if (title.empty()) title = "Unknown";
    std::string format = ext.length ? safe(ext,false) : "MIDI";
    std::string script;
    for (size_t i = 0; i < source.size();) {
        if (source.compare(i,6,"$title") == 0) { script += title; i += 6; }
        else if (source.compare(i,7,"$format") == 0) { script += format; i += 7; }
        else script += source[i++];
        if (script.size() > 65536) return "";
    }
    return script;
}

std::string pollInstances() {
    int number = port();
    if (!number) return error("tmidi_bridge_not_configured");
    if (number < 0) return error("tmidi_bridge_invalid_port");
    NSDictionary *snapshot = query(number);
    if (!snapshot) return error("tmidi_bridge_unavailable");
    if (![snapshot[@"protocol"] isEqual:@"ourin-tmidi-dde/1"] || snapshot[@"error"] ||
        ![snapshot[@"session"] isKindOfClass:[NSString class]] ||
        ![snapshot[@"instances"] isKindOfClass:[NSArray class]] || [snapshot[@"instances"] count] > 32) return error("tmidi_bridge_invalid_snapshot");
    NSMutableSet *seen = [NSMutableSet set];
    for (id item in snapshot[@"instances"]) {
        if (![item isKindOfClass:[NSDictionary class]]) return error("tmidi_bridge_invalid_instance");
        for (NSString *key in @[@"id", @"getstatus", @"getplayfile", @"getfilename", @"gettitle"]) {
            if (![item[key] isKindOfClass:[NSString class]] || [item[key] length] > 8192) return error("tmidi_bridge_invalid_instance");
        }
        if (![item[@"id"] length] || [seen containsObject:item[@"id"]]) return error("tmidi_bridge_duplicate_instance");
        [seen addObject:item[@"id"]];
    }
    std::string session = safe(snapshot[@"session"],false);
    if (session != bridgeSession) { lastFiles.clear(); initialized = false; bridgeSession = session; }
    std::map<std::string,std::string> next;
    std::string result;
    for (NSDictionary *item in snapshot[@"instances"]) {
        std::string id = safe(item[@"id"],false), state = safe(item[@"getstatus"],false);
        if (state.empty()) continue;
        std::string previous = lastFiles.count(id) ? lastFiles[id] : "";
        std::string filename = safe(item[@"getfilename"],false);
        if (state == "stop") next[id] = "";
        else if (state == "play") {
            // At first attachment the original ignores already-playing files.
            // New instances after attachment start with an empty previous file.
            if (initialized && filename != previous) {
                if (result.empty()) { result = makeScript(item); next[id] = filename; }
                else next[id] = previous; // don't lose simultaneous next-instance change
            } else next[id] = filename;
        } else next[id] = previous; // pause/resume does not announce twice
    }
    lastFiles = std::move(next); initialized = true;
    return result.empty() ? wire(204) : wire(200,"Script",result);
}

std::string dispatch(NSString *text) {
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\r\n"];
    if (lines.count < 3 || ![lines[lines.count-1] isEqualToString:@""] || ![lines[lines.count-2] isEqualToString:@""]) return wire(400);
    bool notify = [lines[0] hasPrefix:@"NOTIFY "];
    if (![lines[0] isEqualToString:@"GET PLUGIN/2.0"] && ![lines[0] isEqualToString:@"GET PLUGIN/2.0M"] &&
        ![lines[0] isEqualToString:@"NOTIFY PLUGIN/2.0"] && ![lines[0] isEqualToString:@"NOTIFY PLUGIN/2.0M"]) return wire(400);
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    for (NSUInteger i=1;i+2<lines.count;i++) {
        NSRange sep = [lines[i] rangeOfString:@":"];
        if (sep.location == NSNotFound || sep.location == 0) return wire(400);
        NSString *key = [lines[i] substringToIndex:sep.location].lowercaseString;
        if (headers[key]) return wire(400);
        headers[key] = [[lines[i] substringFromIndex:sep.location+1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    if (!headers[@"id"]) return wire(400);
    if ([headers[@"id"] isEqualToString:@"version"]) return notify ? wire(204) : wire(200,"Value","Ourin TMIDI bridge/1.0");
    if ([headers[@"id"] isEqualToString:@"OnSecondChange"]) {
        auto result = pollInstances();
        return notify && result.find("PLUGIN/2.0 200") == 0 ? wire(204) : result;
    }
    return wire(204); // Original OnMenuExec and unrelated events have no payload.
}
}

extern "C" int32_t loadu(char *path, size_t length) {
    (void)length; free(path); std::lock_guard<std::mutex> guard(lock);
    initialized=false; bridgeSession.clear(); lastFiles.clear(); return 1;
}
extern "C" void unload() { std::lock_guard<std::mutex> guard(lock); initialized=false; bridgeSession.clear(); lastFiles.clear(); }
extern "C" const uint8_t *request(const uint8_t *input, size_t length, size_t *size) {
    if (!size) return nullptr;
    @autoreleasepool {
        std::lock_guard<std::mutex> guard(lock);
        if (!input || length > maxBytes || memchr(input,0,length)) output=wire(400);
        else {
            NSString *text = [[NSString alloc] initWithBytes:input length:length encoding:NSUTF8StringEncoding];
            try { output = text ? dispatch(text) : wire(400); }
            catch (...) { output=error("tmidi_native_failure"); }
        }
        *size=output.size(); return (const uint8_t *)output.data();
    }
}
