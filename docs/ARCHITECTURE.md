# Architecture

## Runtime

The Cocoa menu-bar app owns AVFoundation camera permission and capture, OpenCV
inference, enrollment, the motion/match state machine, and Keychain access in one
process. A Homebrew-generated user LaunchAgent keeps that process running after
normal login. There is no root daemon, IPC authentication service, remote API,
or external recognition executable.

| Component | Responsibility |
| --- | --- |
| `src/App.mm` | App lifecycle, setup UI, current-session monitoring, sleep/recovery, capture and challenge prompts |
| `src/Recognizer.cpp` | YuNet detection, quality checks, alignment, normalized 128-dimensional SFace embedding |
| `src/Gate.cpp` | Pure decision state: continuous match, random-direction motion, freshness, one-shot result, input guard conjunction |
| `src/MacSecurity.mm` | Local Keychain records, local account password verification, session evidence, Apple signature and AX field checks, targeted input |
| `packaging/facegate.rb.in` | Native Homebrew build, model resources, CLI wrapper and user background service |

## Timing and cancellation

Capture and inference share one serial queue. Recognition is capped to 10 frames
per second, with late AVFoundation buffers discarded and at most one pending UI
result. A generation counter cancels results when enrollment, recognition, lock
state, sleep, or camera state changes. Sample timestamps are converted from the
capture session clock into the host clock and must remain fresh.

The main queue owns enrollment and recognition state. The enrolled template is
compared on that queue, so template changes cannot race an inference read. Model
objects are accessed only on the serial capture queue. Camera start/stop runs off
the UI thread. Preview is hidden while locked.

Three matching frames spanning at least 0.20 seconds are required for each phase:
centered acquisition, the randomly chosen turn, and centered return. A face mismatch,
multiple faces, invalid data, stale/repeated sample, or long frame gap invalidates
the sequence. These are convenience checks, not a cryptographic biometric protocol.

## Platform boundary

LocalAuthentication is used only to authorize setup and deletion. It does not turn
a SFace match into a successful OS authentication. The experimental adapter obtains
the previously enrolled user's password from Keychain and requests PID-targeted
keyboard input. All checks must pass and the OS may still reject it.

The lock-state dictionary key and the actual accessibility shape of loginwindow
are version-dependent. The normal system lock screen is always the authority.
There is no app-drawn lock-screen overlay, alternate desktop lock, or fictitious
`unlockSession()` implementation that claims to unlock macOS.

## Primary references

- [Apple LocalAuthentication](https://developer.apple.com/documentation/localauthentication)
- [Apple camera authorization](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media)
- [Apple session dictionary](https://developer.apple.com/documentation/coregraphics/cgsessioncopycurrentdictionary())
- [Apple PID-targeted events](https://developer.apple.com/documentation/coregraphics/cgevent/posttopid(_:))
- [Apple Running at Login](https://developer.apple.com/library/archive/technotes/tn2228/_index.html)
- [OpenCV SFace model and license](https://github.com/opencv/opencv_zoo/tree/47534e27c9851bb1128ccc0102f1145e27f23f98/models/face_recognition_sface)
- [Homebrew formula and service definitions](https://docs.brew.sh/Formula-Cookbook)

The model commit and SHA-256 digests are pinned in `models/manifest.json`. Network
access is needed to download dependencies/models during installation, not for
recognition. Included third-party license texts preserve their upstream terms.
