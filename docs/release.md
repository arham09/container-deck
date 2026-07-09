# Release Guide

## Packaging

`scripts/package-release.sh` builds a release binary, assembles
`ContainerDeck.app`, signs it, and produces a DMG.

```bash
scripts/package-release.sh                      # ad-hoc signed DMG (local use)
DEVELOPER_ID="Developer ID Application: You (TEAMID)" \
  scripts/package-release.sh                    # Developer ID signed
```

## Signing & notarization (requires an Apple Developer account)

1. Sign with your Developer ID certificate (the script uses `$DEVELOPER_ID`
   when set; otherwise ad-hoc, which only runs on the building machine
   without Gatekeeper warnings suppressed).
2. Notarize and staple:

```bash
xcrun notarytool submit .build/ContainerDeck.dmg \
  --keychain-profile "containerdeck-notary" --wait
xcrun stapler staple .build/ContainerDeck.dmg
```

Store credentials once with
`xcrun notarytool store-credentials containerdeck-notary --apple-id … --team-id … --password <app-specific>`.

Hardened Runtime note: the SwiftPM-built binary is signed with
`--options runtime` when `$DEVELOPER_ID` is set. ContainerDeck needs no
entitlements beyond the defaults (no sandbox in this beta; it launches the
user-installed `container` CLI and reads no protected data). The
`NSAppleEventsUsageDescription` in Info.plist covers the optional
Terminal/iTerm2 automation.

## Homebrew Cask (template)

```ruby
cask "containerdeck" do
  version "1.0.1"
  sha256 "<sha256 of the DMG>"
  url "https://github.com/<you>/container-deck/releases/download/v#{version}/ContainerDeck.dmg"
  name "ContainerDeck"
  desc "Native macOS control center for Apple Container"
  homepage "https://github.com/<you>/container-deck"
  depends_on macos: ">= :sequoia"
  depends_on arch: :arm64
  app "ContainerDeck.app"
end
```

## Release checklist

- [ ] `scripts/test.sh` — full suite green, zero warnings
- [ ] Opt-in real integration tests pass (`RealLifecycle`, `RealContainer`, `RealImage`)
- [ ] `scripts/package-release.sh` with `$DEVELOPER_ID` set
- [ ] Notarize + staple; `spctl -a -vv ContainerDeck.app` passes
- [ ] Fresh-machine check: launch without Apple Container installed → onboarding guidance appears
- [ ] Fresh-machine check: with Apple Container → Turn On, run a container, logs, Turn Off
- [ ] Quit during a log follow → `pgrep -f "container logs"` finds nothing
- [ ] Diagnostics export contains no secrets (search for env values)
- [ ] Update version in `scripts/make-app-bundle.sh` and the cask; tag the release
