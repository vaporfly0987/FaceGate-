#pragma once
#include "Gate.hpp"
#include <opencv2/core.hpp>
#include <opencv2/objdetect/face.hpp>
#include <string>
namespace fg {
struct FaceResult {
    Observation observation;
    Embedding embedding{};
    bool usable = false;
    cv::Rect bounds;
};
class Recognizer {
public:
    explicit Recognizer(const std::string &models);
    FaceResult analyze(const cv::Mat &bgr, double captured, const Embedding *owner);
private:
    cv::Ptr<cv::FaceDetectorYN> detector_;
    cv::Ptr<cv::FaceRecognizerSF> recognizer_;
};
}
