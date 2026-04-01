# Test Class & Runner Guide

For a complete example, see `examples/` in this directory.

---

## File Location

Mirror the source file location under `Tests/`:
- `SharedPackages/BrowserServicesKit/Tests/BrowserServicesKitTests/<Feature>/`
- `SharedPackages/BrowserServicesKit/Tests/SubscriptionTests/`
- `SharedPackages/<Package>/Tests/<PackageTests>/`

## Setup Boilerplate

Every wide event test class uses the same setup:

```swift
import XCTest
import PixelKit
@testable import <Module>

final class <Feature>WideEventTests: XCTestCase {

    private var wideEvent: WideEvent!
    private var firedPixels: [(name: String, parameters: [String: String])] = []
    private var testDefaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() {
        super.setUp()
        testSuiteName = "\(type(of: self))-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName) ?? .standard
        setupMockPixelKit()
        wideEvent = WideEvent(
            useMockRequests: true,
            storage: WideEventUserDefaultsStorage(userDefaults: testDefaults),
            featureFlagProvider: MockWideEventFeatureFlagProvider(isPostEndpointEnabled: true)
        )
        firedPixels.removeAll()
    }

    override func tearDown() {
        testDefaults?.removePersistentDomain(forName: testSuiteName)
        PixelKit.tearDown()
        super.tearDown()
    }

    private func setupMockPixelKit() {
        let mockFireRequest: PixelKit.FireRequest = { pixelName, headers, parameters, allowedQueryReservedCharacters, callBackOnMainThread, onComplete in
            self.firedPixels.append((name: pixelName, parameters: parameters))
            DispatchQueue.main.async {
                onComplete(true, nil)
            }
        }

        PixelKit.setUp(
            dryRun: false,
            appVersion: "1.0.0",
            source: "test",
            defaultHeaders: [:],
            dateGenerator: Date.init,
            defaults: testDefaults,
            fireRequest: mockFireRequest
        )
    }
}
```

Include `MockWideEventFeatureFlagProvider` at bottom of file (or reuse if it exists):
```swift
struct MockWideEventFeatureFlagProvider: WideEventFeatureFlagProviding {
    let isPostEndpointEnabled: Bool
    func isEnabled(_ flag: WideEventFeatureFlag) -> Bool {
        switch flag {
        case .postEndpoint: return isPostEndpointEnabled
        }
    }
}
```

## Test Categories

### Happy Path (Successful Flow)
- Start flow → set durations → complete with `.success`
- Verify `feature.status == "SUCCESS"`
- Verify all custom `feature.data.ext.*` keys
- Verify standard params present: `app.name`, `app.version`, `global.platform`, `global.type`, `global.sample_rate`

### Failure / Error Flow
- Start flow → trigger error → `markAsFailed()` → complete with `.failure`
- Verify error domain, code, underlying domain/code
- Verify `feature.data.ext.failing_step` if applicable

### Cancelled Flow
- Complete with `.cancelled`
- Verify no error data, optional fields excluded when nil

### Edge Cases
- **Duration bucketing**: verify bucketed values (e.g., 2.5s → 5000 bucket)
- **Optional fields excluded**: nil properties don't appear as keys
- **Enum variants**: test each case produces correct rawValue
- **Flow cleanup**: `getAllFlowData().count == 0` after completion

### Completion Decision Tests (if custom logic)
- Test each branch of `completionDecision(for:)`
- Use `async` test methods

## Key Assertions

```swift
// Pixel was fired
XCTAssert(firedPixels.count >= 1 && firedPixels.count <= 2)

// Custom parameters
let params = firedPixels[0].parameters
XCTAssertEqual(params["feature.data.ext.some_key"], "expected_value")

// Standard parameters present
XCTAssertNotNil(params["app.name"])
XCTAssertEqual(params["global.type"], "app")

// Optional excluded when nil
XCTAssertNil(params["feature.data.ext.optional_field"])
```

---

## Running Tests

### BrowserServicesKit tests
```bash
cd <repo_root>/SharedPackages/BrowserServicesKit
swift test --filter <TestClassName>
```

### Other packages
```bash
cd <repo_root>/SharedPackages/<PackageName>
swift test --filter <TestClassName>
```

### App-level tests (if needed)
```bash
xcodebuild test \
  -project <project_path> \
  -scheme <scheme_name> \
  -only-testing:<TestTarget>/<TestClassName> \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Iterative Fix Loop

1. Run the tests
2. If pass → done
3. If fail:
   - Read the failure output
   - Identify root cause
   - Fix the data class or test class
   - Re-run
4. Repeat until all pass

## Common Failures

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Wrong bucketed value | Bucket function range mismatch | Check `bucket()` switch cases |
| Parameter key not found | Typo in `WideEventParameter` key | Compare with JSON5 definition |
| Module not found | Wrong `@testable import` | Check package/module name |
| Unexpected duration | Date arithmetic off | Check `MeasuredInterval` start/end |
| Pixel not captured | Mock PixelKit not set up | Verify `setupMockPixelKit()` |

## What NOT to Fix

- Don't change assertions to make them pass — fix the data class instead
- Don't remove failing tests — fix the underlying issue
- If a test reveals a real data class bug, fix the data class
