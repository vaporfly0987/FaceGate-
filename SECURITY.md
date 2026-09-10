# Security model

FaceGate is an experimental local convenience tool for one consenting account
owner. It is not a security-reviewed replacement for Mac authentication.

## Data and boundaries

- Camera frames are processed in memory. The application does not record frames,
  transmit biometrics, expose a network listener, or use cloud identification.
- The owner template and optional login password are stored as separate entries
  in the local macOS Keychain. The template is biometric data, not an anonymized hash.
- The default macOS Keychain ACL is used. No `security` shell command, command-line
  password argument, clipboard, world-readable password file, or global keystroke
  broadcast is used. Keychain retrieval while locked forbids UI interaction.
- Passwords necessarily enter process memory during setup and submission. Temporary
  UTF-16 buffers are cleared; Cocoa string/event copies are not guaranteed erasable.
- Anyone able to replace the executable, alter the running user process, or obtain
  that account's Keychain contents is outside this prototype's protection boundary.
  Default Homebrew installs and ad-hoc signing do not create a hardened trust root.
- A saved password can become stale. A failed attempt falls back to ordinary entry;
  it cannot distinguish a rejected password from macOS ignoring synthetic input.

## Recognition limitations

SFace performs actual face-embedding comparison. YuNet detects faces and five
landmarks. Face quality checks reject small, poorly lit, and very blurry crops.
The app requires one face, consecutive matches, a random direction of head motion,
and a return to center. Any mismatch, multiple faces, stale frame, interruption,
or expired challenge resets the sequence.

The head-turn check measures 2D landmark geometry. It is **not robust liveness**.
Photos moved or distorted in front of a camera, a video display, masks, similar
faces, or camera-path manipulation may defeat it. There is no trained presentation
attack detector, secure camera attestation, infrared/depth sensor, or Secure Enclave
binding. The 0.55 cosine threshold is not calibrated for this installation and no
population-wide false-acceptance or demographic performance claim is made.

## Unlock assistance

Submission is off by default and must be authorized locally. The original password
is verified through Open Directory before storage. Enrollment and setup use
LocalAuthentication. A recognition test must pass on the current app/OS build.

Every submission requires a known locked session belonging to the current console
user, completed login, an Apple-signed foreground loginwindow/SecurityAgent process,
a focused secure text field that is empty, and an account label in that field's
window. These checks may fail on real macOS lock screens. The code targets the
verified process PID, but UI state can change between inspection and event handling;
the checks cannot provide atomicity or the guarantees of an OS authentication API.
PID-targeted events can still be ignored or delivered to a changed field within the
same Apple process. This residual race is part of why the backend is experimental.

One attempt is recorded before password retrieval and is persisted across a restart
of the app. A normal active desktop must be observed to reset the budget. Unknown
lock state never permits submission. Current implementation does not cover multiple
accounts, Fast User Switching, remote sessions, or custom login UI; do not treat
those as supported configurations. System password policies remain authoritative.

An Authorization Services plug-in is not included. Integrating one requires a
separate security architecture, privileged installation/recovery design, and
per-version testing; it is not interchangeable with a normal app biometric check.

## Reporting

For ordinary bugs, use the repository issue template without credentials, photos,
face templates, or personally identifying logs. Before public distribution, the
repository owner should enable GitHub private vulnerability reporting and use it
for findings that could expose credentials or cause unauthorized access.
