#include <iostream>
#include <string>
#include <pthread.h>
#include "YayaCore.hpp"

namespace {

// YAYA の辞書は深い再帰を書ける（fncdepth,0 は無制限）。既定の 8MB では VM の再帰上限
// （MAX_RECURSION_DEPTH）より先にスタックが尽きて落ちるので、大きなスタックのスレッドで処理する。
// 確保するのは仮想アドレスだけで、使った分だけが実際のメモリになる。
constexpr size_t kRequestStackSize = 512ull * 1024 * 1024;

void* runRequestLoop(void*) {
    YayaCore core;
    std::string line;
    while (std::getline(std::cin, line)) {
        auto response = core.processCommand(line);
        std::cout << response << std::endl;
    }
    return nullptr;
}

} // namespace

int main() {
    pthread_attr_t attr;
    pthread_t thread;
    if (pthread_attr_init(&attr) == 0 &&
        pthread_attr_setstacksize(&attr, kRequestStackSize) == 0 &&
        pthread_create(&thread, &attr, runRequestLoop, nullptr) == 0) {
        pthread_attr_destroy(&attr);
        pthread_join(thread, nullptr);
        return 0;
    }
    std::cerr << "[yaya_core] Could not start the large-stack thread; running on the main thread" << std::endl;
    runRequestLoop(nullptr);
    return 0;
}
