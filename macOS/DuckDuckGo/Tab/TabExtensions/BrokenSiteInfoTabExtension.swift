//
//  BrokenSiteInfoTabExtension.swift
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

import BrowserServicesKit
import Combine
import Common
import Foundation
import Navigation
import os.log
import PrivacyDashboard
import UserScript
import WebKit

final class BrokenSiteInfoTabExtension {

    private(set) var lastWebError: Error?
    private(set) var lastHttpStatusCode: Int?

    private(set) var inferredOpenerContext: BrokenSiteReport.OpenerContext?
    private(set) var refreshCountSinceLoad: Int = 0

    private(set) var breakageReportingSubfeature: BreakageReportingSubfeature?
    private var siteLoadingPerformanceSubfeature: SiteLoadingPerformanceSubfeature?
    private(set) var lastPageLoadTiming: WKPageLoadTiming?

    private var cancellables = Set<AnyCancellable>()

    init(contentPublisher: some Publisher<Tab.TabContent, Never>,
         webViewPublisher: some Publisher<WKWebView, Never>,
         contentScopeUserScriptPublisher: some Publisher<ContentScopeUserScript, Never>) {

        webViewPublisher.sink { [weak self] webView in
            self?.breakageReportingSubfeature = BreakageReportingSubfeature(targetWebview: webView)
            self?.siteLoadingPerformanceSubfeature = SiteLoadingPerformanceSubfeature()
        }.store(in: &cancellables)

        contentScopeUserScriptPublisher.sink { [weak self] contentScopeUserScript in
            guard let self else { return }

            if let breakageReportingSubfeature {
                contentScopeUserScript.registerSubfeature(delegate: breakageReportingSubfeature)
            }
            if let siteLoadingPerformanceSubfeature {
                contentScopeUserScript.registerSubfeature(delegate: siteLoadingPerformanceSubfeature)
            }
        }.store(in: &cancellables)
    }

    private func resetRefreshCountIfNeeded(action: NavigationAction) {
        switch action.navigationType {
        case .reload, .other:
            break
        default:
            refreshCountSinceLoad = 0
        }
    }

    private func setOpenerContextIfNeeded(action: NavigationAction) {
        switch action.navigationType {
        case .linkActivated, .formSubmitted:
            inferredOpenerContext = .navigation
        default:
            break
        }
    }

    func tabReloadRequested() {
        refreshCountSinceLoad += 1
    }

}

extension BrokenSiteInfoTabExtension: NavigationResponder {

    @MainActor
    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        resetRefreshCountIfNeeded(action: navigationAction)
        setOpenerContextIfNeeded(action: navigationAction)

        return .next
    }

    @MainActor
    func willStart(_ navigation: Navigation) {
        if lastWebError != nil { lastWebError = nil }
    }

    @MainActor
    func decidePolicy(for navigationResponse: NavigationResponse) async -> NavigationResponsePolicy? {
        lastHttpStatusCode = navigationResponse.httpStatusCode

        return .next
    }

    @MainActor
    func didStart(_ navigation: Navigation) {
        if inferredOpenerContext != .external {
            inferredOpenerContext = nil
        }

        if lastWebError != nil {
            lastWebError = nil
        }
    }

    @MainActor
    func navigationDidFinish(_ navigation: Navigation) {
        Task { @MainActor in
            if await navigation.navigationAction.targetFrame?.webView?.isCurrentSiteReferredFromDuckDuckGo == true {
                inferredOpenerContext = .serp
            }
        }
    }

    @MainActor
    func didFailProvisionalLoad(with request: URLRequest, in frame: WKFrameInfo, with error: Error) {
        lastWebError = error
    }

    func didGeneratePageLoadTiming(_ timing: WKPageLoadTiming) {
        lastPageLoadTiming = timing
    }

}

protocol BrokenSiteInfoTabExtensionProtocol: AnyObject, NavigationResponder {
    var lastWebError: Error? { get }
    var lastHttpStatusCode: Int? { get }

    var inferredOpenerContext: BrokenSiteReport.OpenerContext? { get }
    var refreshCountSinceLoad: Int { get }

