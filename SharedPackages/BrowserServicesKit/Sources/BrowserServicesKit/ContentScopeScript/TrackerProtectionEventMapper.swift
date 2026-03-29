//
//  TrackerProtectionEventMapper.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Common
import ContentBlocking
import Foundation
import PrivacyConfig
import TrackerRadarKit

/// Classifies raw C-S-S resource observations into DetectedRequest using native TrackerResolver.
///
/// C-S-S sends pre-block `{url, resourceType, potentiallyBlocked, pageUrl}` signals.
/// `potentiallyBlocked` reflects JS-side heuristics, not the definitive WKContentRuleList verdict.
/// This mapper computes a native blocked candidate from privacy config state and passes it to
/// TrackerResolver instead, mirroring the legacy contentblockerrules.js semantics.
public struct TrackerProtectionEventMapper {

    private let tld: TLD
    private let trackerResolver: TrackerResolver
    private let contentBlockingEnabled: Bool

    public init(tld: TLD, trackerResolver: TrackerResolver, privacyConfig: PrivacyConfiguration) {
        self.tld = tld
        self.trackerResolver = trackerResolver
        self.contentBlockingEnabled = privacyConfig.isEnabled(featureKey: .contentBlocking)
    }

    // MARK: - ResourceObservation classification

    /// Classify a raw resource observation from C-S-S using native TrackerResolver.
    /// Returns nil if the URL is not a known tracker.
    public func classifyResource(_ observation: TrackerProtectionSubfeature.ResourceObservation,
                                 adClickAttributionVendor: String? = nil) -> DetectedRequest? {
        let resolver = resolverWithVendor(adClickAttributionVendor)
        return resolver.trackerFromUrl(
            observation.url,
            pageUrlString: observation.pageUrl,
            resourceType: observation.resourceType,
            potentiallyBlocked: contentBlockingEnabled)
    }

    // MARK: - SurrogateInjection mapping

    /// Map a surrogate injection signal to a DetectedRequest.
    public func classifySurrogate(_ surrogate: TrackerProtectionSubfeature.SurrogateInjection,
                                  adClickAttributionVendor: String? = nil) -> DetectedRequest? {
        let resolver = resolverWithVendor(adClickAttributionVendor)
        return resolver.trackerFromUrl(
            surrogate.url,
            pageUrlString: surrogate.pageUrl,
            resourceType: "script",
            potentiallyBlocked: contentBlockingEnabled)
    }

    /// Extract the surrogate host from the injection URL.
    public func surrogateHost(from surrogate: TrackerProtectionSubfeature.SurrogateInjection) -> String? {
        return URL(string: surrogate.url)?.host
    }

    // MARK: - Classification helpers

    /// Returns true when request and page share the same eTLD+1.
    public func isSameSiteObservation(_ observation: TrackerProtectionSubfeature.ResourceObservation) -> Bool {
        let requestETLDplus1 = tld.eTLDplus1(forStringURL: observation.url)
        let pageETLDplus1 = tld.eTLDplus1(forStringURL: observation.pageUrl)

        guard let requestETLDplus1, let pageETLDplus1 else { return false }
        return requestETLDplus1 == pageETLDplus1
    }

    /// Build a DetectedRequest for a non-TDS cross-site resource (third-party request).
    public func makeThirdPartyRequest(from observation: TrackerProtectionSubfeature.ResourceObservation) -> DetectedRequest? {
        guard !isSameSiteObservation(observation) else { return nil }
        let requestETLDp1 = tld.eTLDplus1(forStringURL: observation.url) ?? observation.url
        let tds = trackerResolver.tds
        let entity = tds.findEntity(forHost: requestETLDp1) ?? Entity(displayName: requestETLDp1, domains: nil, prevalence: nil)
        let isAffiliated = trackerResolver.isPageAffiliatedWithTrackerEntity(pageUrlString: observation.pageUrl, trackerEntity: entity)
        guard !isAffiliated else { return nil }
        return DetectedRequest(url: observation.url,
                               eTLDplus1: requestETLDp1,
                               knownTracker: nil,
                               entity: entity,
                               state: .allowed(reason: .otherThirdPartyRequest),
                               pageUrl: observation.pageUrl)
    }

    // MARK: - Private

    private func resolverWithVendor(_ vendor: String?) -> TrackerResolver {
        guard let vendor else { return trackerResolver }
        return TrackerResolver(tds: trackerResolver.tds,
                               unprotectedSites: trackerResolver.unprotectedSites,
                               tempList: trackerResolver.tempList,
                               tld: tld,
                               adClickAttributionVendor: vendor)
    }
}
