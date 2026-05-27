//
//  PairingV2StateMachineTests.swift
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

import XCTest

@testable import DDGSync

final class PairingV2StateMachineTests: XCTestCase {

    func testWhenBothClientsHaveAccountsAndKindsDifferThenNativeBecomesHost() {
        let localClient = makeLocalClient(kind: .ddg, hasAccount: true, isPresenter: false)

        let decision = PairingV2RoleElection.decideRole(
            localClient: localClient,
            peerStatus: .recoveryCodeAvailable(kind: .thirdParty)
        )

        XCTAssertEqual(decision, .host(joinerKind: .thirdParty, requiresNativeCredentialAbsenceValidation: false))
    }

    func testWhenNeitherClientHasAccountAndKindsDifferThenNativeBecomesHost() {
        let localClient = makeLocalClient(kind: .thirdParty, hasAccount: false, isPresenter: true)

        let decision = PairingV2RoleElection.decideRole(
            localClient: localClient,
            peerStatus: .recoveryCodeRequest(kind: .ddg)
        )

        XCTAssertEqual(decision, .joiner(hostKind: .ddg))
    }

    func testWhenClientsHaveSamePriorityThenPresenterBecomesHost() {
        let localClient = makeLocalClient(kind: .ddg, hasAccount: true, isPresenter: true)

        let decision = PairingV2RoleElection.decideRole(
            localClient: localClient,
            peerStatus: .recoveryCodeAvailable(kind: .ddg)
        )

        XCTAssertEqual(decision, .host(joinerKind: .ddg, requiresNativeCredentialAbsenceValidation: false))
    }

    func testWhenThirdPartyAccountHostsNativeJoinerThenNativeCredentialValidationIsRequired() {
        let localClient = makeLocalClient(kind: .thirdParty, hasAccount: true, isPresenter: true)

        let decision = PairingV2RoleElection.decideRole(
            localClient: localClient,
            peerStatus: .recoveryCodeRequest(kind: .ddg)
        )

        XCTAssertEqual(decision, .host(joinerKind: .ddg, requiresNativeCredentialAbsenceValidation: true))
    }

    func testWhenNativeAccountScannerScansV2LinkingCodeThenSendsHelloAndAccountStatus() {
        var stateMachine = PairingV2StateMachine()
        let localClient = makeLocalClient(kind: .ddg, hasAccount: true, isPresenter: false)

        let commands = stateMachine.handle(
            .scannedCode(.v2Linking(channelID: "channel-1"), localClient: localClient, flags: enabledFlags)
        )

        XCTAssertEqual(commands, [
            .openV2Channel(channelID: nil),
            .sendHello,
            .sendPeerStatus(.recoveryCodeAvailable(kind: .ddg))
        ])
        XCTAssertEqual(
            stateMachine.state,
            .waitingForPeerStatus(.init(localClient: localClient, channelID: "channel-1"))
        )
    }

    func testWhenPresenterFlowIsRequestedThenFlowAbortsAsUnsupported() {
        var stateMachine = PairingV2StateMachine()
        let localClient = makeLocalClient(kind: .thirdParty, hasAccount: true, isPresenter: true)
        let error = PairingV2Error.unsupportedFlow("Pairing V2 code presentation is not implemented")

        let commands = stateMachine.handle(.presentCodeRequested(localClient: localClient, flags: enabledFlags))

        XCTAssertEqual(commands, [.abort(error)])
        XCTAssertEqual(stateMachine.state, .failed(error))
    }

    func testWhenNativeWithoutAccountScansV2LinkingCodeThenFlowAbortsAsUnsupported() {
        var stateMachine = PairingV2StateMachine()
        let localClient = makeLocalClient(kind: .ddg, hasAccount: false, isPresenter: false)
        let error = PairingV2Error.unsupportedFlow("Pairing V2 scanning requires an existing native account in this slice")

        let commands = stateMachine.handle(
            .scannedCode(.v2Linking(channelID: "channel-1"), localClient: localClient, flags: enabledFlags)
        )

        XCTAssertEqual(commands, [.abort(error)])
        XCTAssertEqual(stateMachine.state, .failed(error))
    }