    var breakageReportingSubfeature: BreakageReportingSubfeature? { get }
    var lastPageLoadTiming: WKPageLoadTiming? { get }

    func tabReloadRequested()
}

extension BrokenSiteInfoTabExtension: TabExtension, BrokenSiteInfoTabExtensionProtocol {
    typealias PublicProtocol = BrokenSiteInfoTabExtensionProtocol
    func getPublicProtocol() -> PublicProtocol { self }
}

extension TabExtensions {
    var brokenSiteInfo: BrokenSiteInfoTabExtensionProtocol? {
        resolve(BrokenSiteInfoTabExtension.self)
    }
}

// MARK: - Site Breakage Signals
//
// Per-page, in-memory accumulator of breakage signals the unified log doesn't otherwise carry:
//   • failed / errored subresources (via the `BreakageResourceLoadObserver` SPI — see WebView.swift)
//   • content-rule-list action tallies (engine-truth blocks / cookie-blocks / upgrades / redirects / header mods)
//   • network-connection-integrity load failures (WebKit's explicit "blocked by protections" marker)
//   • storage-access prompts, flagging WebKit's known-breakage compatibility quirks (fragile-site marker)
//   • render health — blank page (navigation finished but nothing painted) and unfinished subresources,
//     derived from the navigation-performance SPI (render-progress milestones + page-load timing). True
//     hangs are intentionally out of scope here — those are handled via timeout pixels.
//
// Each signal class is a `BreakageSignalGroup` that owns its accumulation, decides whether it represents an
// anomaly, and renders its own digest lines; adding a signal type means adding a group to `PageSignals.groups`.
//
// On demand (wired to the site-protections button) it emits an export-safe digest to the unified log
// under `Logger.siteBreakage`, so an internal user who exports their logs after hitting breakage carries
// the diagnostic detail. Hosts (page + resource eTLD+1) are logged hashed (`.private(mask: .hash)`) —
// correlatable across the archive, never cleartext browsing history. Everything else (failure class,
// status/error code, error domain, resource type, file name, first/third-party, counts, render flags,
// milestone bitmask) is logged `.public`.

/// One class of breakage signal accumulated for a single page load. Each group owns its accumulation
/// state, decides whether it represents an anomaly, and renders its own digest lines — the os_log calls
/// stay inside the group so per-field privacy markers (host hashing) are preserved. Adding a new signal
/// type means adding a group; the emit guard derives the "did anything go wrong?" decision from
/// `isAnomalous`, so a new group opts in by construction rather than by editing a shared condition.
protocol BreakageSignalGroup: AnyObject {
    var isAnomalous: Bool { get }
    func emitDigest(reason: String, pageHost: String)
}

final class BreakageSignalsTabExtension {

    enum ResourceOutcome: Equatable {
        case failed(code: Int, errorDomain: String)
        case httpError(status: Int)

        /// Short label used both for de-duplication keys and the digest (the "code" per entry).
        var label: String {
            switch self {
            case .failed(let code, _): return "err\(code)"
            case .httpError(let status): return "http\(status)"
            }
        }

        /// Error domain disambiguating the code (e.g. NSURLErrorDomain vs WebKitErrorDomain); "http" for status errors.
        var errorDomain: String {
            switch self {
            case .failed(_, let domain): return domain
            case .httpError: return "http"
            }
        }
    }

    enum FailureClass: String {
        case resolve, unreachable, cert, http4xx, http5xx, other
    }

    struct ResourceSignal {
        let domain: String        // eTLD+1
        let fileName: String      // last path component only (no path, query, fragment, credentials)
        let resourceType: String?
        let outcome: ResourceOutcome
        let failureClass: FailureClass
        let isThirdParty: Bool
        var count: Int
    }

