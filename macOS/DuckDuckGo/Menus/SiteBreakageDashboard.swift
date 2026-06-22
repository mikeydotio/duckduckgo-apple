//
//  SiteBreakageDashboard.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import AppKit
import Foundation
import SwiftUI

/// Internal-only debug window that visualizes the per-tab site-breakage signals the accumulator holds.
/// Reads live, in-memory snapshots only — no aggregation across tabs, nothing persisted.
@MainActor
final class SiteBreakageDashboardWindowController: NSWindowController {

    private static var sharedController: SiteBreakageDashboardWindowController?
    private let model = SiteBreakageDashboardModel()

    static func show() {
        if let existing = sharedController {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = SiteBreakageDashboardWindowController()
        sharedController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    init() {
        let window = SiteBreakageDashboardWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                                                 styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                                 backing: .buffered, defer: false)
        window.title = "Site Breakage Signals"
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: SiteBreakageDashboardView(model: model))
        model.start()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// The browser binds Cmd+W to `MainViewController.closeTab`, not `performClose:`, so a standalone window
/// never closes on Cmd+W. Intercept it here and close the window directly.
private final class SiteBreakageDashboardWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

extension SiteBreakageDashboardWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        model.stop()
        Self.sharedController = nil
    }
}

// MARK: - Model

@MainActor
final class SiteBreakageDashboardModel: ObservableObject {

    struct TabBreakage: Identifiable {
        let id: String          // Tab.id
        let title: String
        let visits: [VisitSnapshot]
        var issueCount: Int { visits.filter(\.hasIssues).count }
    }

    @Published private(set) var tabs: [TabBreakage] = []
    private var timer: Timer?

    func start() {
        refresh()
        // Polling keeps the window decoupled from per-tab publishers as tabs open and close; 1s is plenty live
        // for a debug surface.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        var result: [TabBreakage] = []
        for tabCollectionViewModel in Application.appDelegate.windowControllersManager.allTabCollectionViewModels {
            for tab in tabCollectionViewModel.tabCollection.loadedTabs {
                guard let snapshots = tab.breakageSignals?.visitSnapshots(), !snapshots.isEmpty else { continue }
                let title = tab.title ?? snapshots.last?.site ?? "Tab"
                result.append(TabBreakage(id: tab.id, title: title, visits: snapshots))
            }
        }
        tabs = result
    }
}

// MARK: - Views

struct SiteBreakageDashboardView: View {
    @ObservedObject var model: SiteBreakageDashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Site Breakage Signals").font(.headline)
                Spacer()
                Text("\(model.tabs.count) tab(s) · live").font(.caption).foregroundColor(.secondary)
            }
            .padding()
            Divider()

            if model.tabs.isEmpty {
                Spacer()
                Text("No tabs with site-breakage signals yet.\nLoad a site, then check back.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                        DisclosureGroup {
                            ForEach(tab.visits.reversed()) { visit in
                                VisitRowView(visit: visit)
                            }
                        } label: {
                            tabHeader(tab, number: index + 1)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private func tabHeader(_ tab: SiteBreakageDashboardModel.TabBreakage, number: Int) -> some View {
        HStack {
            Text("Tab #\(number): \(tab.title)").lineLimit(1).truncationMode(.middle)
            if tab.issueCount > 0 {
                Text("\(tab.issueCount) issue\(tab.issueCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.red.opacity(0.18)))
            }
        }
    }
}

private struct VisitRowView: View {
    let visit: VisitSnapshot

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                if !visit.resourceFailures.isEmpty { resourceSection }
                if visit.blocks.total > 0 { blockSection }
                if visit.integrityFailures > 0 { integritySection }
                if visit.storagePrompts > 0 { storageSection }
                renderSection
            }
            .padding(.vertical, 4)
            .font(.system(.caption, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Circle().fill(visit.hasIssues ? Color.red : Color.green).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(visit.site).fontWeight(.medium)
                    Text(visit.url).font(.caption2).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(Self.time.string(from: visit.startedAt)).font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var resourceSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Subresource failures (\(visit.resourceFailures.reduce(0) { $0 + $1.count }))").bold()
            ForEach(visit.resourceFailures) { r in
                Text("\(r.isThirdParty ? "3p" : "1p") \(r.host) \(r.fileName) [\(r.resourceType)] \(r.failureClass)/\(r.outcome) ×\(r.count)")
            }
        }
    }

    private var blockSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Content blocking").bold()
            Text("loads:\(visit.blocks.blockedLoads) cookies:\(visit.blocks.blockedCookies) https:\(visit.blocks.madeHTTPS) redirects:\(visit.blocks.redirected) headers:\(visit.blocks.modifiedHeaders)")
            ForEach(visit.blocks.domains) { d in Text("blocked \(d.host) ×\(d.count)") }
        }
    }

    private var integritySection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Network-connection-integrity failures (\(visit.integrityFailures))").bold()
            ForEach(visit.integrityDomains) { d in Text("\(d.host) ×\(d.count)") }
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Storage-access prompts: \(visit.storagePrompts), quirks: \(visit.storageQuirks)").bold()
            ForEach(visit.storageQuirkDomains) { d in Text("quirk \(d.host) ×\(d.count)") }
        }
    }

    private var renderSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Render").bold()
            Text("blank:\(String(visit.renderHealth.blankPage)) subresUnfinished:\(String(visit.renderHealth.subresourcesUnfinished)) finished:\(String(visit.renderFinished)) milestones:0x\(String(visit.renderMilestones, radix: 16))")
        }
    }
}
