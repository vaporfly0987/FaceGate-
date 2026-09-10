#include "Recognizer.hpp"
#include <opencv2/imgproc.hpp>
#include <opencv2/dnn.hpp>
#include <algorithm>
#include <stdexcept>

namespace fg {
Recognizer::Recognizer(const std::string &models) {
    cv::setNumThreads(2);
    detector_ = cv::FaceDetectorYN::create(models + "/face_detection_yunet_2023mar.onnx", "",
        cv::Size(640, 480), 0.90f, 0.3f, 5000, cv::dnn::DNN_BACKEND_OPENCV, cv::dnn::DNN_TARGET_CPU);
    recognizer_ = cv::FaceRecognizerSF::create(models + "/face_recognition_sface_2021dec.onnx", "",
        cv::dnn::DNN_BACKEND_OPENCV, cv::dnn::DNN_TARGET_CPU);
}
FaceResult Recognizer::analyze(const cv::Mat &bgr, double captured, const Embedding *owner) {
    FaceResult r; r.observation.captured = captured;
    if (bgr.empty() || bgr.type() != CV_8UC3) return r;
    detector_->setInputSize(bgr.size());
    cv::Mat faces; detector_->detect(bgr, faces);
    r.observation.faces = faces.rows;
    if (faces.rows != 1) return r;
    const float *f = faces.ptr<float>(0);
    for (int i = 0; i < 15; ++i) if (!std::isfinite(f[i])) return r;
    r.observation.facePixels = std::min(f[2], f[3]);
    if (r.observation.facePixels < 120) return r;
    r.bounds = cv::Rect(int(f[0]), int(f[1]), int(f[2]), int(f[3])) & cv::Rect(0, 0, bgr.cols, bgr.rows);
    if (r.bounds.width < 120 || r.bounds.height < 120) return r;
    cv::Mat gray; cv::cvtColor(bgr(r.bounds), gray, cv::COLOR_BGR2GRAY);
    double brightness = cv::mean(gray)[0];
    cv::Mat lap; cv::Laplacian(gray, lap, CV_64F);
    cv::Scalar mean, deviation; cv::meanStdDev(lap, mean, deviation);
    if (brightness < 35 || brightness > 225 || deviation[0] * deviation[0] < 35) return r;
    // YuNet indices: two eyes at 4..7, nose at 8..9. Unmirrored sensor coordinates.
    double eyeDistance = std::abs(double(f[4]) - f[6]);
    if (eyeDistance < 20) return r;
    r.observation.pose = (f[8] - (f[4] + f[6]) / 2.0) / eyeDistance;
    cv::Mat aligned, feature;
    recognizer_->alignCrop(bgr, faces.row(0), aligned);
    recognizer_->feature(aligned, feature);
    if (feature.total() != embeddingSize || feature.type() != CV_32F) return r;
    std::copy_n(feature.ptr<float>(), embeddingSize, r.embedding.begin());
    if (!normalize(r.embedding)) return r;
    if (owner) r.observation.score = cosine(r.embedding, *owner);
    r.usable = true;
    return r;
}
}