    /// Subresource load failures (per-resource, deduped + capped). Anomalous if any failure was seen.
    fileprivate final class ResourceFailures: BreakageSignalGroup {
        var resources: [String: ResourceSignal] = [:] // keyed by "domain|fileName|outcomeLabel"

        var isAnomalous: Bool { !resources.isEmpty }

        func add(domain: String, fileName: String, resourceType: String?, outcome: ResourceOutcome,
                 failureClass: FailureClass, isThirdParty: Bool, max: Int) {
            let key = "\(domain)|\(fileName)|\(outcome.label)"
            if var existing = resources[key] {
                existing.count += 1
                resources[key] = existing
            } else if resources.count < max {
                resources[key] = ResourceSignal(domain: domain, fileName: fileName, resourceType: resourceType,
                                                outcome: outcome, failureClass: failureClass, isThirdParty: isThirdParty, count: 1)
            }
        }

        func emitDigest(reason: String, pageHost: String) {
            let resources = Array(self.resources.values)
            guard !resources.isEmpty else { return }

            let total = resources.reduce(0) { $0 + $1.count }
            let firstParty = resources.filter { !$0.isThirdParty }.reduce(0) { $0 + $1.count }

            var classes: [FailureClass: Int] = [:]
            for signal in resources { classes[signal.failureClass, default: 0] += signal.count }
            let classSummary = classes.map { "\($0.key.rawValue):\($0.value)" }.sorted().joined(separator: ",")

            Logger.siteBreakage.log("[\(reason, privacy: .public)] page=\(pageHost, privacy: .private(mask: .hash)) failed=\(total) (1p:\(firstParty),3p:\(total - firstParty)) classes{\(classSummary, privacy: .public)}")

            for signal in resources.sorted(by: { $0.count > $1.count }).prefix(BreakageSignalsTabExtension.maxDigestEntries) {
                Logger.siteBreakage.log("[\(reason, privacy: .public)] \(signal.isThirdParty ? "3p" : "1p", privacy: .public) \(signal.domain, privacy: .private(mask: .hash)) \(signal.fileName, privacy: .public) [\(signal.resourceType ?? "?", privacy: .public)] \(signal.outcome.label, privacy: .public) \(signal.outcome.errorDomain, privacy: .public) ×\(signal.count)")
            }
        }
    }

    /// Content-rule-list action tallies (engine-truth blocks / modifications). Anomalous if anything was blocked or modified.
    fileprivate final class ContentBlocks: BreakageSignalGroup {
        var blockedLoads = 0
        var blockedCookies = 0
        var madeHTTPS = 0
        var redirected = 0
        var modifiedHeaders = 0
        var blockedDomains: [String: Int] = [:] // eTLD+1 -> blocked-load count

        var total: Int { blockedLoads + blockedCookies + madeHTTPS + redirected + modifiedHeaders }
        var isAnomalous: Bool { total > 0 }

        func emitDigest(reason: String, pageHost: String) {
            guard total > 0 else { return }

            let blockedLoads = self.blockedLoads, blockedCookies = self.blockedCookies
            let madeHTTPS = self.madeHTTPS, redirected = self.redirected, modifiedHeaders = self.modifiedHeaders
            Logger.siteBreakage.log("[\(reason, privacy: .public)] page=\(pageHost, privacy: .private(mask: .hash)) blocked(load:\(blockedLoads),cookies:\(blockedCookies)) httpsUpgraded:\(madeHTTPS) redirected:\(redirected) headersModified:\(modifiedHeaders)")

            for (domain, count) in blockedDomains.sorted(by: { $0.value > $1.value }).prefix(BreakageSignalsTabExtension.maxDigestEntries) {
                Logger.siteBreakage.log("[\(reason, privacy: .public)] blocked \(domain, privacy: .private(mask: .hash)) ×\(count)")
            }
        }
    }

    /// Render / paint progress (engine-truth, via the navigation-performance SPI). Anomalous on a blank page
    /// or unfinished subresources. Its digest line is always emitted alongside the others (when any group is
    /// anomalous) so healthy renders provide a calibration baseline.
    fileprivate final class RenderSignals: BreakageSignalGroup {
        var navigationFinished = false
        var renderMilestones: UInt = 0          // accumulated _WKRenderingProgressEvents bitmask
        var pageLoadTiming: WKPageLoadTiming?    // last reported timing milestones (nil fields = milestone never reached)

        var health: RenderHealth {
            BreakageSignalsTabExtension.renderHealth(navigationFinished: navigationFinished,
                                                     renderMilestones: renderMilestones,
                                                     timing: pageLoadTiming)
        }
        var isAnomalous: Bool { health.anomaly }

        func emitDigest(reason: String, pageHost: String) {
            let health = self.health
            let blank = health.blankPage
            let subres = health.subresourcesUnfinished
            let navFinished = navigationFinished
            let milestones = renderMilestones
            Logger.siteBreakage.log("[\(reason, privacy: .public)] page=\(pageHost, privacy: .private(mask: .hash)) render blank:\(blank, privacy: .public) subresUnfinished:\(subres, privacy: .public) finished:\(navFinished, privacy: .public) milestones:0x\(String(milestones, radix: 16), privacy: .public)")
        }
    }

