# Tech Design: Per-Site Permission Manager on iOS

- **Asana:** [Project task](https://app.asana.com/1/137249556945/project/1215172677539195/task/1213800892997347?focus=true)
- **Designs:** [Figma — Permission iOS/Android](https://www.figma.com/design/aMaDTBcE9Fsfu40NbjzcrH/Permission--iOS-Android-?node-id=380-46782&m=dev)
- **Geolocation feasibility:** validated in the hack phase (branch `bartosz/on-site-permissions-geo-hack`, spike code — do not merge)
- **Status:** Final. All architectural claims below were verified against the repo; file/line references are as of this writing.

## Summary

Bring the per-site permission manager (camera, microphone, geolocation) to iOS. The shipped macOS implementation (`macOS/DuckDuckGo/Permissions/`) is the reference. Its storage + decision core — `PermissionManager`, `PermissionStore`, the Core Data model, and the decision types — is extracted into a new **`Permissions` sub-library inside `SharedPackages/BrowserServicesKit`**, alongside `History`, `Bookmarks`, and `PrivacyStats`, and consumed by both platforms. WebKit integration, session state, and all UI remain per-platform.

On iOS this delivers: a 3-option site prompt (**Always Allow / Allow Once / Never Allow**) shown **before** any system prompt, replacing WebKit's built-in 2-option session prompt; a Settings → Permissions page with a per-site allow/deny list, status icons, remove-permission actions, and global "never ask" controls; a recover-from-denied-system-permission flow with a System Settings referral; a granted-permission animation and post-grant toast; a temporary browsing-menu entry point; and retention of permissions for fireproofed sites across Fire Button use.

Transport differs by permission type. Camera and microphone use the public `WKUIDelegate` media-capture API, which iOS already exposes. Geolocation has no working iOS delegate hook, so it uses a `navigator.geolocation` JS-interception shim bridging to `CLLocationManager` — **validated end-to-end in the hack phase**: the shim reliably replaces WebKit's own per-site location prompt with our UI, all three JS entry points work against a real `CLLocationManager`, and returned coordinates match stock behavior. Camera/mic and geolocation share one decision core, one store, and one dialog component.

### Success criteria (from the Asana task)

1. Per-site permission manager shipped to **100% of iOS users**, covering camera, microphone, and location, with Fire Button integration.
2. **Directional reduction in the iOS permission issue rate from the current 4.0% baseline** — measured via per-site permission manager **engagement (opens, changes)** in the 4 weeks post-launch as an interim signal, and confirmed via the Quarterly Survey the following quarter.

The pixel set in [Success metrics & measurement](#success-metrics--measurement) is designed to produce these numbers directly, not retrofitted after launch.

## Current state

### macOS (reference implementation — shipped)

Everything lives in the macOS app target (`macOS/DuckDuckGo/Permissions/{Model,View,ViewModel}`), none of it shared. The model layer (`PermissionManager`, `PermissionStore`/`LocalPermissionStore`, `StoredPermission`/`PersistedPermissionDecision`/`PermissionEntity`, `PermissionType`) is Foundation/CoreData/Combine and portable, with four impurities that the extraction fixes: `PermissionType` imports AppKit/`DesignResourcesKitIcons` for `icon`/`solidIcon`; `StoredPermission.swift` imports PixelKit and fires `GeneralPixel.permissionDecryptionFailedUnique` directly; `LocalPermissionStore` calls `PermissionManagedObject.className()` (AppKit-only `NSObject` API); and `PermissionManagerProtocol.burnPermissions(except:)` takes the concrete macOS `FireproofDomains` class. The WebKit hub (`PermissionModel`), session types (`PermissionState`, the `Permissions` typealias, `PermissionAuthorizationQuery` — a typealias over the Tab-layer `UserDialogRequest`), the concrete `SystemPermissionManager`, the private-SPI geolocation provider (dlsym'd `WKContextGetGeolocationManager`/`WKGeolocationManagerSetProvider` via `WKProcessPool+GeolocationProvider`), and all UI are macOS-specific and stay put.

The Core Data entity `PermissionManagedObject` (`Permissions.xcdatamodeld`) lives in the app-wide merged `"Database"` store; `domainEncrypted` is a `Transformable` attribute with `valueTransformerName="NSStringTransformer"`, encrypted at rest via `EncryptedValueTransformer<NSString>` registered in `Database.init()` (`macOS/DuckDuckGo/Common/Database/Database.swift:63-78`) before any store load.

### iOS today — and what happens to the existing session-permission path

iOS has **no per-site permission subsystem**: no manager, no store, no model, no geolocation handling (zero `CLLocationManager`/geolocation code in `iOS/`). What exists today, and its fate:

1. **WebKit's built-in per-session camera/mic prompt.** `TabViewController` (the main web view's `WKUIDelegate`) implements `webView(_:requestMediaCapturePermissionFor:initiatedByFrame:type:decisionHandler:)` (`iOS/DuckDuckGo/TabViewController.swift:3517`) and returns `.prompt` for non-Duck.ai origins, which makes WebKit show its own 2-option "allow / don't allow for this session" dialog. **Fate: subsumed by the coordinator.** With the feature flag on, this delegate method routes every camera/mic request through `SitePermissionsCoordinator`, which always resolves to `.grant` or `.deny` — `.prompt` is never returned, so WebKit's session dialog can no longer appear. WebKit's session grants are ephemeral WebKit-internal state (nothing we persist), so there is **no data migration**: any grants made under the old path simply expire with their session. With the flag off, the method returns `.prompt` exactly as today — the old path remains the intact fallback until rollout completes, after which the `.prompt` branch survives only as a safety net for unknown/future capture types.
2. **WebKit's built-in geolocation prompt** ("this site would like to use your current location"), backed by the app's OS-level location authorization. **Fate: replaced.** The injected shim intercepts `navigator.geolocation` before page scripts run, so WebKit's native geolocation path — and therefore its prompt — is never invoked (verified on device in the hack phase). If the shim is not injected (flag off) or fails to install, behavior degrades to exactly today's.
3. **The Duck.ai auto-grant stub.** The same delegate method auto-grants/denies mic (and camera+mic) for Duck.ai hosts based on `AVCaptureDevice.authorizationStatus(for: .audio)`. **Fate: preserved, relocated.** The inline guard becomes a `PermissionDecisionOverriding` provider injected into `PermissionManager` — the identical mechanism macOS uses for `DuckAiVoiceChatPermissionOverride` — with behavior pinned by tests. (The separate `AIChatWebViewController` in the AIChat package has its own delegate and is untouched.)

Reusable iOS primitives (verified): `Fireproofing` protocol (`iOS/Core/Fireproofing.swift:26`, `isAllowed(fireproofDomain:)`), `URLOpener` (`iOS/Core/URLOpener.swift:22`) with the `NoMicPermissionAlert` open-Settings precedent, `CoreDataDatabase.loadModel(from: <Package>.bundle, named:)` bootstrap (History: `iOS/Core/HistoryManager.swift:255`; PrivacyStats: `iOS/DuckDuckGo/PrivacyStats/PrivacyStatsDatabase.swift:59`), `Pixel.Event` + JSON5 definitions, `ActionMessageView` toasts, `OmniBarNotificationAnimator` omnibar animations, `SettingsPrivacyProtectionsView` for the settings entry, both browsing-menu builders, `KeyValueStoring` persistors per `.cursor/rules/user-defaults-storage.mdc`, and `FeatureFlag` (`iOS/Core/FeatureFlag.swift`).

## Goals / Non-goals

### Goals

- Per-site camera, microphone, and geolocation permissions on iOS: persisted Always Allow / Never Allow, session-scoped Allow Once, site prompt shown **before** the system prompt.
- Settings → Permissions page: per-site list with status icons, remove-permission actions, global "never ask" controls (per type), System Settings referral, recover-from-denied-system-permission flow.
- Granted-permission omnibar animation and post-grant toast; temporary browsing-menu entry point.
- Fire Button integration: permissions for fireproofed sites survive data clearing; per-domain forget clears that domain's permissions.
- One shared storage + decision core for both platforms, with macOS behavior and persisted data fully preserved (no store migration, no behavior change on macOS).
- Pixels that directly produce the success-criteria measurements.
- macOS stays green after every PR.

### Non-goals

- iOS at-rest encryption of the permissions store (v1 stores domains plaintext-archived, matching iOS History/Bookmarks; see Risks).
- Bringing popups, notification, external-scheme, or autoplay permission types to iOS (the shared enum retains those cases for macOS; iOS surfaces only camera/mic/geolocation).
- Porting macOS UI (Permission Center popover, address-bar permission buttons) — all iOS UI is new, per Figma.
- Changing macOS's private-SPI geolocation transport.
- Customizing or re-prompting the **OS-level** permission sheets — confirmed impossible in the hack phase (see the two-layer model below); recovery is Settings deep-link only.
- Real `GeolocationPosition`/`GeolocationPositionError` class instances in the shim (`instanceof` fidelity) — plain spec-shaped objects suffice for real-world sites; revisit only if breakage is observed.

## Architecture

### Package home: `Permissions` sub-library in BrowserServicesKit

A new target + product in `SharedPackages/BrowserServicesKit/Package.swift`, sources at `Sources/Permissions/`, tests at `Tests/PermissionsTests/`. This matches the **History profile** exactly: History is a sibling `.library` product (not part of the `BrowserServicesKit` umbrella target — consumers `import History` directly), Foundation/CoreData/Combine only, no UI, no localization, no third-party deps, Core Data model shipped via `.process(...)`, hand-written managed-object classes, per-target test target.

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

The package also needs a module-level `public let bundle = Bundle.module` (the `Sources/History/global.swift` pattern) so apps can call `CoreDataDatabase.loadModel(from: Permissions.bundle, named: "Permissions")`.

Why not the alternatives: a top-level `SharedPackages` package is for domains with external deps, UI, or localization (`AIChat` has `defaultLocalization` + DesignResourcesKit; `DataBrokerProtectionCore` has ZIPFoundation/swift-algorithms) — the permissions core has none of that; and the BSK umbrella target deliberately excludes domain libraries like History/Bookmarks/PrivacyStats. The macOS `typealias Permissions = [PermissionType: PermissionState]` stays app-side (below), so no type shadows the `Permissions` module name inside the package; no existing BSK product or target uses the name.

### Shared/platform boundary — every type

**Moves into `SharedPackages/BrowserServicesKit/Sources/Permissions/`** (from `macOS/DuckDuckGo/Permissions/Model/`):

| Type | Notes on the move |
|---|---|
| `PermissionType` | Core enum + `rawValue` codec + `canPersistGrantedDecision`/`canPersistDeniedDecision` only. Drops `import AppKit`/`DesignResourcesKitIcons`/`CommonObjCExtensions`: `icon`/`solidIcon` become a macOS app extension (Seam 1); `requiresSystemPermission`, `surfacesSystemDisabledWarning`, and `permissionsUpdatedExternally` become platform-side extensions because they encode per-platform product policy (macOS: camera/mic skip the two-step system flow; iOS: the recover-from-denied flow covers camera/mic too). All seven cases (incl. `.popups`, `.notification`, `.externalScheme`, `.autoplayPolicy`) move so macOS raw values and stored rows keep working unchanged. |
| `[PermissionType].init?(devices: WKMediaCaptureType)` | Moves as `PermissionType+WKMediaCaptureType.swift` (public WebKit API, identical need on both platforms; WebKit imports have BSK precedent, e.g. `Navigation`). The `_WKCaptureDevices` SPI initializer **stays in the macOS app**. |
| `PersistedPermissionDecision`, `StoredPermission`, `PermissionEntity` | The direct PixelKit call on `domainEncrypted` decode failure is replaced by the event-mapping seam (Seam 3). |
| `PermissionStore` (protocol), `LocalPermissionStore` | Replace the AppKit-only `PermissionManagedObject.className()` with an entity-name constant (History precedent: `NSFetchRequest<...>(entityName: "...")`). Gains an optional `EventMapping` for store/decode errors. |
| `PermissionManager`, `PermissionManagerProtocol`, `PermissionDecisionOverriding` | Portable as-is (Foundation/Combine/Common/FoundationExtensions; `droppingWwwPrefix()` is in shared `FoundationExtensions`). One signature change: `burnPermissions(except:)` takes the package fireproofing protocol (Seam 2) instead of concrete `FireproofDomains`. |
| `SystemPermissionManagerProtocol`, `SystemPermissionAuthorizationState` | Protocol + enum only (Foundation/Combine + `PermissionType`; incl. `.systemDisabled`). The **concrete** `SystemPermissionManager` stays on macOS (`NSApp.delegateTyped`, PixelKit, macOS notification service); iOS writes its own concrete (Seam 4). |
| `Permissions.xcdatamodeld` + hand-written `PermissionManagedObject` | See [Data model](#data-model--encryption-approach). |
| `DomainFireproofStatusProviding` (new, package-defined) | Seam 2. |
| `PermissionStoreEvent` (new) | Seam 3. |
| `PermissionManagerMock` | Currently in the macOS app target; both platforms' tests need it. Start in `PermissionsTests`; promote to a `PermissionsTestingUtils` product (precedent: `PersistenceTestingUtils`, `BookmarksTestsUtils`) when the app test suites consume it. |

**Stays in the macOS app target** (session/dialog/WebKit/UI layer — deliberately not extracted):

- `PermissionModel` (WebKit hub: AVFoundation swizzle, `_WK` SPI delegate handling, capture-state KVO, geolocation provider wiring).
- `PermissionState` (a session state machine over the app-defined `WKWebView.CaptureState`, `macOS/DuckDuckGo/Common/Extensions/WKWebViewExtension.swift:58`), the `Permissions` typealias, and `PermissionAuthorizationQuery` (+ `UserDialogRequest`, `macOS/DuckDuckGo/Tab/Model/UserDialogRequest.swift` — Tab-layer dialog machinery shared with other macOS dialogs). These model *live webview usage and in-flight prompts*, not persisted decisions; iOS's prompt lifecycle is different (sheet-based, system-prompt-second) and gets its own lighter types.
- Concrete `SystemPermissionManager`, `GeolocationProvider`/`GeolocationService`/`WKProcessPool+GeolocationProvider`, `Tab+UIDelegate` wiring, `DuckAiVoiceChatPermissionOverride`.
- All Views/ViewModels, `PermissionPixel.swift`, `AddressBarPermissionButtonsIconsProviding`, new `PermissionType+Icons.swift` extension, `FireproofDomains` + its one-line conformance to the package fireproofing protocol.

**New on iOS (app target first — the same call History made; extraction to an `iOS/LocalPackages/Permissions-iOS` UI package, precedent `DataBrokerProtection-iOS`/`SyncUI-iOS`, is deferred until the UI stabilizes, because every surface couples to `TabViewController`, the omnibar, and the Settings stack):**

- `PermissionsDatabase` — dedicated `CoreDataDatabase` (mirrors `HistoryManager`/`PrivacyStatsDatabase`): model from `Permissions.bundle`, own `Permissions.sqlite` in Application Support. Not merged into iOS's app-group `"Database"` store.
- `SitePermissionsCoordinator` (per-tab, owned by `TabViewController`) — the iOS analog of `PermissionModel`: receives `WKUIDelegate` media-capture requests and shim geolocation requests, consults `PermissionManager`, drives the site prompt, tracks session Allow Once grants, owns the held-callback invariants.
- iOS concrete `SystemPermissionManager` (camera/mic via `AVCaptureDevice.authorizationStatus(for:)`, geolocation via the shared `CLLocationManager` service).
- Site prompt UI (custom SwiftUI dialog per Figma — `UIAlertController` cannot carry the site icon, confirmed in the hack phase; mirror the `WebJSAlert` custom-view approach), Settings → Permissions page (row in `SettingsPrivacyProtectionsView`, `SettingsDeepLinkSection` case, `navigationDestinationView(for:)` in `SettingsRootView`), per-site list with status icons, remove actions, global never-ask controls, recover-from-denied view.
- Omnibar granted animation: new `OmniBarNotificationType` case through the existing `OmniBarNotificationAnimator` pipeline (mirroring `cookiePopupManaged`); post-grant toast via `ActionMessageView`.
- Temporary menu entry in `TabViewControllerMenuBuilderExtension.buildBrowsingMenu` and mirrored in `BrowsingMenu/SheetPresentationMenu/BrowsingMenuBuilder.swift`, flag-gated.
- `Fireproofing` adapter, pixel `EventMapping`, `FeatureFlag` case, geolocation bridge + `CLLocationManager` service (below).

### The four seams (what the core exposes, what platforms inject)

**Seam 1 — Icons.** Icons stay **out** of the core. BSK has zero design-resource dependencies today (its only Infrastructure dep is `SystemFrameworksExtensions`), and no BSK sub-library ships images; adding a BSK → `DesignResourcesKitIcons` edge for two computed properties would be dependency creep. Instead each platform provides a `PermissionType+Icons.swift` extension: macOS a verbatim move of the existing `icon`/`solidIcon` bodies; iOS returning the glyphs/sizes Figma specifies.

**Seam 2 — Fireproofing.** Package-defined minimal protocol:

```swift
public protocol DomainFireproofStatusProviding: AnyObject {
    func isFireproof(fireproofDomain: String) -> Bool
}
```

`burnPermissions(except:completion:)` takes this protocol. macOS: `FireproofDomains` conforms directly (it already has the exact method; its app-local protocol of the same name is superseded for this call path). iOS: a one-line adapter over `Fireproofing.isAllowed(fireproofDomain:)`. The eTLD+1 overload `burnPermissions(of:tld:)` moves unchanged (`TLD` from `Common`).

**Seam 3 — Pixels / events.** Per `.cursor/rules/pixels.mdc`, pixels fired from inside a shared package go through an `EventMapping` mapped client-side — the History precedent (`EventMapping<History.HistoryDatabaseError>` → `HistoryStoreEventMapper` on iOS, PixelKit on macOS):

```swift
public enum PermissionStoreEvent {
    case domainDecryptionFailed   // replaces the direct PixelKit call in StoredPermission.swift
    case storeError(Error)
}
```

`LocalPermissionStore` takes an optional `EventMapping<PermissionStoreEvent>`. macOS maps `domainDecryptionFailed` → existing `GeneralPixel.permissionDecryptionFailedUnique`; iOS maps to new `Pixel.Event` cases. **Feature pixels stay platform-side**, matching macOS today (the model layer fires nothing; the UI fires `PermissionPixel`). The iOS feature pixel set is specified in [Success metrics & measurement](#success-metrics--measurement).

**Seam 4 — System permission state.** `SystemPermissionManagerProtocol` + `SystemPermissionAuthorizationState` in the package as shared vocabulary; concrete per platform. Opening System Settings is **not** part of this seam — it is UI (iOS: `URLOpener` + `UIApplication.openSettingsURLString`, `NoMicPermissionAlert` precedent; macOS: unchanged `NSWorkspace` `x-apple.systempreferences:` calls).

### The two-layer permission model (framing for everything below)

There are two independent layers; keeping them separate resolves most design questions (validated framing from the hack phase):

| Layer | Who owns it | Prompt | Our control |
|---|---|---|---|
| **1. OS authorization** — does the *app* get camera/mic/location at all | iOS (TCC/CoreLocation) | System sheet, shown once per app per capability | **None.** Can't restyle, can't add an icon, can't re-show after denial. Recovery = Settings deep-link only. |
| **2. Per-site web permission** — does *this website* get it | WebKit's built-in prompts today | WebKit's 2-option dialogs | **Full.** This is what this project takes over: our dialog, our 3 options, our storage, our re-prompt rules. |

Consequences: the site prompt (layer 2) always precedes the system prompt (layer 1) by construction; a persisted per-site "Always Allow" still yields nothing if layer 1 is denied — that is exactly the recover-from-denied flow; our per-site "Never Allow" is our own state and can be re-prompted/changed freely in-app, unlike an OS denial; and the requested "icon on the alert" nice-to-have lands on **our** dialog (trivial in a custom view), never on the OS sheet.

### iOS request flow — camera/mic

`TabViewController`'s existing `webView(_:requestMediaCapturePermissionFor:initiatedByFrame:type:decisionHandler:)` delegates to `SitePermissionsCoordinator`:

1. Map `WKMediaCaptureType` → `[PermissionType]` (shared initializer). Unknown/future types → `.prompt` (safety fallback, today's behavior).
2. Duck.ai override provider (relocated inline guard) — behavior preserved exactly.
3. Global "never ask" for the type → `decisionHandler(.deny)`, no prompt. Implemented as a second chained `PermissionDecisionOverriding` backed by a `KeyValueStoring` persistor (per `.cursor/rules/user-defaults-storage.mdc` — global toggles are settings, not per-site rows).
4. `PermissionManager.permission(forDomain:permissionType:)`: `.allow` → `.grant`; `.deny` → `.deny`; `.ask` → present the site prompt while holding `decisionHandler`.
5. Prompt result: **Always Allow** → `setPermission(.allow, …)` + `.grant`; **Allow Once** → `.grant` without persisting (session-scoped, coordinator-tracked); **Never Allow** → `setPermission(.deny, …)` + `.deny`.
6. Returning `.grant` is what triggers WebKit's app-level TCC prompt (first time only) — site prompt therefore precedes system prompt with no extra machinery.
7. If layer 1 is already denied (`SystemPermissionManager` reports `.denied`/`.restricted`), skip the site prompt and present the recover flow (explanation + Open Settings via `URLOpener`).
8. On grant: omnibar animation + toast; decision pixel fires.

The `decisionHandler` must be called exactly once on every path (decision, dismissal, tab close, navigation, backgrounding) — a coordinator-owned invariant; leaking it stalls the page's `getUserMedia` promise.

### iOS request flow — geolocation (validated transport)

No `WKUIDelegate` geolocation hook exists on iOS, and macOS's C-SPI provider is unavailable. The validated transport: a content script injected at **document start, all frames, page content world** replaces `navigator.geolocation.{getCurrentPosition,watchPosition,clearWatch}` **and mirrors `navigator.permissions.query({name:'geolocation'})`**, bridging to native over a script-message handler; native decides via the same coordinator flow as camera/mic (steps 2–8 above, with layer 1 = CoreLocation), drives a shared `CLLocationManager` service, and pushes results/errors/permission-state changes back into the originating frame.

Hack-phase results this design relies on:

- WebKit's own per-site location prompt **no longer appears** — page scripts hit our object, so WebKit's native geolocation path is never invoked. Verified on device against `main` (test page: `privacy-test-pages/features/permission-prompts.html`).
- All of `getCurrentPosition`, `watchPosition` (continuous), `clearWatch` work through the shim against a real `CLLocationManager`, including `enableHighAccuracy`, `timeout`, `maximumAge`, and the W3C error codes (`PERMISSION_DENIED` / `POSITION_UNAVAILABLE` / `TIMEOUT`); coordinates matched stock behavior.
- **The Permissions API must be owned too.** Overriding only `navigator.geolocation` leaves `navigator.permissions.query` reporting stale `prompt` state (found and fixed during the hack) — real sites gate on it. Both surfaces must read the same store, and `PermissionStatus.onchange` must fire on decision changes.
- The no-dialog deny path (global "never ask") correctly returns `PERMISSION_DENIED` with zero prompts and no WebKit prompt leak.
- The override persists across navigations (re-installed per document; same-document history changes keep the context).
- `Info.plist` already contains `NSLocationWhenInUseUsageDescription` — no plist change.

Production hardening required beyond the spike (spike code is throwaway; do not merge):

1. **Home: content-scope-scripts.** The shim moves into C-S-S as a subfeature using the existing `messageSecret` handshake + `UserScriptMessageBroker`/`Subfeature` pattern (as `favicon`/`printing` do). This closes the spike's spoofing gap — the spike registered its message handler in the page world, where page JS could post fabricated permission requests. **Delivery note: this is cross-repo work** (a `content-scope-scripts` PR plus a version bump in this repo) and should be sequenced early (see PR split).
2. **Single shared `CLLocationManager`** service with proper lifecycle/accuracy handling (the spike used one per tab), fanning out to concurrent one-shots and watches; also the backing for the iOS `SystemPermissionManager`'s geolocation state.
3. **Policy decisions to encode** (product/security sign-off, then tests): gate on `isSecureContext` (WebKit does; the spike didn't); behavior for `about:blank`/`srcdoc`/`javascript:` frames, where document-start injection is historically flaky — recommendation: treat un-shimmed synthetic frames as deny-by-default rather than letting WebKit's prompt leak.
4. **Lifecycle edges:** stop native watches on `pagehide` and reconcile on bfcache restore (JS-side watches can otherwise look alive while native ones are dead).
5. **Object identity caveat** (accepted): results are plain spec-shaped objects, not real `GeolocationPosition` instances — `instanceof` fails; fine for essentially all real sites (non-goal above).

**Durability risk (the one to watch):** the model rests on the shim being un-bypassable and WebKit's native prompt staying suppressed across all frame types and future iOS releases — undocumented territory. Mitigation: automated coverage against the `privacy-test-pages` permission suite in CI, a dedicated prompt-leak test (assert WebKit's dialog never appears when the shim is active), and the flag as a kill switch.

## Data model + encryption approach

### Model relocation

`Permissions.xcdatamodeld` moves verbatim from `macOS/DuckDuckGo/Permissions/Model/` to `Sources/Permissions/CoreData/`, declared `.process(...)`. Single entity, unchanged:

| Attribute | Type | Notes |
|---|---|---|
| `domainEncrypted` | Transformable, `valueTransformerName="NSStringTransformer"` | Encrypted on macOS, plaintext-archived on iOS (below) |
| `permissionType` | String | `PermissionType.rawValue` |
| `allow` | Boolean (scalar) | |
| `isRemoved` | Boolean (optional, default NO, scalar) | |

`allow`/`isRemoved` together encode `PersistedPermissionDecision` via the existing `PermissionManagedObject.decision` extension.

**Codegen ownership changes.** The entity is currently `codeGenerationType="class"` (Xcode-generated in the app target). Package convention (History/Bookmarks/PrivacyStats) is Manual/None + a hand-written class. The move sets codegen to Manual/None and adds a hand-written `PermissionManagedObject.swift` declared `@objc(PermissionManagedObject)` (exactly as `@objc(BrowsingHistoryEntryManagedObject)` does), so runtime class lookup via the model's `representedClassName` keeps resolving after the class changes modules.

**Store compatibility (macOS).** The entity's version hash derives from its structure (name, attributes, types, optionality, defaults) — not file location, module, or codegen mode — so the merged model stays compatible with existing users' `Database.sqlite` and **no migration occurs**, provided the entity XML is byte-identical. This is the highest-consequence invariant of the extraction; the switchover PR includes a regression test for it (see Testing).

### Encryption + transformer registration

The model keeps `Transformable domainEncrypted` with transformer name `"NSStringTransformer"`. Note for reviewers looking for precedent: the shared `BrowsingHistory` model is **not** one — its `title`/`url` are plain `String`/`URI` attributes (the `valueTransformerName` entries on them are vestigial no-ops), and macOS's encrypted history uses a separate app-local legacy model. `Permissions` is the first shared model with a genuinely `Transformable` attribute encrypted on one platform and not the other, hence the explicit per-platform strategy:

**macOS (behavior unchanged — encrypted).** `Database.init()` currently builds `mergedModel(from: [.main])`, registers `EncryptedValueTransformer<NSString>` et al. over it, then constructs the `CoreDataDatabase` — all synchronously before any store load. Once the model leaves `.main`, that call no longer picks it up, so `Database.init()` becomes:

```swift
let mainModel = NSManagedObjectModel.mergedModel(from: [.main])!
let permissionsModel = CoreDataDatabase.loadModel(from: Permissions.bundle, named: "Permissions")!
let mergedModel = NSManagedObjectModel(byMerging: [mainModel, permissionsModel])!
_ = try mergedModel.registerValueTransformers(withAllowedPropertyClasses: [...], keyStore: keyStore)  // BEFORE store construction, as today
let httpsUpgradeModel = HTTPSUpgrade.managedObjectModel
db = CoreDataDatabase(name: Constants.databaseName, containerLocation: containerLocation,
                      model: .init(byMerging: [mergedModel, httpsUpgradeModel])!)
```

Two invariants: transformer registration strictly **before** store load (preserved by construction — it all lives in `Database.init()`), and registration runs over a model that **includes** the permissions entity (register over the merged model, not `mainModel` alone — otherwise `domainEncrypted` silently loses its transformer).

**iOS (plaintext, v1).** The package ships a trivial pass-through transformer (an `NSSecureUnarchiveFromDataTransformer` subclass allowing `NSString`) plus a `Permissions.registerPlaintextDomainTransformer()` helper; `PermissionsDatabase.make()` calls it **before** `loadStore`. Leaving the name unregistered is not acceptable — Core Data's fallback for a missing named transformer is an undefined/fragile keyed-archiver path that logs warnings and can crash under secure-coding enforcement. With the pass-through, iOS stores the domain as a plain keyed-archived string: well-defined, and upgradable later (moving iOS to real encryption requires porting the key store + `EncryptedValueTransformer` out of macOS-only `macOS/LocalPackages/Utilities` plus a value-level data migration — out of scope for v1, tracked as follow-up).

iOS store bootstrap (mirrors `HistoryManager`/`PrivacyStatsDatabase`): dedicated `CoreDataDatabase(name: "Permissions", containerLocation: <app support>, model: loadModel(from: Permissions.bundle, named: "Permissions"))`, wired into DI at startup behind the feature flag.

## Success metrics & measurement

The success criteria need two numbers, and the pixel set is defined so each is directly computable:

**Interim signal (4 weeks post-launch): per-site permission manager engagement — opens and changes.**

| Pixel (iOS `Pixel.Event` + JSON5 definition) | Fires when | Type | Produces |
|---|---|---|---|
| `m_permissions_manager_opened` | Settings → Permissions page appears; `source` param: `settings` \| `menu` (temporary entry) \| `toast` \| `recovery` | Daily + Count | **Opens**: unique engaging users/day and volume, by entry point |
| `m_permissions_setting_changed` | Any change made in the manager; params: `type` (camera/mic/location), `change` (`to_allow`/`to_deny`/`to_ask`/`removed`) | Daily + Count | **Changes** made in the manager (macOS analog: `m_mac_permission_center_changed_*`) |
| `m_permissions_global_ask_toggled` | Global "never ask" toggled; params: `type`, `enabled` | Daily + Count | Changes (global) |
| `m_permissions_prompt_decision` | Site prompt resolved; params: `type`, `decision` (`always`/`once`/`never`), `dismissed` | Daily + Count | Prompt-level changes + funnel denominator context (macOS analog: `m_permission_authorization_*`) |
| `m_permissions_system_settings_opened` | System Settings referral tapped; param: `type`, `source` (`prompt`/`manager`/`recovery`) | Daily + Count | Recovery-flow engagement (macOS analog: `m_permission_system_preferences_*`) |

Engagement metric = unique users firing `m_permissions_manager_opened` or `m_permissions_setting_changed` (or `m_permissions_global_ask_toggled`) over the 4-week window, as a share of iOS actives — trended against the **4.0% permission issue rate baseline** as the directional interim signal. The daily variants make "unique engaging users per day/window" computable without post-hoc inference; the count variants give volume. Confirmation comes from the Quarterly Survey the following quarter (outside this design; no additional instrumentation needed).

**Ship criterion (100% of iOS users):** the `FeatureFlag` rollout itself; standard experiment/rollout reporting covers it, no dedicated pixel.

Conventions (per `.cursor/rules/pixels.mdc`): each pixel = `Pixel.Event` case + `name` mapping + JSON5 definition in `iOS/PixelDefinitions/pixels/definitions/` (description, owners, triggers, suffixes, parameters) + `npm run validate-pixel-defs` in CI; `m_`-prefixed self-documenting names; no URLs/PII — `type`/`decision`/`source` are closed enums, domains are never sent. Exact final names to be settled at implementation against current naming review guidance; the **set and parameters above are the contract**, chosen so the success-criteria queries exist on day one. The package-internal `PermissionStoreEvent` seam additionally maps `domainDecryptionFailed`/`storeError` to debug pixels on both platforms.

## Testing approach

- **Package (`PermissionsTests`):** port the macOS unit tests for manager/store/codec (from `macOS/UnitTests/Permissions/`, minus WebKit-dependent `PermissionModel` tests, which stay on macOS); decision resolution incl. override chaining (Duck.ai, global never-ask); burn with fireproof exceptions (both overloads); `PermissionType` raw-value round-trips incl. `external_` schemes; store CRUD + `clear(except:)` batch delete against a temporary store; event-mapping emission on decode failure.
- **macOS store-compatibility regression (switchover PR):** open a fixture `Database.sqlite` created pre-extraction with the new merged model and assert persistent-store metadata compatibility (mirrors History's `BrowsingHistory_V1.sqlite` fixture approach), plus an encrypt/decrypt round-trip of `domainEncrypted` with the registered transformer.
- **macOS existing suites stay green:** `macOS/UnitTests/Permissions/*` (updated imports), `IntegrationTests/Fire/FireTests.swift` (burn path through the new protocol seam).
- **iOS unit tests:** `SitePermissionsCoordinator` decision matrix (persisted allow/deny, ask→prompt, allow-once session scoping and expiry-on-navigation, Duck.ai override parity with today's inline guard, global never-ask, system-denied → recover flow, `decisionHandler` called-exactly-once on all exit paths) using `PermissionManagerMock` and a stub `SystemPermissionManager`; plaintext transformer round-trip; fireproofing adapter; settings view model (list/remove/toggle); pixel-firing assertions for every event in the measurement table.
- **Geolocation shim:** automated runs against `privacy-test-pages/features/permission-prompts.html` (request-once, watch, stop, Permissions-API state incl. `onchange`, error codes, iframe behavior, secure-context gating, synthetic-frame policy); a **prompt-leak test** asserting WebKit's native location dialog never appears while the shim is active; bfcache watch-reconciliation test. Simulator note: set Features ▸ Location ▸ Custom Location, or position requests time out.
- **Pixels:** JSON5 definitions validated via `npm run validate-pixel-defs`.
- **Manual/QA:** site-prompt-before-system-prompt ordering on first-ever TCC/CoreLocation ask; fireproofed-site retention across Fire; per-domain forget; recover flow round-trip through System Settings; toast/animation; side-by-side coordinate comparison with stock behavior.

## Suggested PR split

> **This is a suggestion, not a commitment** — sequencing and grouping may change as work lands. Each PR is independently shippable and keeps macOS green.

1. **PR 1 — Create the `Permissions` package (no consumers).** New BSK target/product/tests; types moved as copies with the seam changes (fireproof protocol, event mapping, entity-name constant, hand-written `@objc` managed object, platform extensions split out); model copy with codegen set to Manual/None; `global.swift` bundle export. Neither app imports it yet, so nothing can break.
2. **PR 2 — macOS switchover.** macOS imports `Permissions`; app-target copies and the app-local model are deleted **in the same PR** (two `@objc(PermissionManagedObject)` classes must never link together); `Database.init()` merges the package model and registers transformers over the merged model; `FireproofDomains` conformance, pixel `EventMapping`, `PermissionType+Icons.swift` and policy-flag extensions; store-compatibility regression test. Highest-risk PR — keep it mechanical, zero behavior change.
3. **PR 3 — iOS foundation.** `PermissionsDatabase` + plaintext transformer registration, `PermissionManager` DI, iOS `SystemPermissionManager`, `Fireproofing` adapter, `FeatureFlag` case, pixel event mapping + the `Pixel.Event` cases and JSON5 definitions from the measurement table. No UI; dark-launched.
4. **PR 4 (cross-repo, start early) — C-S-S geolocation subfeature.** The shim (geolocation + Permissions-API mirror) as a content-scope-scripts feature with the `messageSecret`/`Subfeature` handshake; version bump lands in this repo. Independent of PRs 1–3; longest external lead time.
5. **PR 5 — iOS camera/mic + site prompt.** `SitePermissionsCoordinator`, `TabViewController` delegate rewiring (Duck.ai guard → override provider; `.prompt` retained only as unknown-type fallback), 3-option prompt UI (custom view, site icon), allow-once session semantics, `m_permissions_prompt_decision` wiring.
6. **PR 6 — Settings → Permissions.** Settings row + deep link, per-site list with status icons, remove actions, global never-ask persistor + override, System Settings referral, recover-from-denied flow; `m_permissions_manager_opened` / `m_permissions_setting_changed` / `m_permissions_global_ask_toggled` / `m_permissions_system_settings_opened`.
7. **PR 7 — Feedback + entry point.** Omnibar granted animation, post-grant toast, temporary browsing-menu entry (both menu builders), flag-gated.
8. **PR 8 — Fire integration.** `burnPermissions` wired into the iOS data-clearing/forget paths (full burn except fireproofed; per-domain via the eTLD+1 overload), matching `Fire.swift`'s macOS pattern.
9. **PR 9 — Geolocation wiring.** Native bridge to the C-S-S subfeature, shared `CLLocationManager` service, coordinator + prompt + Settings location rows, prompt-leak and lifecycle tests.

## Risks / open questions

**Core Data relocation (high consequence, well-mitigated).** Any accidental change to the entity XML changes the version hash and would trigger a migration attempt against every macOS user's merged store. Mitigations: byte-identical entity move, the PR 2 compatibility test, no model-version bump. Related silent failure mode: transformer registration run over a model missing the entity encrypts nothing / reads garbage — hence "register over the merged model" is called out as an invariant.

**Transformer registration ordering.** Structurally preserved on macOS (`Database.init()` before any `loadStore`); on iOS the pass-through registration lives inside `PermissionsDatabase.make()` before `loadStore`, so no caller can get it wrong. The known-bad state is an unregistered `"NSStringTransformer"` at store-access time.

**Codegen ownership.** Hand-written class is safe only with the `@objc(PermissionManagedObject)` annotation and atomic deletion of the generated class in PR 2; combining/reordering PR 1+2 carelessly links duplicate ObjC classes.

**Geolocation shim durability.** Feasibility is validated, but suppression of WebKit's native prompt across all frame types and future iOS releases is undocumented behavior. Mitigations: CI coverage against privacy-test-pages, the prompt-leak test, deny-by-default policy for un-shimmed synthetic frames, and the feature flag as a kill switch. Cross-repo C-S-S delivery is also the longest lead-time item — start PR 4 early.

**OS-layer limitations (accepted, by platform design).** No icon on and no re-prompt of the system sheets; after an OS-level denial the only recovery is the Settings deep-link flow. This bounds the recover-from-denied UX and should be reflected in copy.

**iOS plaintext at rest (accepted for v1).** Domains with permission decisions are stored unencrypted on iOS, consistent with iOS History/Bookmarks. Follow-up task: port key store + `EncryptedValueTransformer` out of macOS-only `Utilities` and run a value-level migration.

**Held-callback lifetime.** Both the media-capture `decisionHandler` and shim geolocation callbacks must resolve exactly once on every exit path (decision, dismiss, tab close, navigation, backgrounding); coordinator-owned invariant, pinned by tests.

**Allow Once semantics (needs design sign-off).** Recommendation: match desktop — session-scoped, cleared on navigation away from the granting origin. Alternatives (per page-load, time-boxed) need a product decision against Figma.

**Global "never ask" vs. per-site allow precedence (needs product confirmation).** Implemented as an override chain, so precedence is an ordering choice. Recommendation: an explicit per-site Always Allow wins over the global toggle (the toggle means "stop asking", not "revoke my choices").

**Duck.ai behavior parity.** The carve-out moves from an inline guard to an override provider; the exact matrix (Duck.ai mic auto-grant/deny off app-level AV status; camera-only and non-Duck.ai unaffected) is pinned by tests in PR 5.

**Module/type name shadowing.** The macOS `Permissions` typealias stays app-side while the app imports the `Permissions` module; qualified `Permissions.SomeType` lookups in macOS app code would hit the typealias first. No such references are needed today; avoid introducing any, and never add a type named `Permissions` inside the package.
