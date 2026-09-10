# Releasing on GitHub and Homebrew

The source archive is ready to become a GitHub repository, but no repository or
public tap has been created for you. Replace example account names with your own.

## Source release

1. Put the source into a repository you own, enable private vulnerability reporting,
   and run the CI workflow. Fix native build errors and record hardware validation
   before claiming any OS is supported for automatic unlock.
2. Tag the reviewed source `v0.1.0`.
3. Run **Prepare source release** from that tag or generate the files locally:

```bash
python3 scripts/package.py
python3 scripts/make_formula.py \
  --archive dist/facegate-0.1.0.tar.gz \
  --repository YOUR_GITHUB_ACCOUNT/facegate \
  --output dist/facegate.rb
```

4. Create GitHub release `v0.1.0` and upload exactly
   `dist/facegate-0.1.0.tar.gz`. The formula hashes this release attachment, not
   GitHub's automatically generated source archive.
5. Create repository `YOUR_GITHUB_ACCOUNT/homebrew-facegate`; copy the generated
   formula into `Formula/facegate.rb`, commit it, and push it.
6. Test from a fresh Intel Mac with:

```bash
brew tap YOUR_GITHUB_ACCOUNT/facegate
brew install YOUR_GITHUB_ACCOUNT/facegate/facegate
brew test YOUR_GITHUB_ACCOUNT/facegate/facegate
facegate
```

For later versions, update the CMake project version, Info.plist-generated values,
CLI version, Homebrew template version, package/release names in scripts, version
assertions and docs together. Generate a new checksum from the exact new attachment.
Never reuse a release URL with different bytes. Model updates must update both
the manifest and the CMake verification digests, with the model/template version
changed so users re-enroll.

## Local tap

`scripts/install-homebrew.sh` is usable before publication. It creates
`local/facegate`, stores a source tarball under the tap's `vendor` directory, and
generates a formula with a `file://` source URL and the archive's actual SHA-256.
The formula downloads its two model resources from the pinned official model commit.
Local taps contain machine-specific paths; publish a separately generated remote
formula, not the local one.

## Signing and distributing binaries

The build is ad-hoc signed for local Homebrew use. Rebuilds can change its code
identity and trigger Keychain/camera/Accessibility permission prompts. App code
hash changes disable experimental unlock and require retesting.

CI app ZIPs are debugging artifacts linked to that runner's Homebrew dependencies.
**They are not standalone portable or notarized Mac installers.** The Homebrew
source-build route is the distribution method implemented here.

A consumer-ready prebuilt cask would additionally require bundling and signing
all native dependencies, auditing their licenses and minimum OS versions, applying
a stable Developer ID signature and suitable hardened-runtime entitlements,
notarizing/stapling the distribution, and testing on clean Macs. Do not advertise
that as completed. Do not globally disable Gatekeeper, SIP or library validation
as an installation step.

The beta workflow is manual and targets an isolated, owner-controlled Intel Mac
with self-hosted labels `macOS`, `X64`, and `facegate-beta`. Do not run untrusted
pull requests on a personal Mac through a self-hosted runner.