    /// Loads failed by network-connection-integrity protections (WebKit's explicit "blocked by protections"
    /// marker). Engine-truth attribution of breakage to our protections. Anomalous if any failure was seen.
    final class IntegrityFailures: BreakageSignalGroup {
        var total = 0
        var domains: [String: Int] = [:] // eTLD+1 -> count

        var isAnomalous: Bool { total > 0 }

        func record(domain: String, max: Int) {
            total += 1
            if domains[domain] != nil || domains.count < max { domains[domain, default: 0] += 1 }
        }

        func emitDigest(reason: String, pageHost: String) {
            guard total > 0 else { return }

            let total = self.total
            Logger.siteBreakage.log("[\(reason, privacy: .public)] page=\(pageHost, privacy: .private(mask: .hash)) integrityFailures:\(total)")

            for (domain, count) in domains.sorted(by: { $0.value > $1.value }).prefix(BreakageSignalsTabExtension.maxDigestEntries) {
                Logger.siteBreakage.log("[\(reason, privacy: .public)] integrityFail \(domain, privacy: .private(mask: .hash)) ×\(count)")
            }
        }
    }

    /// Storage-access prompts for subframes. The `forQuirk` flag means WebKit applied a known-breakage
    /// compatibility quirk — it already considers the site fragile around storage/cookies, which is exactly
    /// where our cookie/storage protections bite. Anomalous when a quirk was applied; plain prompts are tallied
    /// for context but do not trigger a digest on their own.
    final class StorageAccessPrompts: BreakageSignalGroup {
        var prompts = 0
        var quirks = 0
        var quirkDomains: [String: Int] = [:] // subframe eTLD+1 that triggered a known-breakage quirk

        var isAnomalous: Bool { quirks > 0 }

        func record(subFrameDomain: String, quirk: Bool, max: Int) {
            prompts += 1
            guard quirk else { return }
            quirks += 1
            if quirkDomains[subFrameDomain] != nil || quirkDomains.count < max { quirkDomains[subFrameDomain, default: 0] += 1 }
        }

        func emitDigest(reason: String, pageHost: String) {
            guard prompts > 0 else { return }

            let prompts = self.prompts, quirks = self.quirks
            Logger.siteBreakage.log("[\(reason, privacy: .public)] page=\(pageHost, privacy: .private(mask: .hash)) storageAccessPrompts:\(prompts) quirks:\(quirks)")

            for (domain, count) in quirkDomains.sorted(by: { $0.value > $1.value }).prefix(BreakageSignalsTabExtension.maxDigestEntries) {
                Logger.siteBreakage.log("[\(reason, privacy: .public)] storageQuirk \(domain, privacy: .private(mask: .hash)) ×\(count)")
            }
        }
    }

    /// Mutable signal accumulator for a single main-frame page load — one instance per navigation.
    private final class PageSignals {
        /// Stable identity for the visit so the dashboard keeps its row across live polls and after the
        /// visit is snapshotted into history.
        let visitID = UUID()
        let startedAt = Date()
        var pageHost: String?       // landing site (eTLD+1)
        var pageURL: URL?           // full main-frame URL, for the local dashboard only (never logged)
        let resources = ResourceFailures()
        let blocks = ContentBlocks()
        let integrity = IntegrityFailures()
        let storage = StorageAccessPrompts()
        let render = RenderSignals()

        /// All groups, in digest emission order. New signal types are added here.
        var groups: [BreakageSignalGroup] { [resources, blocks, integrity, storage, render] }
    }

