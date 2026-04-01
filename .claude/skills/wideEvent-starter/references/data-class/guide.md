# Data Class Guide

For a complete example, see `examples/` in this directory.

## Protocol Requirements

The data class conforms to `WideEventData` (from `SharedPackages/BrowserServicesKit/Sources/PixelKit/WideEvent/WideEventData.swift`).

```swift
public protocol WideEventData: Codable, WideEventParameterProviding {
    static var metadata: WideEventMetadata { get }
    var contextData: WideEventContextData { get set }
    var globalData: WideEventGlobalData { get set }
    var appData: WideEventAppData { get set }
    var errorData: WideEventErrorData? { get set }
    func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision
}

// From WideEventParameterProviding:
func jsonParameters() -> [String: Encodable]
```

## File Location

Ask the user if unclear. Common locations:
- `SharedPackages/BrowserServicesKit/Sources/BrowserServicesKit/<Feature>/`
- `SharedPackages/BrowserServicesKit/Sources/Subscription/WideEvents/`
- `SharedPackages/<FeaturePackage>/Sources/<Module>/`

## Class Structure

The class has four distinct sections:

### 1. Main Class Body

```swift
import Foundation
import PixelKit

public class <Feature>WideEventData: WideEventData {
    public static let metadata = WideEventMetadata(
        pixelName: "<pixel_suffix>",            // suffix only — "subscription_purchase" not "m_ios_wide_subscription_purchase"
        featureName: "<feature-name>",           // hyphens, e.g., "subscription-purchase"
        mobileMetaType: "ios-<feature-name>",    // meta.type enum for iOS
        desktopMetaType: "macos-<feature-name>", // meta.type enum for macOS
        version: "1.0.0"
    )

    // Required protocol properties
    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData
    public var errorData: WideEventErrorData?

    // Feature-specific properties
    // ...

    // CodingKeys (if non-Codable properties like closures exist)
    // init(...)
    // completionDecision(for:)
}
```

### 2. Enums Extension

```swift
extension <Feature>WideEventData {
    public enum SomeEnum: String, Codable, CaseIterable {
        case optionA = "option_a"  // rawValue MUST match JSON5 enum value
    }
}
```

### 3. jsonParameters + Helpers Extension

```swift
extension <Feature>WideEventData {
    public func jsonParameters() -> [String: Encodable] {
        Dictionary(compacting: [
            (WideEventParameter.<Feature>Feature.someKey, someProperty.rawValue),
            (WideEventParameter.<Feature>Feature.latency, someDuration?.intValue(bucket)),
        ])
    }
}
```

### 4. WideEventParameter Extension

```swift
extension WideEventParameter {
    public enum <Feature>Feature {
        static let someKey = "feature.data.ext.some_key"
    }
}
```

## Key Patterns

| Pattern | What | When |
|---------|------|------|
| `WideEvent.MeasuredInterval` | Timing/latency properties | Any duration field |
| `DurationBucket.bucketed()` | Bucket latency values | Latency params with bucketed enums |
| `Dictionary(compacting:)` | Exclude nil from params | Always in `jsonParameters()` |
| `WideEventErrorData(error:)` | Wrap NSError for reporting | Error handling |
| `markAsFailed(at:error:)` | Convenience for fail + error | Features with failing steps |
| `CodingKeys` enum | Exclude non-Codable props | Closures or non-Codable properties |

## Metadata pixelName

The `pixelName` is the suffix only. The framework prepends `m_ios_wide_` or `m_mac_wide_` automatically.
- Pixel `m_ios_wide_subscription_purchase` → `pixelName: "subscription_purchase"`

## SwiftLint

After creating the data class and test files, run SwiftLint to fix formatting:

```bash
swiftlint --fix <data_class_path>
swiftlint --fix <test_class_path>
```

Skip if swiftlint is not installed.
