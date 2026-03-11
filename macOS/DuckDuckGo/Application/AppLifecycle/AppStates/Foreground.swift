//
//  Foreground.swift
//  DuckDuckGo
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

import AppKit
import PixelKit

@MainActor
final class Foreground: ForegroundHandling {

    private weak var appDelegate: AppDelegate?
    private var terminationHandler: TerminationDeciderHandler?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }

    func onTransition() {
        // Phase 1: AppDelegate.applicationDidBecomeActive still runs its own logic.
        // In Phase 2, that logic moves here.
    }

    func didReturn() {
        // Called on subsequent didBecomeActive while already in foreground.
        // Phase 1: no-op (AppDelegate handles this via its didFinishLaunching guard).
    }

    func handleTerminationRequest(onAsyncTerminationApproved: @escaping @MainActor () -> Void) -> NSApplication.TerminateReply {
        // Already processing an async termination — defer to in-flight handler
        if terminationHandler != nil {
            return .terminateLater
        }

        let handler = TerminationDeciderHandler(
            deciders: createTerminationDeciders(),
            replyToApplicationShouldTerminate: { [weak self] shouldTerminate in
                self?.terminationHandler = nil
                if shouldTerminate {
                    onAsyncTerminationApproved()
                }
                NSApp.reply(toApplicationShouldTerminate: shouldTerminate)
            }
        )
        terminationHandler = handler
        let reply = handler.executeTerminationDeciders()

        if reply == .terminateCancel {
            terminationHandler = nil
        }
        return reply
    }

    // MARK: - Private

    private func createTerminationDeciders() -> [ApplicationTerminationDecider] {
        guard let appDelegate else { return [] }

        let persistor = QuitSurveyUserDefaultsPersistor(keyValueStore: appDelegate.keyValueStore)

        let deciders: [ApplicationTerminationDecider?] = [
            QuitSurveyAppTerminationDecider(
                featureFlagger: appDelegate.featureFlagger,
                dataClearingPreferences: appDelegate.dataClearingPreferences,
                downloadManager: appDelegate.downloadManager,
                installDate: AppDelegate.firstLaunchDate,
                persistor: persistor,
                reinstallUserDetection: DefaultReinstallUserDetection(keyValueStore: appDelegate.keyValueStore),
                showQuitSurvey: { [weak appDelegate] in
                    guard let appDelegate else { return }
                    let presenter = QuitSurveyPresenter(
                        windowControllersManager: appDelegate.windowControllersManager,
                        persistor: persistor
                    )
                    await presenter.showSurvey()
                }
            ),

            ActiveDownloadsAppTerminationDecider(
                downloadManager: appDelegate.downloadManager,
                downloadListCoordinator: appDelegate.downloadListCoordinator
            ),

            makeWarnBeforeQuitDecider(),

            .perform { [weak appDelegate] in
                appDelegate?.updateController?.handleAppTermination()
            },

            .perform { [weak appDelegate] in
                appDelegate?.stateRestorationManager?.applicationWillTerminate()
            },

            appDelegate.autoClearHandler,

            .terminationDecider { [weak appDelegate] _ in
                guard let appDelegate else { return .sync(.next) }
                return .async(Task {
                    await appDelegate.privacyStats.handleAppTermination()
                    return .next
                })
            },

            .perform {
                NSApp.visibleWindows.forEach { $0.close() }
            }
        ]

        return deciders.compactMap { $0 }
    }

    private func makeWarnBeforeQuitDecider() -> ApplicationTerminationDecider? {
        guard let appDelegate else { return nil }

        let willShowAutoClearWarning = appDelegate.dataClearingPreferences.isAutoClearEnabled
            && appDelegate.dataClearingPreferences.isWarnBeforeClearingEnabled

        let hasWindow = appDelegate.windowControllersManager.lastKeyMainWindowController?.window != nil

        guard appDelegate.featureFlagger.isFeatureOn(.warnBeforeQuit),
              !willShowAutoClearWarning,
              hasWindow,
              let currentEvent = NSApp.currentEvent else { return nil }

        guard let manager = WarnBeforeQuitManager(
            currentEvent: currentEvent,
            action: .quit,
            isWarningEnabled: { [weak appDelegate] in
                appDelegate?.tabsPreferences.warnBeforeQuitting ?? false
            },
            isPhysicalKeyPress: WarnBeforeQuitManager.makePhysicalKeyPressCheck(for: currentEvent)
        ) else { return nil }

        let presenter = WarnBeforeQuitOverlayPresenter(
            startupPreferences: appDelegate.startupPreferences,
            buttonHandlers: [.dontShowAgain: { [weak appDelegate] in
                PixelKit.fire(GeneralPixel.warnBeforeQuitDontShowAgain, frequency: .standard)
                appDelegate?.tabsPreferences.warnBeforeQuitting = false
            }],
            onHoverChange: { [weak manager] isHovering in
                manager?.setMouseHovering(isHovering)
            }
        )

        presenter.subscribe(to: manager.stateStream)
        return manager
    }

}
