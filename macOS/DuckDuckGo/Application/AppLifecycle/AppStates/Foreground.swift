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

    let dependencies: AppDependencies
    private var terminationHandler: TerminationDeciderHandler?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
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
        let persistor = QuitSurveyUserDefaultsPersistor(keyValueStore: dependencies.stores.keyValueStore)

        let deciders: [ApplicationTerminationDecider?] = [
            QuitSurveyAppTerminationDecider(
                featureFlagger: dependencies.featureFlags.featureFlagger,
                dataClearingPreferences: dependencies.preferences.dataClearingPreferences,
                downloadManager: dependencies.services.downloadManager,
                installDate: AppDelegate.firstLaunchDate,
                persistor: persistor,
                reinstallUserDetection: DefaultReinstallUserDetection(keyValueStore: dependencies.stores.keyValueStore),
                showQuitSurvey: { [weak self] in
                    guard let self else { return }
                    let presenter = QuitSurveyPresenter(
                        windowControllersManager: self.dependencies.ui.windowControllersManager,
                        persistor: persistor
                    )
                    await presenter.showSurvey()
                }
            ),

            ActiveDownloadsAppTerminationDecider(
                downloadManager: dependencies.services.downloadManager,
                downloadListCoordinator: dependencies.services.downloadListCoordinator
            ),

            makeWarnBeforeQuitDecider(),

            .perform { [weak self] in
                self?.dependencies.services.updateController?.handleAppTermination()
            },

            .perform { [weak self] in
                self?.dependencies.services.stateRestorationManager?.applicationWillTerminate()
            },

            dependencies.services.autoClearHandler,

            .terminationDecider { [weak self] _ in
                guard let self else { return .sync(.next) }
                return .async(Task {
                    await self.dependencies.services.privacyStats.handleAppTermination()
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
        let willShowAutoClearWarning = dependencies.preferences.dataClearingPreferences.isAutoClearEnabled
            && dependencies.preferences.dataClearingPreferences.isWarnBeforeClearingEnabled

        let hasWindow = dependencies.ui.windowControllersManager.lastKeyMainWindowController?.window != nil

        guard dependencies.featureFlags.featureFlagger.isFeatureOn(.warnBeforeQuit),
              !willShowAutoClearWarning,
              hasWindow,
              let currentEvent = NSApp.currentEvent else { return nil }

        guard let manager = WarnBeforeQuitManager(
            currentEvent: currentEvent,
            action: .quit,
            isWarningEnabled: { [weak self] in
                self?.dependencies.preferences.tabsPreferences.warnBeforeQuitting ?? false
            },
            isPhysicalKeyPress: WarnBeforeQuitManager.makePhysicalKeyPressCheck(for: currentEvent)
        ) else { return nil }

        let presenter = WarnBeforeQuitOverlayPresenter(
            startupPreferences: dependencies.preferences.startupPreferences,
            buttonHandlers: [.dontShowAgain: { [weak self] in
                PixelKit.fire(GeneralPixel.warnBeforeQuitDontShowAgain, frequency: .standard)
                self?.dependencies.preferences.tabsPreferences.warnBeforeQuitting = false
            }],
            onHoverChange: { [weak manager] isHovering in
                manager?.setMouseHovering(isHovering)
            }
        )

        presenter.subscribe(to: manager.stateStream)
        return manager
    }

}
