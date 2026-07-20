# Building this fork for a physical device under your own Apple Developer team

This fork's Simulator build works out of the box (ad-hoc signed, no team
required). Getting it onto a **physical device** under an Apple Developer
team other than DuckDuckGo's requires a few overrides, because every bundle
identifier and app-group identifier in the committed project is
DuckDuckGo-owned and globally unique — no other team can provision them
under their own names.

This doc assumes a **paid** Apple Developer Program membership. A paid team
can self-provision every capability this app declares (Network Extension /
VPN, AutoFill Credential Provider, SiriKit, App Groups, Keychain Sharing) —
no Apple approval needed for any of those. Only two entitlements
(`com.apple.developer.web-browser` and
`com.apple.developer.browser.app-installation`, both used solely for the
"Set as Default Browser" flow) require an Apple-granted restricted
entitlement and have been removed from this fork's `DuckDuckGo.entitlements`
for that reason — everything else, including the VPN and AutoFill
extensions, stays enabled.

## 1. Create `iOS/LocalOverrides.xcconfig`

This file is git-ignored (`iOS/.gitignore`) and already `#include?`'d last by
every `iOS/Configuration/Configuration*.xcconfig` variant, so it always wins
over the project's defaults:

```
DEVELOPMENT_TEAM = <YOUR_TEAM_ID>
CODE_SIGN_STYLE = Automatic
APP_ID = <your-reverse-dns>.DuckDuckGo
GROUP_ID_PREFIX = group.<your-reverse-dns>.duckduckgo
VPN_APP_GROUP = $(GROUP_ID_PREFIX).netp
```

**Why not `ExternalDeveloper.xcconfig`?** That file (documented in the root
[`README.md`](../README.md)) is included *before* `Configuration.xcconfig`
re-sets `GROUP_ID_PREFIX` inline, so anything you put there for
`GROUP_ID_PREFIX` gets silently overwritten. `LocalOverrides.xcconfig` is
included *after* that reassignment, so it's the only file that reliably wins
for `GROUP_ID_PREFIX`. Use `ExternalDeveloper.xcconfig` for
`DEVELOPMENT_TEAM`/`APP_ID` if you prefer (both work there too), or put
everything in `LocalOverrides.xcconfig` as above — either way, `GROUP_ID_PREFIX`
must go in `LocalOverrides.xcconfig`.

**Why rename `GROUP_ID_PREFIX` at all?** App Group IDs are a namespace Apple
enforces globally, not per-team — `group.com.duckduckgo.*` is registered to
DuckDuckGo's team and no other team can create groups under that prefix.

## 2. Register your device

Xcode → Devices and Simulators (or the Developer portal) → add your device's
UDID under your team.

## 3. Open the workspace and select your device

Open `DuckDuckGo.xcworkspace`, choose the **iOS Browser** scheme, and select
your device as the run destination. With the override above active, Xcode's
automatic signing manager will:

- Create an "Apple Development" certificate for your team, if you don't
  already have one.
- Register the App IDs for the app and every extension it embeds (`<APP_ID>`,
  `<APP_ID>.NetworkExtension`, `<APP_ID>.CredentialExtension`,
  `<APP_ID>.Widgets`, `<APP_ID>.ShareExtension`, `<APP_ID>.OpenAction2`) with
  the capabilities each declares.
- Register the `group.<your-reverse-dns>.duckduckgo.*` App Groups and add
  them to each App ID.

If any App Group fails to auto-register (this can happen the first time),
create it manually in the Developer portal and add it to each App ID that
references it, then retry.

## 4. Run

Run to your device from Xcode (Debug configuration), or from the command
line:

```
xcodebuild -workspace DuckDuckGo.xcworkspace -scheme "iOS Browser" \
  -destination 'platform=iOS,name=<your device name>' \
  -allowProvisioningUpdates
```

For an installable build outside Xcode, archive and export a Development
build, then install with `xcrun devicectl device install app`.

## Acceptance check

- The app launches on your device.
- Onboarding completes.
- You can load a URL and open/close tabs.

## Known limitation

"Set as Default Browser" won't do anything — the entitlements it needs
(`web-browser`, `browser.app-installation`) are Apple-approval-gated and have
been removed from this fork's entitlements (see `DuckDuckGo.entitlements`).
This degrades gracefully; every call site that checks default-browser status
is wrapped in a throwing/`Result`-based check, so nothing crashes. If you're
ever granted those entitlements for your own App ID, restore both keys to
`iOS/DuckDuckGo/DuckDuckGo.entitlements`.
