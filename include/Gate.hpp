#pragma once
#include <array>
#include <cmath>
#include <cstdint>
#include <string>

namespace fg {
constexpr size_t embeddingSize = 128;
using Embedding = std::array<float, embeddingSize>;
constexpr double matchThreshold = 0.55; // Experimental operating point; not a calibrated FAR.
double cosine(const Embedding &a, const Embedding &b);
bool normalize(Embedding &value);
struct Observation {
    int faces = 0;
    double score = -1;
    double pose = 0; // Nose offset / eye separation; a 2D motion heuristic, not depth.
    double facePixels = 0;
    double captured = 0; // Monotonic time, same clock as Gate::observe.
};
enum class Stage { acquire, turn, center, passed };
class Gate {
public:
    void reset(double now, int direction);
    bool observe(const Observation &frame, double now);
    Stage stage() const { return stage_; }
    int direction() const { return direction_; }
private:
    Stage stage_ = Stage::acquire;
    int direction_ = 1;
    int count_ = 0;
    double first_ = 0, last_ = -1, started_ = 0;
    void lose();
};
struct UnlockEvidence {
    bool optedIn = false, sameOSBuild = false, sameAppBuild = false;
    bool locked = false, currentUser = false, onConsole = false;
    bool loginComplete = false, trustedTarget = false, secureField = false;
    bool emptyField = false, userLabel = false, accessibility = false;
    bool alreadyAttempted = true;
    double matchAge = INFINITY;
};
bool canSubmit(const UnlockEvidence &e);
}