    private let tld: TLD
    private var page = PageSignals()
    private var visits: [VisitSnapshot] = [] // in-memory, capped, never persisted to disk
    private var cancellables = Set<AnyCancellable>()

    private static let maxResources = 200
    private static let maxDigestEntries = 20
    private static let maxVisits = 10
    private static let ignoredResourceTypes: Set<String> = ["Beacon", "Ping", "CSPReport"] // telemetry, not breakage
    private static let ignoredHosts: Set<String> = ["external-content.duckduckgo.com"] // DDG favicon proxy

    // _WKRenderingProgressEvents bits indicating the page actually drew content.
    private static let firstVisuallyNonEmptyLayout: UInt = 1 << 1
    private static let firstMeaningfulPaint: UInt = 1 << 8

    init(webViewPublisher: some Publisher<WKWebView, Never>, tld: TLD) {
        self.tld = tld

        webViewPublisher.sink { [weak self] webView in
            guard let observer = (webView as? WebView)?.breakageObserver else { return }
            observer.onObservation = { [weak self] observation in
                DispatchQueue.main.async { self?.record(observation) }
            }
        }.store(in: &cancellables)
    }

    // MARK: Recording

    private func record(_ observation: BreakageResourceObservation) {
        let host = observation.url?.host
        if let host, Self.ignoredHosts.contains(host) { return }
        if Self.ignoredResourceTypes.contains(observation.resourceTypeName) { return }

        let outcome: ResourceOutcome
        let failureClass: FailureClass
        if let error = observation.error {
            if error.code == NSURLErrorCancelled { return } // navigation churn / fire-and-forget, not breakage
            outcome = .failed(code: error.code, errorDomain: error.domain)
            failureClass = Self.classify(errorCode: error.code)
        } else if let status = observation.httpStatusCode, status >= 400 {
            outcome = .httpError(status: status)
            failureClass = status >= 500 ? .http5xx : .http4xx
        } else {
            return
        }

        let domain = tld.eTLDplus1(host) ?? host ?? "<?>"
        let isThirdParty = page.pageHost.map { domain != $0 } ?? true
        page.resources.add(domain: domain,
                           fileName: Self.fileName(from: observation.url),
                           resourceType: observation.resourceTypeName,
                           outcome: outcome,
                           failureClass: failureClass,
                           isThirdParty: isThirdParty,
                           max: Self.maxResources)
    }

    /// Last path component only (e.g. "poster.jpg"); empty for pathless / directory-style URLs.
    private static func fileName(from url: URL?) -> String {
        guard let url else { return "" }
        let last = url.lastPathComponent
        return last == "/" ? "" : last
    }

    // MARK: Digest

    @MainActor
    private func resetPage(for navigation: Navigation) {
        // Snapshot the finishing visit into the in-memory history before discarding it, so the dashboard can
        // show it after the user has navigated away. Skip the initial empty page (no site yet).
        if page.pageHost != nil {
            visits.append(makeSnapshot(from: page))
            if visits.count > Self.maxVisits { visits.removeFirst(visits.count - Self.maxVisits) }
        }

        page = PageSignals()
        // Fall back to the raw host: localhost and other non-public-suffix hosts have no eTLD+1, and we still
        // want those visits to register (e.g. the local test harness on localhost).
        page.pageHost = tld.eTLDplus1(navigation.url.host) ?? navigation.url.host
        page.pageURL = navigation.url
    }

    /// Recent visits plus the in-progress one, oldest first. Read-only snapshot for the internal dashboard;
    /// in-memory only, never persisted.
    @MainActor
    func visitSnapshots() -> [VisitSnapshot] {
        var result = visits
        if page.pageHost != nil { result.append(makeSnapshot(from: page)) }
        return result
    }

