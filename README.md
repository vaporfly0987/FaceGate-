# FaceGate

Local webcam face recognition for **Intel Macs targeting macOS 14 or newer**, with
a menu-bar app, a Homebrew background service, and an **experimental** password-assisted
screen-unlock option. The app uses native AVFoundation capture and OpenCV YuNet/SFace.

**Status: prototype, not a validated lock-screen authentication product.**
The portable decision logic and packaging are testable on Linux. The native macOS
application, camera permissions, Homebrew installation, and actual lock-screen
submission require validation on an Intel Mac. Developer-beta support is a test
target, not a guarantee. No release is published to GitHub or Homebrew by this archive.

## What it does

- Enrolls the current user's face after macOS owner authentication.
- Stores a face embedding in the local macOS Keychain; saves no camera photos/video.
- Matches locally with a pretrained face-recognition model, with no cloud inference.
- Requires a continuous match and a randomized head turn followed by facing forward.
- Runs in the menu bar and, through `brew services`, starts after login and restarts
after a process exit. It suspends capture for sleep and inactive user sessions.
- Offers an optional warm-camera mode to reduce start latency. The camera light
remains on in this mode; it increases power usage.
- Defaults to recognition-only mode. Password assistance requires separate setup.

## macOS limitations you need to know

Apple's [LocalAuthentication framework](https://developer.apple.com/documentation/localauthentication)
authenticates actions within apps; it does not register a third-party webcam matcher
as system Face ID. This project does not provide a system biometric provider.

Experimental unlock stores **your existing Mac password** in your local Keychain,
then attempts to submit it to a positively identified Apple lock-screen process.
This is not equivalent to FileVault unlock, Secure Enclave-backed biometrics, or a
new authentication factor. The OS lock screen remains authoritative and may ignore
or reject the synthetic input.

The experimental path is disabled until explicitly configured. The setup checks the
current password through Open Directory and stores it only in the user's Keychain.
The recognition path still requires a fresh face match and a random motion challenge.

## Requirements

- Intel Mac
- macOS 14 Sonoma or newer
- Xcode Command Line Tools
- Homebrew
- `cmake`, `opencv`, and Python 3 for the model downloader
- A built-in or compatible webcam

Apple Silicon is intentionally rejected by the build because the project is currently
an Intel-only experiment.

## Installation

This repository contains the source and the Homebrew formula template, not a live
Homebrew tap. For development:

```bash
brew install cmake opencv
python3 scripts/download_models.py
bash scripts/build.sh
open build/FaceGate.app
```

For a published tap, see [docs/RELEASING.md](docs/RELEASING.md). Do not run the
experimental unlock path on a machine where you cannot recover with the normal
password login.

## Homebrew service

The formula template installs the app under Homebrew and exposes a wrapper that
launches the menu-bar application. `brew services start` runs it as the logged-in
user; it is not a privileged system daemon.

## Privacy

Recognition is local. Frames exist only in process memory, and the enrolled face
is stored as a 128-dimensional embedding in the macOS Keychain. The project does
not include telemetry, a network recognition service, or automatic photo uploads.
The optional password-assisted path necessarily stores the existing account password
in Keychain and handles it in process memory; see [SECURITY.md](SECURITY.md).

## Validation and safety

Run the portable tests before touching a real Mac. The native build verifies the
pinned ONNX model SHA-256 digests. The repository includes a CI workflow for Intel
macOS runners and a separate manually triggered workflow for an isolated self-hosted
beta Mac.

This is **prototype software**. Do not represent a successful recognition match as
proof of identity or a lock-screen submission as a secure OS authentication event.
The included liveness check is a simple motion challenge, not a presentation-attack
detector.

## Project layout

- `src/` — macOS app, security adapter, and recognition implementation
- `include/` — public C++ interfaces
- `tests/` — portable state-machine and vision smoke tests
- `scripts/` — model download, build, test, packaging, and Homebrew generation
- `packaging/` — app bundle metadata and formula template
- `models/manifest.json` — pinned model commit and SHA-256 values
- `docs/` — architecture, compatibility, validation, and release notes

## Releasing

The repository includes a source-only release workflow that creates a deterministic
archive, tests, packaging scripts, and pinned model provenance/licenses.
Push the source to a GitHub repository you own. Nothing here publishes automatically.

The **Prepare source release** workflow creates a deterministic source tarball and
a Homebrew formula using the actual repository name. Download its workflow artifact,
create release `v0.1.0`, and upload **that exact** `facegate-0.1.0.tar.gz` file.
Copy its generated `facegate.rb` into `Formula/facegate.rb` in a repository named
`homebrew-facegate` under your GitHub account.

After publishing those files, users can install with:

```bash
# Replace YOUR_GITHUB_ACCOUNT with your real account; this is not a live tap yet.
brew tap YOUR_GITHUB_ACCOUNT/facegate
brew install YOUR_GITHUB_ACCOUNT/facegate/facegate
facegate
```

Then quit the manually opened app and start the background service using your tap's
fully qualified formula name. See [docs/RELEASING.md](docs/RELEASING.md) for local
release generation, signing, and limitations of distributing prebuilt apps.

## Build and test manually

```bash
brew install cmake opencv
bash scripts/build.sh
open build/FaceGate.app
```

Portable tests, including the matching/motion state machine, stale-frame handling,
unlock guards, and archive/formula generation:

```bash
bash scripts/test.sh
```

GitHub CI targets Intel macOS 15 and 26 runners. A separate, manually triggered
workflow supports an isolated self-hosted Intel beta test Mac. macOS 14 hardware
validation must be performed separately. See [architecture](docs/ARCHITECTURE.md).

## Performance

Capture uses a 640×480 preset, a latest-frame-only delegate, a single worker queue,
CPU inference capped to two OpenCV threads, and at most 10 recognition frames per
second. A complete motion sequence requires multiple fresh frames in each phase.
Warm-camera mode avoids camera startup delay. Actual recognition/unlock latency,
CPU usage, battery impact, and accuracy have **not been measured on an Intel Mac**.
