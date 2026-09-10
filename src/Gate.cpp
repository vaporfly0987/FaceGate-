#include "Gate.hpp"
#include <algorithm>

namespace fg {
bool normalize(Embedding &value) {
    double norm = 0;
    for (float x : value) {
        if (!std::isfinite(x)) return false;
        norm += double(x) * x;
    }
    if (norm < 1e-12 || !std::isfinite(norm)) return false;
    norm = std::sqrt(norm);
    for (float &x : value) x = float(x / norm);
    return true;
}
double cosine(const Embedding &a, const Embedding &b) {
    double sum = 0, na = 0, nb = 0;
    for (size_t i = 0; i < a.size(); ++i) {
        if (!std::isfinite(a[i]) || !std::isfinite(b[i])) return -1;
        sum += double(a[i]) * b[i];
        na += double(a[i]) * a[i]; nb += double(b[i]) * b[i];
    }
    if (na < 1e-12 || nb < 1e-12) return -1;
    return std::clamp(sum / std::sqrt(na * nb), -1.0, 1.0);
}
void Gate::lose() { stage_ = Stage::acquire; count_ = 0; first_ = 0; last_ = -1; }
void Gate::reset(double now, int direction) {
    lose(); started_ = now; direction_ = direction < 0 ? -1 : 1;
}
bool Gate::observe(const Observation &f, double now) {
    if (stage_ == Stage::passed) return false; // A result can only be consumed once.
    if (!std::isfinite(now) || !std::isfinite(f.captured) ||
        !std::isfinite(f.score) || !std::isfinite(f.pose) ||
        !std::isfinite(f.facePixels) || f.faces != 1 ||
        f.score < matchThreshold || f.facePixels < 120 ||
        now < f.captured || now - f.captured > 0.35 ||
        now < started_ || now - started_ > 12) {
        lose(); return false;
    }
    // Reject repeated/out-of-order frames, and require continuity after a dropped camera stream.
    if (last_ >= 0 && f.captured <= last_) { lose(); return false; }
    if (last_ >= 0 && f.captured - last_ > 0.45) lose();
    last_ = f.captured;
    bool qualifies = stage_ == Stage::turn ? f.pose * direction_ > 0.16 : std::abs(f.pose) < 0.10;
    if (!qualifies) { count_ = 0; first_ = 0; return false; }
    if (count_++ == 0) first_ = f.captured;
    if (count_ < 3 || f.captured - first_ < 0.20) return false;
    count_ = 0;
    if (stage_ == Stage::acquire) stage_ = Stage::turn;
    else if (stage_ == Stage::turn) stage_ = Stage::center;
    else { stage_ = Stage::passed; return true; }
    return false;
}
bool canSubmit(const UnlockEvidence &e) {
    return e.optedIn && e.sameOSBuild && e.sameAppBuild && e.locked && e.currentUser &&
        e.onConsole && e.loginComplete && e.trustedTarget && e.secureField &&
        e.emptyField && e.userLabel && e.accessibility && !e.alreadyAttempted &&
        std::isfinite(e.matchAge) && e.matchAge >= 0 && e.matchAge <= 0.35;
}
}