    /// Flattens the live mutable signal groups into an immutable value snapshot for display.
    private func makeSnapshot(from page: PageSignals) -> VisitSnapshot {
        let resourceRows = page.resources.resources.values
            .map { VisitSnapshot.ResourceFailure(host: $0.domain, fileName: $0.fileName, resourceType: $0.resourceType ?? "?",
                                                 outcome: $0.outcome.label, failureClass: $0.failureClass.rawValue,
                                                 isThirdParty: $0.isThirdParty, count: $0.count) }
            .sorted { $0.count > $1.count }
        let blocks = VisitSnapshot.Blocks(blockedLoads: page.blocks.blockedLoads, blockedCookies: page.blocks.blockedCookies,
                                          madeHTTPS: page.blocks.madeHTTPS, redirected: page.blocks.redirected,
                                          modifiedHeaders: page.blocks.modifiedHeaders,
                                          domains: page.blocks.blockedDomains.hostCounts())
        return VisitSnapshot(id: page.visitID,
                             site: page.pageHost ?? "<?>",
                             url: page.pageURL?.absoluteString ?? page.pageHost ?? "<?>",
                             startedAt: page.startedAt,
                             resourceFailures: resourceRows,
                             blocks: blocks,
                             integrityFailures: page.integrity.total,
                             integrityDomains: page.integrity.domains.hostCounts(),
                             storagePrompts: page.storage.prompts,
                             storageQuirks: page.storage.quirks,
                             storageQuirkDomains: page.storage.quirkDomains.hostCounts(),
                             renderHealth: page.render.health,
                             renderFinished: page.render.navigationFinished,
                             renderMilestones: page.render.renderMilestones)
    }

    /// On-demand emission (wired to the site-protections button). Reads the live buffer, so post-load /
    /// interaction-driven failures up to this moment are included.
    @MainActor
    func emitDigestOnDemand() {
        emitDigest(reason: "protections-button")
    }

    /// Emits a digest only when at least one signal group observed an anomaly. Each group renders its own
    /// lines (keeping per-field privacy markers); new signal types surface automatically via `groups` /
    /// `isAnomalous` without touching this method.
    private func emitDigest(reason: String) {
        guard page.groups.contains(where: \.isAnomalous) else { return }

        let pageHost = page.pageHost ?? "<?>"
        for group in page.groups {
            group.emitDigest(reason: reason, pageHost: pageHost)
        }
    }

    /// Result of the passive render-health check. `anomaly` gates whether a digest is worth emitting on its own.
    struct RenderHealth: Equatable {
        let blankPage: Bool             // navigation finished but the page never painted anything
        let subresourcesUnfinished: Bool // document finished, but subresources were still pending at the timing report
        var anomaly: Bool { blankPage || subresourcesUnfinished }
    }

    /// Derives render health from the navigation-performance signals. Pure (no logging / state) so it can be unit-tested.
    /// A page is considered to have rendered if any "drew content" milestone fired (bitmask) or the timing report
    /// recorded a first visual layout / meaningful paint.
    static func renderHealth(navigationFinished: Bool, renderMilestones: UInt, timing: WKPageLoadTiming?) -> RenderHealth {
        let renderedSomething = (renderMilestones & (firstVisuallyNonEmptyLayout | firstMeaningfulPaint)) != 0
            || timing?.firstMeaningfulPaint != nil
            || timing?.firstVisualLayout != nil
        let blankPage = navigationFinished && !renderedSomething
        let subresourcesUnfinished = timing?.documentFinishedLoading != nil && timing?.allSubresourcesFinishedLoading == nil
        return RenderHealth(blankPage: blankPage, subresourcesUnfinished: subresourcesUnfinished)
    }

    static func classify(errorCode: Int) -> FailureClass {
        switch errorCode {
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return .resolve
        case NSURLErrorCannotConnectToHost, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet:
            return .unreachable
        case (-1206)...(-1200): // NSURLError server/client certificate range
            return .cert
        default:
            return .other
        }
    }
}

extension BreakageSignalsTabExtension: NavigationResponder {

    @MainActor
    func didStart(_ navigation: Navigation) {
        resetPage(for: navigation)
    }

    @MainActor
    func navigationDidFinish(_ navigation: Navigation) {
        page.render.navigationFinished = true
    }

    @MainActor
    func renderingProgressDidChange(progressEvents: UInt) {
        page.render.renderMilestones |= progressEvents
    }

