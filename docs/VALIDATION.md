# Intel Mac validation

Use a test account on hardware you own. Keep normal password entry available.
Do not upload camera frames, your password, or your face embedding as test artifacts.
No real Mac validation was performed in the Linux creation environment.

## Record each tested configuration

| Field | Value to record |
| --- | --- |
| Mac model / CPU | e.g. Intel MacBook model and year |
| OS | Product version and exact `sw_vers -buildVersion` |
| App | Version and `facegate doctor` code hash |
| Build dependencies | Xcode/Command Line Tools, Homebrew, OpenCV versions |
| Camera | Built-in camera model, ambient lighting |
| Recognition timing | Median/p95 from first fresh frame to passed motion sequence |
| Unlock timing | Median/p95 from wake to actual desktop, separate from recognition |
| Resource use | CPU and memory awake/unlocked, locked, and warm-camera mode |
| Results | Pass/fail for each gate below; observed limitation message |

## Build and package gates

- Run `bash scripts/test.sh`, then `bash scripts/build.sh` on the Intel Mac.
- Verify the output is x86_64, has a 14.0 minimum deployment target, and passes
  `codesign --verify --strict build/FaceGate.app`.
- Run the local Homebrew installer from an extracted archive with spaces in its
  parent path. Check the installed CLI and app resources.
- Run `brew test local/facegate/facegate` and `facegate doctor`.
- Confirm uninstall/reinstall behavior and explicitly delete saved Keychain entries
  when testing removal. Homebrew removal does not automatically erase the data.

## Recognition and setup

- Deny then grant camera access; confirm clear status and recovery.
- Enroll, cancel enrollment, replace enrollment, and verify new enrollment disables
  experimental submission until a new recognition test passes.
- Try darkness, glare, glasses, oblique positions, multiple faces, absence, and
  another consenting test person. Record false accepts and false rejects.
- Try a static printed image and recorded video of the enrolled user. Treat any
  acceptance as a failure of the convenience system, not as a successful liveness test.
- Interrupt the camera and suspend/resume between motion stages. No prior stage
  may be carried through a missing/mismatching face or stale frame.
- Confirm cancelled or failed local authentication does not replace enrollment
  or enable experimental unlock.

## Background operation

- Quit the standalone instance, start `brew services`, and verify exactly one app
  process, a visible FG menu item, and restart after a crash.
- Lock, sleep, wake, disconnect power, and switch active sessions. Confirm capture
  stops when appropriate and no old match survives sleep or an interruption.
- Confirm warm mode keeps capture running only while awake in the active user session.
- Check camera contention with a video-call app. Failure must stop recognition and
  retain password fallback.
- After reboot, sign in normally and confirm the service starts. Do not expect
  FaceGate to run at FileVault preboot or at the first login.

## Experimental unlock

- Start with recognition-only mode, then authorize experimental setup and grant
  Accessibility permission. The entered password is locally verified before saving.
- On an awake lock screen for the same user, confirm whether fresh camera frames
  continue and the Apple process, secure field and account-label guards succeed.
- If the target is unavailable, record that this OS build is **not supported by
  the current backend**. Do not remove guards merely to get keystrokes through.
- Confirm the matched face alone does not cause any input into a desktop app.
- Test partially filled password fields, manual unlock during recognition, and
  an unavailable/locked Keychain. Submission must be refused when evidence is absent.
- Change the account password and verify a stale saved credential produces at most
  one attempt. No automatic retry until an active desktop is observed again.
- Crash the app after a recorded attempt and confirm restart cannot loop submissions.
- Verify actual desktop access after successful input; the status text deliberately
  reports an attempt rather than claiming successful OS authentication.
- Run these checks again after every OS/app update. There is no beta allowlist
  that substitutes for a live test.

Fast User Switching, multiple accounts, custom login interfaces, remote sessions,
and external/virtual cameras are not supported by the initial backend.
