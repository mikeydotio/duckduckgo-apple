//
//  PairingV2CoordinatorTests.swift
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

import Security
import XCTest

@testable import DDGSync

final class PairingV2CoordinatorTests: XCTestCase {

    func testWhenNativeJoinerReceivesThirdPartyRecoveryCodeThenDelegatesUpgradeToSyncService() async throws {
        let dependencies = MockSyncDependencies()
        let upgradeCoordinator = ThirdPartyAccountUpgradeCoordinatingMock()
        dependencies.createThirdPartyAccountUpgradeCoordinatorStub = upgradeCoordinator
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = nil

        let syncService = DDGSync(dataProvidersSource: MockDataProvidersSource(), dependencies: dependencies)
        let messageExchanger = PairingV2MessageExchangingMock()
        let messageCrypto = PairingV2MessageCrypto()
        let peerKeyPair = try PairingV2KeyPairFactory.makeKeyPair(channelID: "peer-channel")
        let coordinator = PairingV2Coordinator(syncService: syncService,
                                               messageExchanger: messageExchanger,
                                               messageCrypto: messageCrypto,
                                               deviceName: "Mac",
                                               deviceType: "desktop",
                                               flags: PairingV2RolloutFlags(isV2ScanningEnabled: true, isV2CodeEnabled: true))

        try await coordinator.startScanning(qrPayload: .init(channelId: peerKeyPair.channelID, publicKey: peerKeyPair.publicKey))
        let hello = try localHello(from: messageExchanger, peerPrivateKey: peerKeyPair.privateKey, messageCrypto: messageCrypto)

        messageExchanger.fetchMessagesStub = [
            .init(seq: 1,
                  version: PairingV2ProtocolVersion.current,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeAvailable(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
                                                 name: "Peer",
                                                 kind: .thirdParty,
                                                 userId: "third-party-user")),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]
        try await coordinator.pollOnce()
        XCTAssertEqual(
            coordinator.state,
            .joinerWaitingForRecoveryCode(
                .init(localClient: .init(name: "Mac", kind: .ddg, hasAccount: false, isPresenter: false),
                      channelID: peerKeyPair.channelID,
                      peerStatus: .recoveryCodeAvailable(name: "Peer", kind: .thirdParty, userId: "third-party-user"))
            )
        )

        let recoveryCode = "third-party-recovery-code"
        messageExchanger.fetchMessagesStub = [
            .init(seq: 2,
                  version: PairingV2ProtocolVersion.current,
                  payload: try messageCrypto.encrypt(
                    .recoveryCodeResponse(.init(recoveryCode: recoveryCode)),
                    recipientPublicKey: hello.publicKey,
                    senderChannelID: peerKeyPair.channelID).payload)
        ]
        try await coordinator.pollOnce()

        XCTAssertEqual(upgradeCoordinator.upgradeThirdPartyAccountCalls.map(\.recoveryCode), [recoveryCode])
        XCTAssertEqual(upgradeCoordinator.upgradeThirdPartyAccountCalls.first?.deviceName, "Mac")
        XCTAssertEqual(upgradeCoordinator.upgradeThirdPartyAccountCalls.first?.deviceType, "desktop")
        XCTAssertEqual(coordinator.completedRegisteredDevices?.map(\.id), [RegisteredDevice.mock.id])
        XCTAssertEqual(coordinator.completedRegisteredDevices?.map(\.name), [RegisteredDevice.mock.name])
        XCTAssertEqual(coordinator.completedRegisteredDevices?.map(\.type), [RegisteredDevice.mock.type])
        XCTAssertEqual(coordinator.state, .completed(.loggedIn))
        XCTAssertEqual((dependencies.secureStore as? SecureStorageStub)?.theAccount?.userId, SyncAccount.mock.userId)
        XCTAssertEqual((dependencies.secureStore as? SecureStorageStub)?.theScopedPassword, Data(repeating: 1, count: 32))
    }

    private func localHello(from messageExchanger: PairingV2MessageExchangingMock,
                            peerPrivateKey: SecKey,
                            messageCrypto: PairingV2MessageCrypto) throws -> PairingV2HelloMessage {
        let encryptedHello = try XCTUnwrap(messageExchanger.sendCalls.first?.messages.first)
        let message = try XCTUnwrap(try messageCrypto.decrypt(encryptedHello, privateKey: peerPrivateKey))
        guard case .hello(let hello) = message else {
            XCTFail("Expected local hello")
            throw PairingV2Error.unexpectedEvent("Expected local hello")
        }
        return hello
    }
}
