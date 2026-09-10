# Validation performed for this source package

Creation environment: Linux x86_64. Validation date: September 10, 2026.

Completed:

- Compiled the portable C++17 decision code with `-Wall -Wextra -Werror -pedantic`.
- Passed 50 assertions covering normalized embeddings, invalid vectors,
  continuous matching, motion direction, stale/replayed frames, multi-face and
  mismatch rejection, challenge expiry, one-shot results and required submission guards.
- Passed three Python unittest cases covering deterministic archive generation and
  excluded files; local/remote formula generation and interpolation protection;
  and rejection of model bytes with an incorrect checksum.
- Parsed all four GitHub YAML files and the Info.plist template.
- Checked shell syntax for build, test and local Homebrew installer scripts.
- Downloaded both full ONNX models through the included downloader and verified
  their sizes and SHA-256 digests against the pinned upstream Git LFS records.

Not performed:

- Native macOS Objective-C++ compilation or execution.
- Running Homebrew or parsing the generated formula with Homebrew/Ruby.
- OpenCV inference execution or measurement of identity accuracy.
- Camera permission, enrollment, Keychain, background service, sleep/wake or
  Accessibility tests on a Mac.
- Automatic lock-screen unlock or developer-beta tests.
- GitHub Actions execution, repository publication or a public Homebrew release.

These omissions prevent any claim that this is a validated working lock-screen
unlock product. Native build workflows and detailed hardware tests are included
to make the remaining work reproducible. Full model files are deliberately omitted
from the source archive and are downloaded with checksum verification at build time.
