#include "Gate.hpp"
#include <iostream>
#include <limits>
#include <stdexcept>
#include <vector>

static int checks = 0;
static void check(bool value, const char *description) {
    ++checks;
    if (!value) throw std::runtime_error(description);
}
static fg::Observation frame(double t, double pose = 0) { return {1, 0.8, pose, 160, t}; }
static bool sequence(fg::Gate &g, double start, int direction = 1) {
    bool passed = false;
    for (int i = 0; i < 12; ++i) {
        double t = start + i * 0.12;
        double pose = i < 4 ? 0 : i < 8 ? direction * 0.25 : 0;
        passed = g.observe(frame(t, pose), t) || passed;
    }
    return passed;
}
int main() {
    try {
        fg::Embedding a{}, b{};
        check(!fg::normalize(a), "zero embedding must fail");
        a[0] = 1; b[1] = 1;
        check(fg::cosine(a, b) == 0, "different vectors");
        check(fg::cosine(a, a) == 1, "identical vectors");
        b[2] = std::numeric_limits<float>::quiet_NaN();
        check(fg::cosine(a, b) == -1 && !fg::normalize(b), "NaN embedding must fail");
        for (int direction : {-1, 1}) {
            fg::Gate g; g.reset(0, direction);
            check(sequence(g, 0, direction), "fresh matching motion sequence should pass");
            check(!g.observe(frame(2), 2), "match must be one-shot");
            g.reset(0, direction);
            check(!sequence(g, 0, -direction), "wrong motion direction must fail");
        }
        fg::Gate g; g.reset(0, 1);
        bool passed = false;
        for (int i = 0; i < 90; ++i) passed |= g.observe(frame(i * .1), i * .1);
        check(!passed, "stationary face cannot complete motion check");
        for (int bad = 0; bad < 9; ++bad) {
            g.reset(0, 1);
            for (int i = 0; i < 4; ++i) g.observe(frame(i * .12), i * .12);
            auto f = frame(.5, .3);
            if (bad == 0) f.faces = 2;
            if (bad == 1) f.score = .54;
            if (bad == 2) f.facePixels = 80;
            if (bad == 3) f.captured = 0;
            if (bad == 4) f.captured = 1;
            if (bad == 5) f.pose = NAN;
            if (bad == 6) f.faces = 0;
            if (bad == 7) f.score = NAN;
            if (bad == 8) f.facePixels = INFINITY;
            check(!g.observe(f, .5), "bad frame cannot pass");
            check(g.stage() == fg::Stage::acquire, "bad frame must reset continuity");
        }
        g.reset(0, 1);
        g.observe(frame(.2), .2); g.observe(frame(.2), .2);
        check(g.stage() == fg::Stage::acquire, "replayed timestamp cannot advance");
        g.reset(0, 1);
        for (int i = 0; i < 4; ++i) g.observe(frame(i * .12), i * .12);
        g.observe(frame(2, .3), 2);
        check(g.stage() == fg::Stage::acquire, "camera interruption must reset motion");
        g.reset(0, 1);
        check(!sequence(g, 13), "expired challenge cannot pass");
        fg::UnlockEvidence e;
        e.optedIn = e.sameOSBuild = e.sameAppBuild = e.locked = e.currentUser = true;
        e.onConsole = e.loginComplete = e.trustedTarget = e.secureField = true;
        e.emptyField = e.userLabel = e.accessibility = true;
        e.alreadyAttempted = false; e.matchAge = .1;
        check(fg::canSubmit(e), "all evidence permits one attempt");
        std::vector<bool fg::UnlockEvidence::*> requirements = {
            &fg::UnlockEvidence::optedIn, &fg::UnlockEvidence::sameOSBuild, &fg::UnlockEvidence::sameAppBuild,
            &fg::UnlockEvidence::locked, &fg::UnlockEvidence::currentUser, &fg::UnlockEvidence::onConsole,
            &fg::UnlockEvidence::loginComplete, &fg::UnlockEvidence::trustedTarget, &fg::UnlockEvidence::secureField,
            &fg::UnlockEvidence::emptyField, &fg::UnlockEvidence::userLabel, &fg::UnlockEvidence::accessibility};
        for (auto member : requirements) {
            auto bad = e; bad.*member = false;
            check(!fg::canSubmit(bad), "every unlock guard is required");
        }
        auto attempted = e; attempted.alreadyAttempted = true;
        check(!fg::canSubmit(attempted), "already submitted is denied");
        for (double age : {-1., .36, double(INFINITY), double(NAN)}) {
            auto bad = e; bad.matchAge = age;
            check(!fg::canSubmit(bad), "invalid or stale match is denied");
        }
        std::cout << checks << " checks passed\n";
    } catch (const std::exception &e) { std::cerr << e.what() << '\n'; return 1; }
}