    @MainActor
    func didGeneratePageLoadTiming(_ timing: WKPageLoadTiming) {
        page.render.pageLoadTiming = timing
    }

    @MainActor
    func navigationDidPerformContentRuleListAction(_ action: ContentRuleListAction, forURL url: URL, ruleListIdentifier identifier: String) {
        if action.blockedLoad {
            page.blocks.blockedLoads += 1
            let domain = tld.eTLDplus1(url.host) ?? url.host ?? "<?>"
            if page.blocks.blockedDomains[domain] != nil || page.blocks.blockedDomains.count < Self.maxResources {
                page.blocks.blockedDomains[domain, default: 0] += 1
            }
        }
        if action.blockedCookies { page.blocks.blockedCookies += 1 }
        if action.madeHTTPS { page.blocks.madeHTTPS += 1 }
        if action.redirected { page.blocks.redirected += 1 }
        if action.modifiedHeaders { page.blocks.modifiedHeaders += 1 }
    }

    @MainActor
    func navigationDidFailLoadDueToNetworkConnectionIntegrity(forURL url: URL) {
        let domain = tld.eTLDplus1(url.host) ?? url.host ?? "<?>"
        page.integrity.record(domain: domain, max: Self.maxResources)
    }

    @MainActor
    func navigationDidPromptForStorageAccess(topFrameDomain: String, subFrameDomain: String, forQuirk: Bool) {
        let domain = tld.eTLDplus1(subFrameDomain) ?? subFrameDomain
        page.storage.record(subFrameDomain: domain, quirk: forQuirk, max: Self.maxResources)
    }
}

protocol BreakageSignalsTabExtensionProtocol: AnyObject, NavigationResponder {
    @MainActor func emitDigestOnDemand()
    @MainActor func visitSnapshots() -> [VisitSnapshot]
}

/// Immutable, value-type view of one visit's accumulated signals for the internal site-breakage dashboard.
/// Local display only — holds cleartext hosts/URLs and is never logged or persisted.
struct VisitSnapshot: Identifiable {
    struct ResourceFailure: Identifiable {
        let id = UUID()
        let host: String
        let fileName: String
        let resourceType: String
        let outcome: String       // e.g. "err-1003" / "http404"
        let failureClass: String  // resolve / unreachable / cert / http4xx / http5xx / other
        let isThirdParty: Bool
        let count: Int
    }

    struct HostCount: Identifiable {
        let id = UUID()
        let host: String
        let count: Int
    }

    struct Blocks {
        let blockedLoads: Int
        let blockedCookies: Int
        let madeHTTPS: Int
        let redirected: Int
        let modifiedHeaders: Int
        let domains: [HostCount]
        var total: Int { blockedLoads + blockedCookies + madeHTTPS + redirected + modifiedHeaders }
    }

    let id: UUID
    let site: String
    let url: String
    let startedAt: Date
    let resourceFailures: [ResourceFailure]
    let blocks: Blocks
    let integrityFailures: Int
    let integrityDomains: [HostCount]
    let storagePrompts: Int
    let storageQuirks: Int
    let storageQuirkDomains: [HostCount]
    let renderHealth: BreakageSignalsTabExtension.RenderHealth
    let renderFinished: Bool
    let renderMilestones: UInt

    /// True if this visit observed anything worth surfacing (drives the dashboard's "issue" highlight).
    var hasIssues: Bool {
        !resourceFailures.isEmpty || blocks.total > 0 || integrityFailures > 0 || storageQuirks > 0 || renderHealth.anomaly
    }
}

private extension Dictionary where Key == String, Value == Int {
    /// Sorted host→count pairs for display, highest first.
    func hostCounts() -> [VisitSnapshot.HostCount] {
        map { VisitSnapshot.HostCount(host: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }
}

extension BreakageSignalsTabExtension: TabExtension, BreakageSignalsTabExtensionProtocol {
    typealias PublicProtocol = BreakageSignalsTabExtensionProtocol
    func getPublicProtocol() -> PublicProtocol { self }
}

extension TabExtensions {
    var breakageSignals: BreakageSignalsTabExtensionProtocol? {
        resolve(BreakageSignalsTabExtension.self)
    }
}
