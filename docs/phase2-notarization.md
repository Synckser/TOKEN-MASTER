# Phase 2 — signing, notarization, distribution (not done this session)

v1 ships as an **unsigned local build**. To distribute it so other Macs run it
without Gatekeeper blocking, do the following. Requires an Apple Developer Program
membership and a **Developer ID Application** certificate.

## 1. Sign (Developer ID, hardened runtime)
Set the signing identity in `project.yml` (replace the ad-hoc `-`):

```yaml
settings:
  base:
    CODE_SIGN_IDENTITY: "Developer ID Application: Your Name (TEAMID)"
    CODE_SIGNING_REQUIRED: "YES"
    CODE_SIGNING_ALLOWED: "YES"
    ENABLE_HARDENED_RUNTIME: "YES"
    DEVELOPMENT_TEAM: "TEAMID"
```

Keep the app **non-sandboxed** (`com.apple.security.app-sandbox: false`) — it needs
to read `~/.claude` and `~/.codex`. Then:

```sh
xcodegen generate
xcodebuild -project TokenMaster.xcodeproj -scheme TokenMaster \
  -configuration Release -derivedDataPath build build
codesign --verify --deep --strict --verbose=2 \
  build/Build/Products/Release/TokenMaster.app
```

## 2. Notarize
Store credentials once (app-specific password or App Store Connect API key):

```sh
xcrun notarytool store-credentials TM-NOTARY \
  --apple-id "you@example.com" --team-id TEAMID --password "app-specific-pw"
```

Zip, submit, wait, staple:

```sh
ditto -c -k --keepParent build/Build/Products/Release/TokenMaster.app TokenMaster.zip
xcrun notarytool submit TokenMaster.zip --keychain-profile TM-NOTARY --wait
xcrun stapler staple build/Build/Products/Release/TokenMaster.app
```

## 3. DMG
Build a distributable disk image (e.g. `create-dmg`):

```sh
brew install create-dmg
create-dmg --volname "TOKEN MASTER" --app-drop-link 480 170 \
  TokenMaster.dmg build/Build/Products/Release/TokenMaster.app
xcrun stapler staple TokenMaster.dmg   # staple the DMG too
```

## 4. Auto-update (Sparkle)
Add the Sparkle SPM package, an `SUFeedURL` + EdDSA public key in Info.plist, host
an `appcast.xml`, sign each update with the Sparkle EdDSA private key. Wire an
"Check for updates" item into the popover/Settings.

## 5. App Store (investigation, later)
The App Store requires sandboxing, which blocks reading `~/.claude` / `~/.codex`
directly. Options to investigate:
- A user-selected security-scoped bookmark (user grants the folders once).
- A privileged helper / `SMAppService` daemon outside the app sandbox.
- Ship App Store as a reduced-feature build, keep the full app on direct download.

## Notes
- First unsigned launch: right-click → Open, or clear quarantine:
  `xattr -dr com.apple.quarantine TokenMaster.app`.
- If a future protected path needs Full Disk Access, prompt the user and open
  System Settings → Privacy & Security → Full Disk Access.
