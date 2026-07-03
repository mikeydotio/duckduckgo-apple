# Tech Design: Per-Site Permission Manager on iOS

- **Asana:** [Project task](https://app.asana.com/1/137249556945/project/1215172677539195/task/1213800892997347?focus=true)
- **Designs:** [Figma — Permission iOS/Android](https://www.figma.com/design/aMaDTBcE9Fsfu40NbjzcrH/Permission--iOS-Android-?node-id=380-46782&m=dev)
- **Status:** Final, except the geolocation transport, which is **PROVISIONAL** pending the hack-phase validation (see [Geolocation approach](#geolocation-approach-provisional)).

## Summary

Bring the per-site permission manager (camera, microphone, geolocation) to iOS, using the shipped macOS implementation as the reference. The storage + decision core (`PermissionManager`, `PermissionStore`, the Core Data model, and the decision types) is extracted from the macOS app target into a new **`Permissions` sub-library inside `SharedPackages/BrowserServicesKit`**, alongside `History`, `Bookmarks`, and `PrivacyStats`. WebKit integration, session state, and all UI remain per-platform.

On iOS this powers: a 3-option site prompt (Always Allow / Allow Once / Never Allow) shown **before** the system prompt; a Settings → Permissions page with a per-site allow/deny list, status icons, remove actions, and global "never ask" controls; a recover-from-denied-system-permission flow with a System Settings referral; a granted-permission animation and post-grant toast; a temporary browsing-menu entry point; and retention of permissions for fireproofed sites.

Camera and microphone use the public `WKUIDelegate` media-capture API and are fully committed. iOS `WKWebView` exposes no working geolocation-permission delegate, so per-site geolocation depends on a `navigator.geolocation` JS-interception shim bridging to `CLLocationManager`; the design isolates that transport so camera/mic ship even if geolocation is deferred.

### Deviations from the originally proposed architecture

The proposal was validated against the code; four claims needed correction:

1. **`PermissionState`, the `Permissions` typealias, and `PermissionAuthorizationQuery` do not move to the shared package.** `PermissionAuthorizationQuery` is a typealias over `UserDialogRequest<Info, Output>` (`macOS/DuckDuckGo/Tab/Model/UserDialogRequest.swift`), which is macOS Tab-layer dialog machinery. `PermissionState` imports WebKit and is a session state machine over the app-defined `WKWebView.CaptureState` (`macOS/DuckDuckGo/Common/Extensions/WKWebViewExtension.swift:58`) and holds `.requested(PermissionAuthorizationQuery)`. Both are live-webview/session types, not decision storage. They stay in the macOS app; iOS defines its own (simpler) prompt-request type. Side benefit: the `Permissions` typealias staying app-side avoids a type shadowing the `Permissions` module name in qualified lookups.
2. **The fireproofing seam cannot reuse `DomainFireproofStatusProviding` as claimed.** That protocol exists only in the macOS app (`macOS/DuckDuckGo/Fireproofing/Model/FireproofDomains.swift:25`) and `PermissionManager` doesn't even use it — `burnPermissions(except:)` takes the **concrete** `FireproofDomains` class. Nothing shared exists; iOS has its own unrelated `Fireproofing` protocol (`iOS/Core/Fireproofing.swift:26`, method `isAllowed(fireproofDomain:)`). The package defines its own minimal protocol and both platforms adapt to it.
3. **The settings-deep-link seam (`URLOpener`) is not a core seam.** The shared core never opens URLs; on macOS, System Settings is opened from the views (`NSWorkspace.shared.open` in `PermissionCenterView.swift:376` et al.). URL opening stays in the per-platform UI layer — iOS already has `URLOpener` (`iOS/Core/URLOpener.swift:22`); no protocol is lifted into the package.
4. **The claimed History encryption precedent does not exist as described.** The shared `BrowsingHistory` model stores `title`/`url` as plain `String`/`URI` attributes (the `valueTransformerName` entries on them are vestigial no-ops); macOS's encrypted history uses a **separate app-local legacy model** (`macOS/DuckDuckGo/History/Services/History.xcdatamodeld`) with `Transformable` attributes. `Permissions` will be the first shared model with a `Transformable` attribute that is encrypted on one platform and not the other, so iOS needs an explicit plaintext transformer strategy rather than "no registration" (see [Data model](#data-model--encryption-approach)).

Additionally, the icon seam is revised (icons stay out of the core; see [Seam 1](#seam-1--icons)), and two hidden dependencies in the "portable" layer were found and must be fixed during extraction: `LocalPermissionStore` uses AppKit's `NSObject.className()` (unavailable on iOS), and `StoredPermission.swift` imports `PixelKit` directly (replaced by the event-mapping seam).

## Goals / Non-goals

### Goals

- Per-site camera and microphone permissions on iOS with persisted Always Allow / Never Allow decisions and session-scoped Allow Once, prompted **before** the system prompt.
- Per-site geolocation on iOS via the shim transport, **if** the hack phase validates it.
- Settings → Permissions page: per-site list with status icons, remove-permission actions, global "never ask" controls, System Settings referral, recover-from-denied-system-permission flow.
- Granted-permission animation (omnibar) and post-grant toast; temporary browsing-menu entry point.
- Permissions for fireproofed sites survive data clearing (Fire button / auto-clear).
- One shared storage + decision core used by both platforms, with macOS behavior and persisted data fully preserved (no store migration, no behavior change).
- macOS stays green after every PR.

### Non-goals

- iOS at-rest encryption of the permissions store (v1 stores domains in plaintext, matching iOS History precedent; see risks).
- Bringing popups, notification, external-scheme, or autoplay permission types to iOS (the enum retains those cases for macOS; iOS v1 surfaces only camera/mic/geolocation).
- Porting macOS UI (Permission Center popover, address-bar buttons) — all iOS UI is new, per Figma.
- Changing macOS's private-SPI geolocation transport.
- A Web-standard `navigator.permissions.query()` bridge (follow-up if the shim ships).

## Architecture

### Package home: `Permissions` sub-library in BrowserServicesKit

A new target + product in `SharedPackages/BrowserServicesKit/Package.swift`, at `Sources/Permissions/`, with tests at `Tests/PermissionsTests/`. This matches the **History profile** exactly, which was verified: History is a sibling `.library` product (not part of the `BrowserServicesKit` umbrella target), Foundation/CoreData/Combine only, no UI, no localization, no third-party deps, Core Data model shipped via `.process(...)`, hand-written managed-object classes, per-target test target.

```swift
.library(name: "Permissions", targets: ["Permissions"]),
// ...
.target(
    name: "Permissions",
    dependencies: [
        "Common",        // TLD
        "Persistence",   // CoreDataDatabase
        .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),   // droppingWwwPrefix()
        .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),  // asyncOrNow
    ],
    resources: [.process("CoreData/Permissions.xcdatamodeld")],
    swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
),
.testTarget(name: "PermissionsTests", dependencies: ["Permissions"]),
```

Why not the alternatives:

- **Not a top-level `SharedPackages` package.** Top-level packages carry external deps, UI, or localization (`AIChat` has `defaultLocalization` + DesignResourcesKit; `DataBrokerProtectionCore` has ZIPFoundation/swift-algorithms; `VPN` has WireGuardC). The permissions core has none of that — it is a pure logic+storage leaf like History/Bookmarks/PrivacyStats, all of which live inside BSK.
- **Not the BSK umbrella target.** History/Bookmarks/PrivacyStats are deliberately not in the umbrella; consumers `import Permissions` directly. Same here.
- **Module naming:** `Permissions` matches the domain-noun convention (History, Bookmarks). The macOS `typealias Permissions = [PermissionType: PermissionState]` stays app-side (see Deviations #1), so there is no type/module name collision inside the package. No existing BSK product or target uses the name.

### Shared/platform boundary — every type

**Moves into `SharedPackages/BrowserServicesKit/Sources/Permissions/`** (from `macOS/DuckDuckGo/Permissions/Model/`):

| Type | Notes on the move |
|---|---|
| `PermissionType` | Core enum + `rawValue` codec + `canPersistGrantedDecision`/`canPersistDeniedDecision` only. Drops `import AppKit`/`DesignResourcesKitIcons`/`CommonObjCExtensions`: `icon`/`solidIcon` move to a macOS-side extension (Seam 1); `requiresSystemPermission`, `surfacesSystemDisabledWarning`, and `permissionsUpdatedExternally` move to platform-side extensions because they encode per-platform product policy (e.g. on macOS camera/mic skip the two-step system flow; on iOS the recover-from-denied flow covers camera/mic). All seven cases (incl. `.popups`, `.notification`, `.externalScheme`, `.autoplayPolicy`) move so macOS raw values and stored rows keep working unchanged. |
| `[PermissionType].init?(devices: WKMediaCaptureType)` | Moves as `PermissionType+WKMediaCaptureType.swift` (public WebKit API, identical need on both platforms; WebKit imports exist in BSK precedent, e.g. `Navigation`). The `_WKCaptureDevices` SPI initializer **stays in the macOS app**. |
| `PersistedPermissionDecision`, `StoredPermission`, `PermissionEntity` | `StoredPermission.swift` currently imports `PixelKit` and fires `GeneralPixel.permissionDecryptionFailedUnique` on decode failure — replaced by the event-mapping seam (Seam 3). |
| `PermissionStore` (protocol), `LocalPermissionStore` | Already clean (Common/CoreData/Persistence/Foundation) except `PermissionManagedObject.className()`, which is AppKit-only `NSObject` API — replace with an entity-name constant (History precedent: `NSFetchRequest<...>(entityName: "...")`). Gains an optional `EventMapping` for store/decode errors. |
| `PermissionManager`, `PermissionManagerProtocol`, `PermissionDecisionOverriding` | Portable today (Foundation/Combine/Common/FoundationExtensions; `droppingWwwPrefix()` is in shared `FoundationExtensions`). One signature change: `burnPermissions(except fireproofDomains: FireproofDomains, ...)` → takes the package fireproofing protocol (Seam 2). |
| `SystemPermissionManagerProtocol`, `SystemPermissionAuthorizationState` | Protocol + enum only (Foundation/Combine + `PermissionType` — portable as written). The **concrete** `SystemPermissionManager` stays on macOS (it uses `NSApp.delegateTyped`, PixelKit, the macOS notification service). iOS writes its own concrete for camera/mic/geolocation over `AVCaptureDevice` + `CLLocationManager`. |
| `Permissions.xcdatamodeld` + hand-written `PermissionManagedObject` | See [Data model](#data-model--encryption-approach). |
| `DomainFireproofStatusProviding` (new, package-defined) | Seam 2. |
| `PermissionStoreEvent` (new) | Seam 3. |
| `PermissionManagerMock` | Currently in the macOS app target; both platforms' tests need it. Move into `PermissionsTests` initially; promote to a `PermissionsTestingUtils` product (precedent: `PersistenceTestingUtils`, `BookmarksTestsUtils`) if the app test suites need it. |

**Stays in the macOS app target:**

- `PermissionModel` (the WebKit hub: AVFoundation swizzle, `_WK` SPI delegate handling, KVO on capture states, geolocation provider wiring).
- `PermissionState`, `Permissions` typealias, `PermissionAuthorizationQuery` (+ `UserDialogRequest`) — session/dialog types (Deviations #1).
- Concrete `SystemPermissionManager`, `GeolocationProvider`/`GeolocationService`/`WKProcessPool+GeolocationProvider` (dlsym'd WebKit C SPI), `Tab+UIDelegate` wiring, `DuckAiVoiceChatPermissionOverride`.
- All Views/ViewModels, `PermissionPixel.swift`, `AddressBarPermissionButtonsIconsProviding`, new `PermissionType+Icons.swift` extension.
- `FireproofDomains` + a one-line conformance to the package fireproofing protocol.

**New on iOS (app target first, per History precedent):**

- `PermissionsDatabase` — dedicated `CoreDataDatabase` bootstrapping (mirrors `HistoryManager.swift:255` / `PrivacyStatsDatabase.swift:59`): `CoreDataDatabase.loadModel(from: Permissions.bundle, named: "Permissions")`, own `Permissions.sqlite` in Application Support. Not merged into iOS's app-group "Database" store.
- `SitePermissionsCoordinator` (per-tab, owned by `TabViewController`) — the iOS analog of `PermissionModel`: receives `WKUIDelegate` media-capture requests, consults `PermissionManager`, drives the site prompt, tracks session Allow Once grants, and (provisionally) hosts the geolocation bridge.
- Site prompt UI (SwiftUI sheet, 3 options per Figma), Settings → Permissions page (row in `SettingsPrivacyProtectionsView` + `SettingsDeepLinkSection` case + `navigationDestinationView(for:)`), per-site list with status icons, remove actions, global never-ask controls, recover-from-denied view.
- Omnibar granted animation: new `OmniBarNotificationType` case rendered via the existing `OmniBarNotificationAnimator` pipeline (`iOS/DuckDuckGo/OmniBarNotificationAnimator.swift`), mirroring `cookiePopupManaged`. Post-grant toast via `ActionMessageView`.
- Temporary menu entry in `TabViewControllerMenuBuilderExtension.buildBrowsingMenu` (and mirrored in `BrowsingMenu/SheetPresentationMenu/BrowsingMenuBuilder.swift`), feature-flag-gated.
- iOS concrete `SystemPermissionManager` + `Fireproofing` adapter + pixel `EventMapping` + `FeatureFlag` case (`iOS/Core/FeatureFlag.swift`).
- (Provisional) geolocation shim user script + `CLLocationManager` bridge.

A `iOS/LocalPackages/Permissions-iOS` UI package (precedent: `DataBrokerProtection-iOS`, `SyncUI-iOS`) is the eventual home if the UI grows, but the first cut lives in the app target because the surfaces are tightly coupled to `TabViewController`, the omnibar, and the Settings stack — the same call History made. `macOS/LocalPackages/Permissions-macOS` is **not** created now; macOS UI stays where it is (no benefit to churning shipped UI).

### The four seams

#### Seam 1 — Icons

**Icons stay out of the core.** The original proposal (change `PermissionType.icon` to return `DesignSystemImage`) works mechanically — `DesignSystemImage` is a cross-platform `UIImage`/`NSImage` typealias in `DesignResourcesKitIcons` — but BSK currently has **zero** design-resource dependencies (its only Infrastructure dep is `SystemFrameworksExtensions`), and no BSK sub-library ships images. Adding a BSK → `DesignResourcesKitIcons` edge for two computed properties is dependency creep against clear layering precedent. Instead:

- macOS: `PermissionType+Icons.swift` in the app (verbatim move of the existing `icon`/`solidIcon` bodies).
- iOS: its own `PermissionType+Icons.swift` returning the glyphs/sizes Figma specifies (which may not be the macOS `Size16` set anyway).

If a genuinely shared UI layer emerges later, the extension can live there.

#### Seam 2 — Fireproofing

Package defines the minimal protocol (reusing the established macOS name, now package-owned):

```swift
public protocol DomainFireproofStatusProviding: AnyObject {
    func isFireproof(fireproofDomain: String) -> Bool
}
```

`PermissionManagerProtocol.burnPermissions(except:completion:)` takes this protocol instead of the concrete `FireproofDomains`. macOS: `FireproofDomains` conforms directly (it already has the exact method; its app-local protocol of the same name is superseded for this call path). iOS: a one-line adapter over `Fireproofing` (`isAllowed(fireproofDomain:)`). The eTLD+1 burn overload `burnPermissions(of:tld:)` moves unchanged (`TLD` comes from `Common`).

#### Seam 3 — Pixels / events

Per `.cursor/rules/pixels.mdc`, pixels fired from inside a shared package go through an `EventMapping` enum mapped client-side — the exact History precedent (`EventMapping<History.HistoryDatabaseError>` → `HistoryStoreEventMapper` on iOS, PixelKit on macOS). The package defines:

```swift
public enum PermissionStoreEvent {
    case domainDecryptionFailed   // replaces the direct PixelKit call in StoredPermission.swift
    case storeError(Error)
}
```

`LocalPermissionStore` takes an optional `EventMapping<PermissionStoreEvent>`. macOS maps `domainDecryptionFailed` → the existing `GeneralPixel.permissionDecryptionFailedUnique`; iOS maps to new `Pixel.Event` cases. **Feature pixels stay platform-side**, which matches macOS today: `PermissionModel` fires nothing; the UI layer fires `PermissionPixel` (`authorizationDecision`, `permissionCenterChanged`, `permissionCenterReset`, `systemPreferencesOpened`). iOS defines equivalent `Pixel.Event` cases + JSON5 definitions under `iOS/PixelDefinitions/`, fired from the iOS prompt/settings UI.

#### Seam 4 — System permission state

`SystemPermissionManagerProtocol` + `SystemPermissionAuthorizationState` (incl. `.systemDisabled`, needed for the recover-from-denied flow) live in the package as the shared vocabulary; each platform ships its own concrete. The iOS concrete covers: camera/mic via `AVCaptureDevice.authorizationStatus(for:)` (the recover-from-denied flow reads `.denied`/`.restricted`), geolocation via the `CLLocationManager` service (provisional). Opening System Settings is **not** part of this seam — it is UI (iOS: `URLOpener` + `UIApplication.openSettingsURLString`, precedent `NoMicPermissionAlert.swift:31`; macOS: unchanged `NSWorkspace` calls).

### iOS request flow (camera/mic)

`TabViewController` is already the main web view's `WKUIDelegate` and already implements `webView(_:requestMediaCapturePermissionFor:initiatedByFrame:type:decisionHandler:)` — today it returns `.prompt` for non-Duck.ai origins (`iOS/DuckDuckGo/TabViewController.swift:3517`). New flow, delegated to `SitePermissionsCoordinator`:

1. Map `WKMediaCaptureType` → `[PermissionType]` (shared initializer).
2. Duck.ai carve-out: the existing inline guard becomes a `PermissionDecisionOverriding` conformance injected into `PermissionManager` — the same mechanism macOS uses for `DuckAiVoiceChatPermissionOverride`. Behavior preserved exactly.
3. Global "never ask" for the type → `decisionHandler(.deny)`. Implemented as a second chained `PermissionDecisionOverriding` backed by a `KeyValueStoring` persistor (per `.cursor/rules/user-defaults-storage.mdc`; global toggles are settings, not per-site rows).
4. `PermissionManager.permission(forDomain:permissionType:)`: `.allow` → `.grant`; `.deny` → `.deny`; `.ask` → present the site prompt while holding `decisionHandler`.
5. Site prompt result: **Always Allow** → `setPermission(.allow, …)` + `.grant`; **Allow Once** → `.grant` without persisting (session-scoped, tracked by the coordinator); **Never Allow** → `setPermission(.deny, …)` + `.deny`.
6. Calling `.grant` is what triggers WebKit's app-level TCC prompt (first time only) — the site prompt therefore naturally **precedes** the system prompt, satisfying the reorder requirement without extra machinery.
7. If system permission is already denied (`SystemPermissionManager` reports `.denied`/`.restricted`), skip the site prompt and present the recover flow (explanation + Open Settings via `URLOpener`).
8. On grant: omnibar animation + toast.

## Data model + encryption approach

### Model relocation

`Permissions.xcdatamodeld` moves verbatim from `macOS/DuckDuckGo/Permissions/Model/` to `Sources/Permissions/CoreData/`, declared `.process(...)`. Single entity, unchanged:

| Attribute | Type | Notes |
|---|---|---|
| `domainEncrypted` | Transformable, `valueTransformerName="NSStringTransformer"` | Encrypted on macOS, plaintext-archived on iOS (below) |
| `permissionType` | String | `PermissionType.rawValue` |
| `allow` | Boolean (scalar) | |
| `isRemoved` | Boolean (optional, default NO, scalar) | |

Together `allow`/`isRemoved` encode `PersistedPermissionDecision` via the existing `PermissionManagedObject.decision` extension.

**Codegen ownership changes.** The entity is currently `codeGenerationType="class"` (Xcode-generated in the app target). Package convention (History/Bookmarks/PrivacyStats) is Manual/None + a hand-written class. The move therefore: sets codegen to Manual/None, and adds a hand-written `PermissionManagedObject.swift` in the package declared `@objc(PermissionManagedObject)` (exactly as `@objc(BrowsingHistoryEntryManagedObject)` does), so the runtime class lookup via the model's `representedClassName` keeps resolving after the class changes modules.

**Store compatibility (macOS).** The entity's version hash derives from its structure (name, attributes, types, optionality, defaults), not from file location, module, or codegen mode — so the merged model stays compatible with existing users' `Database.sqlite` and **no migration occurs**, provided the entity XML is byte-identical. This is the highest-consequence invariant of the whole extraction; PR 2 includes a regression test for it (see Testing).

### Encryption + transformer registration

The model keeps `Transformable domainEncrypted` with transformer name `"NSStringTransformer"`. Per-platform:

**macOS (behavior unchanged — encrypted).** Today `Database.init()` (`macOS/DuckDuckGo/Common/Database/Database.swift:63-78`) builds `mergedModel(from: [.main])`, registers `EncryptedValueTransformer<NSString>` et al. over it via `registerValueTransformers(withAllowedPropertyClasses:keyStore:)`, then constructs the `CoreDataDatabase` — all synchronously before any store load (`AppDelegate` line ~536 constructs `Database()`, line ~539 loads the store). Once the model leaves `.main`, `mergedModel(from: [.main])` no longer picks it up, so `Database.init()` changes to:

```swift
let mainModel = NSManagedObjectModel.mergedModel(from: [.main])!
let permissionsModel = CoreDataDatabase.loadModel(from: Permissions.bundle, named: "Permissions")!
let mergedModel = NSManagedObjectModel(byMerging: [mainModel, permissionsModel])!
_ = try mergedModel.registerValueTransformers(withAllowedPropertyClasses: [...], keyStore: keyStore)  // BEFORE store construction, as today
let httpsUpgradeModel = HTTPSUpgrade.managedObjectModel
db = CoreDataDatabase(name: Constants.databaseName, containerLocation: containerLocation,
                      model: .init(byMerging: [mergedModel, httpsUpgradeModel])!)
```

The critical ordering — transformer registration strictly before store load — is preserved by construction because it all lives in `Database.init()`. The registration must run over a model that **includes** the permissions entity (register over the merged model, not `mainModel` alone), otherwise `domainEncrypted` silently loses its transformer.

**iOS (plaintext, v1).** Since History provides no real precedent here (Deviations #4), iOS takes the explicit path: the package ships a trivial pass-through transformer (an `NSSecureUnarchiveFromDataTransformer` subclass allowing `NSString`) plus a `Permissions.registerPlaintextDomainTransformer()` helper; `PermissionsDatabase.make()` calls it **before** `loadStore`. Leaving the name unregistered is not acceptable — Core Data's fallback behavior for a missing named transformer is an undefined/fragile keyed-archiver path that logs warnings and can crash under secure-coding enforcement. With the pass-through, iOS stores the domain as a plain keyed-archived string: well-defined, and upgradable later (moving iOS to `EncryptedValueTransformer` would require porting the key store out of macOS-only `macOS/LocalPackages/Utilities` plus a value-level data migration — explicitly out of scope for v1).

iOS store bootstrap (mirrors `HistoryManager`/`PrivacyStatsDatabase`): dedicated `CoreDataDatabase(name: "Permissions", containerLocation: <app support>, model: loadModel(from: Permissions.bundle, named: "Permissions"))`, wired into DI at app startup behind the feature flag. Note `Permissions.bundle` requires the package to expose its resource bundle the way History does — a module-level `public let bundle = Bundle.module` (see `Sources/History/global.swift`).

## Geolocation approach (PROVISIONAL)

> Everything in this section is pending the hack-phase validation of the JS shim. The rest of the design does not depend on it: `PermissionType.geolocation` exists in the core regardless, and deferral only means iOS hides location rows/prompts in v1.

**Why a shim.** Verified: iOS has no DDG geolocation handling at all today (zero `CLLocationManager`/geolocation code in `iOS/`; sites get WebKit's built-in per-origin prompt backed by the app's location authorization). macOS's transport — a WebKit geolocation provider installed through dlsym'd C SPI (`WKContextGetGeolocationManager`/`WKGeolocationManagerSetProvider` via `WKProcessPool+GeolocationProvider`) plus `_webView:requestGeolocationPermissionForOrigin:...` delegate SPI — is unavailable/non-functional on iOS. The blocker is API availability, not App Review (both macOS distributions ship the same SPI; the shim itself is plain JS + public CoreLocation, so no new review risk).

**Provisional design.**

- A user script injected at document start overrides `navigator.geolocation` (`getCurrentPosition`, `watchPosition`, `clearWatch`) in the page world, forwarding requests over a `WKScriptMessageHandler` bridge with request/watch IDs.
- Native side: a `WebGeolocationProviding` protocol on iOS (the transport seam — the coordinator depends on the protocol, not the shim), implemented by a `GeolocationBridge` that consults the same `PermissionManager` decision flow as camera/mic (site prompt first), then drives a `CLLocationManager`-backed service (`requestWhenInUseAuthorization` → system prompt second; position updates → JS callbacks; PositionError codes mapped per spec: `PERMISSION_DENIED` on site-deny or system-deny).
- Fail-open: if the shim is disabled or fails to install, behavior degrades to exactly today's (WebKit's own prompt) — no regression path.

**Known validation risks for the hack phase:** override visibility in the page world vs. isolated content worlds; cross-origin iframes; interaction with `navigator.permissions.query({name:'geolocation'})` (shim leaves it untouched → possible inconsistency); site fingerprinting of the overridden API; accuracy/`enableHighAccuracy` options; watch lifetime across navigations; ensuring WebKit's native prompt cannot double-fire when the shim handles a request. If any of these prove fatal, per-site geolocation is deferred and camera/mic ship alone.

## Testing approach

- **Package (`PermissionsTests`):** port the existing macOS unit tests for manager/store/codec (from `macOS/UnitTests/Permissions/`, minus WebKit-dependent `PermissionModel` tests, which stay on macOS); decision resolution incl. override chaining; burn with fireproof exceptions (both overloads); `PermissionType` raw-value round-trips incl. `external_` schemes; store CRUD + `clear(except:)` batch delete against an in-memory/temporary store; event-mapping emission on decode failure.
- **macOS store-compatibility regression (PR 2):** a test that opens a fixture `Database.sqlite` created pre-extraction with the new merged model and asserts `NSPersistentStoreCoordinator.metadataForPersistentStore` compatibility (mirrors History's migration-fixture approach, `BrowsingHistory_V1.sqlite`), plus an encrypt/decrypt round-trip of `domainEncrypted` with the registered transformer.
- **macOS existing suites stay green:** `macOS/UnitTests/Permissions/*` (updated imports), `IntegrationTests/Fire/FireTests.swift` (burn path through the new protocol seam).
- **iOS unit tests:** `SitePermissionsCoordinator` decision matrix (persisted allow/deny, ask→prompt, allow-once session scoping, Duck.ai override, global never-ask, system-denied → recover flow) using `PermissionManagerMock` and a stub `SystemPermissionManager`; plaintext transformer round-trip; fireproofing adapter; settings view model (list/remove/toggle).
- **Pixels:** JSON5 definitions validated via `npm run validate-pixel-defs`.
- **Manual/QA:** site-prompt-before-system-prompt ordering on first-ever TCC ask; fireproofed-site retention across Fire; recover flow round-trip through System Settings; toast/animation; and, provisionally, the geolocation shim against a test-page matrix (getCurrentPosition/watch/iframe/error codes).

## Suggested PR split

> **This is a suggestion, not a commitment** — sequencing and grouping may change as work lands. Each PR is independently shippable and keeps macOS green.

1. **PR 1 — Create the `Permissions` package (no consumers).** New BSK target/product/tests; types moved as copies with the seam changes (fireproof protocol, event mapping, entity-name constant, hand-written `@objc` managed object, platform extensions split out); model copy with codegen set to Manual/None. Neither app imports it yet, so nothing can break; the `@objc(PermissionManagedObject)` class is not yet linked next to the app's generated one.
2. **PR 2 — macOS switchover.** macOS imports `Permissions`; app-target copies of the moved files and the app-local model are deleted **in the same PR** (two `@objc(PermissionManagedObject)` classes must never link together); `Database.init()` merges the package model and registers transformers over the merged model; `FireproofDomains` conformance, pixel `EventMapping`, `PermissionType+Icons.swift` and policy-flag extensions added; store-compatibility regression test. Highest-risk PR — keep it mechanical, no behavior changes.
3. **PR 3 — iOS foundation.** `PermissionsDatabase` + plaintext transformer registration, `PermissionManager` DI, iOS `SystemPermissionManager`, `Fireproofing` adapter, `FeatureFlag` case, pixel event mapping. No UI; dark-launched.
4. **PR 4 — iOS camera/mic + site prompt.** `SitePermissionsCoordinator`, `TabViewController` delegate rewiring (Duck.ai guard → override provider), 3-option prompt UI, allow-once session semantics, decision pixels.
5. **PR 5 — Settings → Permissions.** Settings row + deep link, per-site list with status icons, remove actions, global never-ask persistor + override, System Settings referral, recover-from-denied flow.
6. **PR 6 — Feedback + entry point.** Omnibar granted animation (`OmniBarNotificationType` case), post-grant toast (`ActionMessageView`), temporary browsing-menu entry (both menu builders), flag-gated.
7. **PR 7 — Fire integration.** `burnPermissions` wired into the iOS data-clearing/forget paths (full burn except fireproofed; per-domain burn via eTLD+1 overload), matching `Fire.swift`'s macOS pattern.
8. **PR 8 (provisional) — Geolocation.** Shim user script, message bridge, `CLLocationManager` service, `WebGeolocationProviding` wiring, location rows enabled in Settings/prompt. Lands only if the hack phase validates the transport.

## Open questions / risks

**Core Data relocation (high consequence, well-mitigated).** Any accidental change to the entity XML (attribute type, optionality, default) changes the version hash and would trigger a migration attempt against every existing macOS user's merged store. Mitigations: byte-identical entity move, the PR 2 compatibility test, and no model-version bump. Related: registration must run over the *merged* model (a model that lacks the entity registers nothing for it, and the failure mode — writes that bypass encryption or unreadable reads — is silent until runtime).

**Transformer registration ordering.** Preserved structurally on macOS (`Database.init()` before any `loadStore`); on iOS the pass-through registration lives inside `PermissionsDatabase.make()` before `loadStore`, so no caller can get it wrong. The known-bad state is an unregistered `"NSStringTransformer"` name at store-access time.

**Codegen ownership.** Switching from Xcode codegen to a hand-written class is safe only with the `@objc(PermissionManagedObject)` annotation and atomic deletion of the generated class (PR 2). If PR 1 and PR 2 were ever combined or reordered carelessly, duplicate ObjC classes would collide at runtime.

**iOS geolocation uncertainty.** The single biggest scope risk; fully firewalled behind the transport seam (see the provisional section's validation list). Decision point: end of hack phase. Also product-visible: if deferred, the Settings page ships camera/mic only, and Figma's location surfaces need a v1.1 flag.

**iOS plaintext at rest (accepted for v1).** Domains with permission decisions are stored unencrypted on iOS, consistent with iOS History/Bookmarks today. Flipping to encryption later requires porting the key store + `EncryptedValueTransformer` out of macOS-only `Utilities` and a value-level migration of existing rows — worth a follow-up task now so it isn't forgotten.

**Held `decisionHandler` lifetime.** The site prompt holds WebKit's media-capture `decisionHandler` while the user decides. The handler must be called exactly once on every path (dismiss, tab close, navigation, backgrounding) — the coordinator owns this invariant; leaking it stalls the page's `getUserMedia` promise.

**Allow Once semantics.** macOS scopes non-persisted grants to the page/tab session with reset-on-navigation handled by `PermissionModel`. iOS needs an explicit product decision (per page-load vs. per tab-visit vs. time-boxed); recommendation: match desktop (cleared on navigation away from the granting origin). Needs design sign-off against Figma.

**Global "never ask" vs. per-site allow precedence.** Implemented as an override chain, so precedence is an ordering choice. Recommendation: an explicit per-site Always Allow wins over the global toggle (the toggle means "stop asking", not "revoke my choices") — needs product confirmation.

**Module/type name shadowing.** The macOS `Permissions` typealias stays app-side while the app imports the `Permissions` module; qualified lookups of the form `Permissions.SomeType` in macOS app code would resolve to the typealias first. No such qualified references are needed today; avoid introducing any, and never add a type named `Permissions` inside the package.

**Duck.ai behavior parity.** The carve-out moves from an inline guard to an override provider; the matrix (duck.ai mic auto-grant/deny off app-level AV status, camera-only unaffected, non-duck.ai unaffected) must be pinned by tests in PR 4.
