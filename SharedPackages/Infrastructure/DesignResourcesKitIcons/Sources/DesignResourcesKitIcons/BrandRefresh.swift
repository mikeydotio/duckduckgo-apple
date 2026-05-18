//
//  BrandRefresh.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Visual appearance for design-system illustration icons. Set once at app launch
/// from the `brandRefreshIcons` feature flag; reads happen-after that single write.
/// Mirrors the `DuckUIAppearance` pattern used for button styles.
public enum DesignResourcesKitIconsAppearance: Sendable {
    case legacy
    case refresh

    nonisolated(unsafe) public static var current: DesignResourcesKitIconsAppearance = .legacy
}

public struct BrandRefreshableImage {
    enum Resource {
        case imageResource(ImageResource)
        case named(String)
    }

    let legacy: Resource
    let refresh: Resource?

    public init(_ legacy: ImageResource, refresh: ImageResource? = nil) {
        self.legacy = .imageResource(legacy)
        self.refresh = refresh.map(Resource.imageResource)
    }

    public init(named legacy: String, refreshName: String? = nil) {
        self.legacy = .named(legacy)
        self.refresh = refreshName.map(Resource.named)
    }

    var resolvedResource: Resource {
        switch DesignResourcesKitIconsAppearance.current {
        case .refresh:
            refresh ?? legacy
        case .legacy:
            legacy
        }
    }
}

extension DesignSystemImage {
    /// Returns the refresh-branded asset when `DesignResourcesKitIconsAppearance.current == .refresh`,
    /// otherwise the legacy asset. Used by accessors whose imageset has a paired `*-Refresh`
    /// variant shipped alongside the original for rollback safety.
    static func brandRefreshable(legacy: ImageResource, refresh: ImageResource) -> DesignSystemImage {
        switch BrandRefreshableImage(legacy, refresh: refresh).resolvedResource {
        case .imageResource(let imageResource):
            return .init(resource: imageResource)
        case .named:
            assertionFailure("Design system images must use typed image resources")
            return .init(resource: legacy)
        }
    }
}