    func testWhenScannerReceivesHelloAfterSendingHelloThenFlowAbortsAsScopeCut() {
        var stateMachine = PairingV2StateMachine()
        let localClient = makeLocalClient(kind: .ddg, hasAccount: true, isPresenter: false)

        _ = stateMachine.handle(
            .scannedCode(.v2Linking(channelID: "channel-1"), localClient: localClient, flags: enabledFlags)
        )
        let error = PairingV2Error.unexpectedEvent("scanner received hello after sending scan hello; simultaneous scan handling is out of scope")
        let commands = stateMachine.handle(.receivedHello(.init(channelId: "peer-channel", publicKey: "public-key")))

        XCTAssertEqual(commands, [.abort(error)])
        XCTAssertEqual(stateMachine.state, .failed(error))
    }

    func testWhenHelloHasUnsupportedVersionThenFlowAborts() {
        var stateMachine = PairingV2StateMachine()
        let commands = stateMachine.handle(.receivedHello(.init(channelId: "peer-channel", publicKey: "public-key", version: "3.0")))

        XCTAssertEqual(commands, [.abort(.unsupportedVersion("3.0"))])
        XCTAssertEqual(stateMachine.state, .failed(.unsupportedVersion("3.0")))
    }

    func testWhenNativeScansThirdPartyRecoveryCodeThenFlowAbortsAsIncompatible() {
        var stateMachine = PairingV2StateMachine()
        let localClient = makeLocalClient(kind: .ddg, hasAccount: false, isPresenter: false)

        let commands = stateMachine.handle(
            .scannedCode(.recoveryCode(kind: .thirdParty, code: "recovery-code"), localClient: localClient, flags: enabledFlags)
        )

        XCTAssertEqual(commands, [
            .abort(.incompatibleRecoveryCode(scanningKind: .ddg, codeKind: .thirdParty))
        ])
        XCTAssertEqual(stateMachine.state, .failed(.incompatibleRecoveryCode(scanningKind: .ddg, codeKind: .thirdParty)))
    }

    func testWhenNativeHostReceivesThirdPartyAvailableThenItPreparesThirdPartyRecoveryCode() {
        var stateMachine = PairingV2StateMachine()
        let localClient = makeLocalClient(kind: .ddg, hasAccount: true, isPresenter: false)

        _ = stateMachine.handle(
            .scannedCode(.v2Linking(channelID: "channel-1"), localClient: localClient, flags: enabledFlags)
        )
        let commands = stateMachine.handle(.receivedPeerStatus(.recoveryCodeAvailable(kind: .thirdParty)))

        XCTAssertEqual(commands, [
            .prepareRecoveryCode(credentialKind: .thirdParty, purpose: "ai_chats")
        ])
        XCTAssertEqual(
            stateMachine.state,
            .hostPreparingRecoveryCode(
                .init(localClient: localClient, channelID: "channel-1", peerStatus: .recoveryCodeAvailable(kind: .thirdParty)),
                credentialKind: .thirdParty
            )
        )
    }

    func testWhenPeerAvailableHasSameUserIdAsLocalAccountThenFlowAborts() {
        var stateMachine = PairingV2StateMachine()
        let localClient = makeLocalClient(kind: .ddg, hasAccount: true, isPresenter: false, userId: "same-user")

        _ = stateMachine.handle(
            .scannedCode(.v2Linking(channelID: "channel-1"), localClient: localClient, flags: enabledFlags)
        )
        let commands = stateMachine.handle(.receivedPeerStatus(.recoveryCodeAvailable(kind: .thirdParty, userId: "same-user")))

        XCTAssertEqual(commands, [.abort(.sameAccount)])
        XCTAssertEqual(stateMachine.state, .failed(.sameAccount))
    }

