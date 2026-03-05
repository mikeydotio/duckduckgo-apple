//
//  RemoteMessagePromoDelegate.swift
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

import Combine
import Foundation
import RemoteMessaging

/// Promo delegate for remote messages on a specific surface (NTP or tab bar).
/// Observes ActiveRemoteMessageModel and reports eligibility to PromoService.
/// The result flows through show() when the user dismisses or the message disappears.
final class RemoteMessagePromoDelegate: PromoDelegate {

    private let activeRemoteMessageModel: ActiveRemoteMessageModel
    private let surface: RemoteMessageSurfaceType

    private let eligibilitySubject: CurrentValueSubject<Bool, Never>
    private var cancellables = Set<AnyCancellable>()

    /// When set, the Combine subscriber will resume the continuation with .ignored(cooldown: 0)
    /// and skip the eligibility update, ensuring show() returns before eligibility-loss path.
    private var userDidDismissFlag = false

    /// Continuation for show(). Resumed by Combine subscriber (user dismiss) or hide() (natural disappearance).
    private var continuation: CheckedContinuation<PromoResult, Never>?

    var isEligible: Bool { eligibilitySubject.value }
    var isEligiblePublisher: AnyPublisher<Bool, Never> { eligibilitySubject.eraseToAnyPublisher() }

    init(activeRemoteMessageModel: ActiveRemoteMessageModel, surface: RemoteMessageSurfaceType) {
        self.activeRemoteMessageModel = activeRemoteMessageModel
        self.surface = surface
        self.eligibilitySubject = CurrentValueSubject(false)

        let messagePublisher: AnyPublisher<RemoteMessageModel?, Never> = {
            switch surface {
            case .newTabPage:
                return activeRemoteMessageModel.$newTabPageRemoteMessage.eraseToAnyPublisher()
            case .tabBar:
                return activeRemoteMessageModel.$tabBarRemoteMessage.eraseToAnyPublisher()
            default:
                return Just(nil).eraseToAnyPublisher()
            }
        }()

        messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleMessageChange(message)
            }
            .store(in: &cancellables)

        refreshEligibility()
    }

    /// Called by ActiveRemoteMessageModel before clearing remoteMessage on user dismiss.
    /// Sets a flag so the Combine subscriber resumes with .ignored(cooldown: 0) instead of updating eligibility.
    func userDidDismiss() {
        userDidDismissFlag = true
    }

    func refreshEligibility() {
        let message = surface == .newTabPage
            ? activeRemoteMessageModel.newTabPageRemoteMessage
            : activeRemoteMessageModel.tabBarRemoteMessage
        let eligible = message != nil && (message?.content?.isSupported == true)
        eligibilitySubject.send(eligible)
    }

    @MainActor
    /// Note that Remote Messages are unique promos in that they don't wait for this method to show them.
    /// Instead, this method is a "wait for dismissal" hook for the promo that is already visible.
    func show(history: PromoHistoryRecord) async -> PromoResult {
        // handleMessageChange may have already fired before show() ran (e.g. in tests)
        if userDidDismissFlag {
            userDidDismissFlag = false
            return .ignored(cooldown: 0)
        }
        return await withCheckedContinuation { cont in
            continuation = cont
        }
    }

    @MainActor
    func hide() {
        guard let cont = continuation else { return }
        continuation = nil
        userDidDismissFlag = false
        cont.resume(returning: .noChange)
    }

    private func handleMessageChange(_ message: RemoteMessageModel?) {
        let eligible = message != nil && (message?.content?.isSupported == true)

        if userDidDismissFlag {
            if let cont = continuation {
                userDidDismissFlag = false
                continuation = nil
                cont.resume(returning: .ignored(cooldown: 0))
            } else {
                // No continuation yet: show() hasn't run. Keep the flag so show() can return .ignored(cooldown: 0).
                // Still update eligibility so isEligible reflects that the message is gone.
                eligibilitySubject.send(eligible)
            }
            return
        }

        eligibilitySubject.send(eligible)
    }
}
