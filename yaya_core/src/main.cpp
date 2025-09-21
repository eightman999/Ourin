#include <iostream>
#include <string>
#include "YayaCore.hpp"

int main() {
    YayaCore core;
    std::string line;
    while (std::getline(std::cin, line)) {
        auto response = core.processCommand(line);
        std::cout << response << std::endl;
    }
    return 0;
}