    func testWhenNativeAccountScannerScansNativePresenterThenWaitsForRecoveryCode() {
        var stateMachine = PairingV2StateMachine()
        let localClient = makeLocalClient(kind: .ddg, hasAccount: true, isPresenter: false)

        _ = stateMachine.handle(
            .scannedCode(.v2Linking(channelID: "channel-1"), localClient: localClient, flags: enabledFlags)
        )
        let commands = stateMachine.handle(.receivedPeerStatus(.recoveryCodeAvailable(kind: .ddg)))

        XCTAssertEqual(commands, [])
        XCTAssertEqual(
            stateMachine.state,
            .joinerWaitingForRecoveryCode(
                .init(localClient: localClient, channelID: "channel-1", peerStatus: .recoveryCodeAvailable(kind: .ddg))
            )
        )
    }

    func testWhenNativeJoinerReceivesRecoveryCodeThenLogsIn() {
        var stateMachine = PairingV2StateMachine()
        let localClient = makeLocalClient(kind: .ddg, hasAccount: true, isPresenter: false)

        _ = stateMachine.handle(
            .scannedCode(.v2Linking(channelID: "channel-1"), localClient: localClient, flags: enabledFlags)
        )
        _ = stateMachine.handle(.receivedPeerStatus(.recoveryCodeAvailable(kind: .ddg)))
        let commands = stateMachine.handle(.receivedRecoveryCode("recovery-code"))

        XCTAssertEqual(commands, [.loginWithRecoveryCode("recovery-code")])
        XCTAssertEqual(
            stateMachine.state,
            .joinerLoggingIn(
                .init(localClient: localClient, channelID: "channel-1", peerStatus: .recoveryCodeAvailable(kind: .ddg)),
                recoveryCode: "recovery-code"
            )
        )
    }

    func testWhenRecoveryCodeSentFromSendingStateThenCompletesAndStopsPolling() {
        var stateMachine = PairingV2StateMachine()
        let localClient = makeLocalClient(kind: .ddg, hasAccount: true, isPresenter: false)

        _ = stateMachine.handle(.scannedCode(.v2Linking(channelID: "channel-1"), localClient: localClient, flags: enabledFlags))
        _ = stateMachine.handle(.receivedPeerStatus(.recoveryCodeRequest(kind: .thirdParty)))
        _ = stateMachine.handle(.recoveryCodePrepared("recovery-code"))
        let commands = stateMachine.handle(.recoveryCodeSent)

        XCTAssertEqual(commands, [.stopPolling])
        XCTAssertEqual(stateMachine.state, .completed(.recoveryCodeSent))
    }

    func testWhenCompatibleRecoveryCodeIsScannedThenFlowAbortsAsUnsupported() {
        var stateMachine = PairingV2StateMachine()
        let localClient = makeLocalClient(kind: .ddg, hasAccount: true, isPresenter: false)
        let error = PairingV2Error.unsupportedFlow("Pairing V2 recovery-code scanning is not implemented")

        let commands = stateMachine.handle(
            .scannedCode(.recoveryCode(kind: .ddg, code: "recovery-code"), localClient: localClient, flags: enabledFlags)
        )

        XCTAssertEqual(commands, [.abort(error)])
        XCTAssertEqual(stateMachine.state, .failed(error))
    }

    private var enabledFlags: PairingV2RolloutFlags {
        PairingV2RolloutFlags(isV2ScanningEnabled: true, isV2CodeEnabled: true)
    }

    private func makeLocalClient(kind: PairingV2DeviceKind,
                                 hasAccount: Bool,
                                 isPresenter: Bool,
                                 userId: String? = nil) -> PairingV2LocalClient {
        PairingV2LocalClient(kind: kind, hasAccount: hasAccount, isPresenter: isPresenter, userId: userId)
    }
}
