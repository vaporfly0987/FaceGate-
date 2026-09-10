#include "Recognizer.hpp"
#include <iostream>
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    try {
        fg::Recognizer recognizer(argv[1]);
        auto result = recognizer.analyze(cv::Mat::zeros(480, 640, CV_8UC3), 0, nullptr);
        if (result.usable || result.observation.faces != 0) return 1;
        std::cout << "Verified models load; blank frame rejected\n";
        return 0;
    } catch (const std::exception &e) { std::cerr << e.what() << '\n'; return 1; }
}
