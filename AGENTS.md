# Apple Browsers (iOS & macOS)

DuckDuckGo browser for iOS and macOS. Privacy-first, modern Swift, cross-platform architecture.

## Architecture

**Pattern**: MVVM + Coordinators + Dependency Injection
**UI**: SwiftUI preferred, UIKit/AppKit for legacy
**Storage**: Core Data + GRDB + Keychain for sensitive data
**Design**: DesignResourcesKit for colors/icons (MANDATORY)

**Key directories:**
- `iOS/` — iOS browser app (UIKit + SwiftUI hybrid)
- `macOS/` — macOS browser app (AppKit + SwiftUI hybrid)
- `SharedPackages/` — Cross-platform Swift packages

## Critical rules

- **MUST** use DesignResourcesKit for all colors: `Color(designSystemColor: .textPrimary)`
- **MUST** use DesignResourcesKit for all icons: `DesignSystemImages.Glyphs.Size16.add`
- **NEVER** use `.shared` singletons — use dependency injection
- **NEVER** use `print()` — use `Logger` extensions (`Logger.general`, `.network`, `.ui`)
- **NEVER** hardcode colors, fonts, or icons
- **NEVER** force unwrap without justification
- **NEVER** update UI without `@MainActor`
- **NEVER** disable linter rules — fix the underlying issue

## Import hygiene

- Don't change imports unless a new symbol requires it or removal is part of the task
- Keep `import SwiftUI` scoped to `#if DEBUG` / `#Preview` blocks
- Prefer `import AppKit` (macOS) or `import UIKit` (iOS) over `import SwiftUI` in view controllers

## Logging

Use `Logger` extensions, never `print()`:
- `Logger.general` — General app functionality
- `Logger.network` — Network requests
- `Logger.ui` — UI updates
- `Logger.tests` — Test-specific (import `os.log` in tests)

## Build commands

| Action | Command |
|--------|---------|
| Build iOS | `xcodebuild -workspace DuckDuckGo.xcworkspace -scheme "iOS Browser" -configuration Debug -destination "platform=iOS Simulator,name=iPhone 16" ONLY_ACTIVE_ARCH=YES` |
| Build macOS | `xcodebuild -workspace DuckDuckGo.xcworkspace -scheme "macOS Browser" -configuration Debug -destination "platform=macOS,arch=arm64" ONLY_ACTIVE_ARCH=YES` |

Use `xcbeautify` to pipe output. See [docs/development-commands.md](docs/development-commands.md) for full details.

## Test naming

Use `when/then` convention: `testWhenUrlIsNotATrackerThenMatchesIsFalse()`

## Reference documentation

Consult the relevant doc when working in that area:

### Core
| Topic | File |
|-------|------|
| Project overview & rule index | [docs/general.md](docs/general.md) |
| Swift code style | [docs/code-style.md](docs/code-style.md) |
| Anti-patterns | [docs/anti-patterns.md](docs/anti-patterns.md) |
| Architecture | [docs/architecture.md](docs/architecture.md) |
| Project structure | [docs/project-structure.md](docs/project-structure.md) |
| Privacy & security | [docs/privacy-security.md](docs/privacy-security.md) |
| Performance optimization | [docs/performance-optimization.md](docs/performance-optimization.md) |

### UI & Design
| Topic | File |
|-------|------|
| Design system (DesignResourcesKit) | [docs/design-system-designresourceskit.md](docs/design-system-designresourceskit.md) |
| SwiftUI style | [docs/swiftui-style.md](docs/swiftui-style.md) |
| SwiftUI advanced patterns | [docs/swiftui-advanced.md](docs/swiftui-advanced.md) |
| WebKit browser patterns | [docs/webkit-browser.md](docs/webkit-browser.md) |

### Features
| Topic | File |
|-------|------|
| Feature flags | [docs/feature-flags.md](docs/feature-flags.md) |
| Feature flag addition | [docs/feature-flags-addition.md](docs/feature-flags-addition.md) |
| A/B experiments | [docs/abn-experiment-framework.md](docs/abn-experiment-framework.md) |
| Pixels | [docs/pixels.md](docs/pixels.md) |
| Pixel definitions | [docs/pixel-definitions.md](docs/pixel-definitions.md) |
| Instrumentation facades | [docs/instrumentation-facades.md](docs/instrumentation-facades.md) |
| Analytics patterns | [docs/analytics-patterns.md](docs/analytics-patterns.md) |
| User defaults / storage | [docs/user-defaults-storage.md](docs/user-defaults-storage.md) |
| SecureVault | [docs/securevault-guidelines.md](docs/securevault-guidelines.md) |
| DuckPlayer | [docs/duckplayer.md](docs/duckplayer.md) |
| DuckPlayer userscript | [docs/duckplayer-userscript-integration.md](docs/duckplayer-userscript-integration.md) |
| Subscription architecture | [docs/subscription-architecture.md](docs/subscription-architecture.md) |
| App lifecycle state machine | [docs/app-lifecycle-state-machine.md](docs/app-lifecycle-state-machine.md) |

### Platform-specific
| Topic | File |
|-------|------|
| iOS architecture | [docs/ios-architecture.md](docs/ios-architecture.md) |
| iOS tracker blocking | [docs/ios-tracker-blocking-implementation.md](docs/ios-tracker-blocking-implementation.md) |
| macOS window management | [docs/macos-window-management.md](docs/macos-window-management.md) |
| macOS system integration | [docs/macos-system-integration.md](docs/macos-system-integration.md) |
| macOS singletons removal | [docs/macos-singletons-removal.md](docs/macos-singletons-removal.md) |
| BSK integration | [docs/browserserviceskit-integration.md](docs/browserserviceskit-integration.md) |
| Shared packages | [docs/shared-packages.md](docs/shared-packages.md) |

### Testing & Workflow
| Topic | File |
|-------|------|
| Testing patterns | [docs/testing.md](docs/testing.md) |
| UI testing | [docs/ui-testing.md](docs/ui-testing.md) |
| Maestro device selection | [docs/maestro-device-selection.md](docs/maestro-device-selection.md) |
| Development commands | [docs/development-commands.md](docs/development-commands.md) |
| Pull request guidelines | [docs/pull-request.md](docs/pull-request.md) |
| Branch naming | [docs/branch-naming-conventions.md](docs/branch-naming-conventions.md) |
| Import hygiene | [docs/import-hygiene.md](docs/import-hygiene.md) |
| Logging guidelines | [docs/logging-guidelines.md](docs/logging-guidelines.md) |

### Network Quality
| Topic | File |
|-------|------|
| Network quality testing | [docs/network-quality-testing.md](docs/network-quality-testing.md) |
| Network quality scoring | [docs/network-quality-scoring.md](docs/network-quality-scoring.md) |
| Network quality test config | [docs/network-quality-test-config.md](docs/network-quality-test-config.md) |
| Network quality variance | [docs/network-quality-variance-scoring.md](docs/network-quality-variance-scoring.md) |
