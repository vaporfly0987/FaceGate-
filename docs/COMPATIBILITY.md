# Compatibility

Target architecture: Intel x86_64. Deployment target: macOS 14.0.
This table records evidence, not an assumption based on the minimum deployment target.

| Environment | Build evidence supplied here | Enrollment / recognition | Real lock-screen unlock |
| --- | --- | --- | --- |
| Linux x86_64 | Portable C++ decision tests and Python packaging tests | Not applicable | Not applicable |
| Intel macOS 14 Sonoma | No native build run in the creation environment | Hardware test required | Unverified; may be blocked |
| Intel macOS 15 | GitHub build workflow provided, not executed here | Hardware test required | Unverified; may be blocked |
| Intel macOS 26 | GitHub build workflow provided, not executed here | Hardware test required | Unverified; may be blocked |
| Intel-compatible developer beta | Manual self-hosted workflow provided | Test every build | Unverified; explicit opt-in resets after OS updates |
| Apple silicon | Initial installer intentionally rejects it | Not a supported target | Not a supported target |
| OS releases without Intel support | Cannot run | Cannot run | Cannot run |

GitHub's [runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
lists `macos-15-intel` and `macos-26-intel`. macOS 14 cloud runners currently use
Apple silicon, so they cannot establish Intel Sonoma hardware compatibility.

Always distinguish:

1. A successful compile against an SDK.
2. An executable actually launching on the target OS with compatible dependencies.
3. Camera permission, Keychain and recognition functioning in a desktop session.
4. Camera access and the necessary session/UI evidence remaining available while locked.
5. macOS actually accepting the credential submission and unlocking the session.

Only item 5 establishes that automatic unlock works on a particular hardware/OS
combination. Cloud CI without a real camera and interactive lock screen does not
establish items 3–5. A 14.0 deployment target does not make libraries built for
newer versions run on Sonoma; build against dependencies installed on that Mac.
