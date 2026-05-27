//
//  PairingV2Coordinator.swift
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

import Foundation
import os.log

final class PairingV2Coordinator {

    private let syncService: DDGSyncing
    private let transport: PairingV2Transporting
    private let messageCrypto: PairingV2MessageCrypto
    private let deviceName: String
    private let deviceType: String
    private let localKind: PairingV2DeviceKind
    private let flags: PairingV2RolloutFlags

    private var stateMachine = PairingV2StateMachine()
    private var localKeyPair: PairingV2KeyPair?
    private var peerChannelID: String?
    private var peerPublicKey: String?
    private var lastProcessedSequence = 0
    private(set) var completedRegisteredDevices: [RegisteredDevice]?
    private(set) var pendingRecoveryKey: SyncCode.RecoveryKey?

    init(syncService: DDGSyncing,
         transport: PairingV2Transporting,
         messageCrypto: PairingV2MessageCrypto = PairingV2MessageCrypto(),
         deviceName: String,
         deviceType: String,
         localKind: PairingV2DeviceKind = .ddg,
         flags: PairingV2RolloutFlags) {
        self.syncService = syncService
        self.transport = transport
        self.messageCrypto = messageCrypto
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.localKind = localKind
        self.flags = flags
    }

    var state: PairingV2State {
        stateMachine.state
    }

    func startScanning(qrPayload: PairingV2QRCodePayload) async throws {
        let keyPair = try PairingV2KeyPairFactory.makeKeyPair()
        localKeyPair = keyPair
        peerChannelID = qrPayload.channelId
        peerPublicKey = qrPayload.publicKey

        let commands = stateMachine.handle(
            .scannedCode(.v2Linking(channelID: qrPayload.channelId), localClient: localClient(isPresenter: false), flags: flags)
        )
        try await execute(commands)
    }

    func pollOnce() async throws {
        guard let channelID = localKeyPair?.channelID else {
            throw SyncError.failedToPrepareForExchange("Pairing V2 local channel is not ready")
        }

        let messages = try await transport.fetchMessages(from: channelID, after: lastProcessedSequence)
        for message in messages.sorted(by: { $0.seq < $1.seq }) {
            guard !isTerminal else {
                return
            }
            try await handle(message.encryptedMessage, sequence: message.seq)
            lastProcessedSequence = max(lastProcessedSequence, message.seq)
        }
    }

    func pollUntilFinished(timeout: TimeInterval = 60, pollInterval: UInt64 = 1_000_000_000) async throws -> PairingV2State.Completion {
        let timeoutDate = Date().addingTimeInterval(timeout)

        while true {
            switch stateMachine.state {
            case .completed(let completion):
                return completion
            case .failed(let error):
                throw error
            default:
                break
            }

            if Date() > timeoutDate {
                throw SyncError.pollingDidTimeOut
            }

            try await pollOnce()
            try await Task.sleep(nanoseconds: pollInterval)
        }
    }

    func cancel() async {
        _ = stateMachine.handle(.failed(.cancelled))
        await closeLocalChannel()
    }

    func closeLocalChannel() async {
        guard let channelID = localKeyPair?.channelID else {
            return
        }
        try? await transport.closeChannel(channelID)
    }

    private func handle(_ encryptedMessage: PairingV2EncryptedMessage, sequence: Int? = nil) async throws {
        guard let privateKey = localKeyPair?.privateKey else {
            throw SyncError.failedToPrepareForExchange("Pairing V2 private key is not ready")
        }

        guard let message = try messageCrypto.decrypt(encryptedMessage, privateKey: privateKey, expectedSenderChannelID: peerChannelID) else {
            Logger.sync.debug("Pairing V2 dropped unknown message type")
            return
        }
        Logger.sync.debug("Pairing V2 received message: \(message.type, privacy: .public)")

        let commands: [PairingV2Command]
        switch message {
        case .hello(let message):
            commands = stateMachine.handle(.receivedHello(message))
            if !isTerminal {
                peerChannelID = message.channelId
                peerPublicKey = message.publicKey
            }

        case .recoveryCodeAvailable(let message):
            commands = stateMachine.handle(.receivedPeerStatus(.recoveryCodeAvailable(kind: message.kind, userId: message.userId)))

        case .recoveryCodeRequest(let message):
            commands = stateMachine.handle(.receivedPeerStatus(.recoveryCodeRequest(kind: message.kind)))

        case .recoveryCodeResponse(let message):
            let recoveryCode = recoveryCode(from: message)
            commands = stateMachine.handle(.receivedRecoveryCode(recoveryCode))

        case .recoveryCodeDenied:
            commands = stateMachine.handle(.failed(.recoveryCodeDenied))

        case .recoveryCodeUnavailable:
            commands = stateMachine.handle(.failed(.recoveryCodeUnavailable))
        }

        try await execute(commands)
    }

    private func execute(_ commands: [PairingV2Command]) async throws {
        for command in commands {
            try await execute(command)
        }
    }

    private func execute(_ command: PairingV2Command) async throws {
        switch command {
        case .openV2Channel(let channelID):
            let channelID = try channelID ?? requiredLocalChannelID()
            try await transport.openChannel(channelID)

        case .sendHello:
            let keyPair = try requiredLocalKeyPair()
            try await send(.hello(.init(channelId: keyPair.channelID, publicKey: keyPair.publicKey)))

        case .sendPeerStatus(let status):
            try await send(statusMessage(for: status))

        case .prepareRecoveryCode(let credentialKind, let purpose):
            let recoveryCode: String
            do {
                recoveryCode = try await prepareRecoveryCode(credentialKind: credentialKind, purpose: purpose)
            } catch {
                try await execute(stateMachine.handle(.failed(.recoveryCodePreparationFailed)))
                throw PairingV2Error.recoveryCodePreparationFailed
            }
            try await execute(stateMachine.handle(.recoveryCodePrepared(recoveryCode)))

        case .sendRecoveryCode(let recoveryCode):
            do {
                try await sendRecoveryCode(recoveryCode)
            } catch {
                try await execute(stateMachine.handle(.failed(.recoveryCodeSendFailed)))
                throw PairingV2Error.recoveryCodeSendFailed
            }
            try await execute(stateMachine.handle(.recoveryCodeSent))

        case .loginWithRecoveryCode(let recoveryCode):
            do {
                try await login(with: recoveryCode)
            } catch {
                try await execute(stateMachine.handle(.failed(.loginFailed)))
                throw PairingV2Error.loginFailed
            }
            try await execute(stateMachine.handle(.loginSucceeded))

        case .stopPolling:
            await closeLocalChannel()

        case .abort:
            await closeLocalChannel()
        }
    }

    private func send(_ message: PairingV2ApplicationMessage) async throws {
        guard let peerChannelID, let peerPublicKey else {
            throw SyncError.failedToPrepareForExchange("Pairing V2 peer channel is not ready")
        }

        let encryptedMessage = try messageCrypto.encrypt(message, recipientPublicKey: peerPublicKey, senderChannelID: try requiredLocalChannelID())
        Logger.sync.debug("Pairing V2 sending message: \(message.type, privacy: .public) to channel: \(peerChannelID, privacy: .public)")
        try await transport.send([encryptedMessage], to: peerChannelID)
    }

    private func statusMessage(for status: PairingV2PeerStatus) -> PairingV2ApplicationMessage {
        let type = status.hasAccount ? PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable : PairingV2ApplicationMessage.MessageType.recoveryCodeRequest

        return status.hasAccount
            ? .recoveryCodeAvailable(.init(type: type, name: deviceName, kind: status.kind, userId: syncService.account?.userId))
            : .recoveryCodeRequest(.init(type: type, name: deviceName, kind: status.kind))
    }

    private func prepareRecoveryCode(credentialKind: PairingV2DeviceKind, purpose: String) async throws -> String {
        switch credentialKind {
        case .thirdParty:
            return try await syncService.prepareThirdPartyRecoveryCode(purpose: purpose)
        case .ddg:
            guard let recoveryCode = syncService.account?.recoveryCode else {
                throw SyncError.invalidRecoveryKey
            }
            return recoveryCode
        }
    }

    private func sendRecoveryCode(_ recoveryCode: String) async throws {
        let response = PairingV2ApplicationMessage.recoveryCodeResponse(
            .init(recoveryCode: recoveryCode)
        )
        try await send(response)
    }

    private func recoveryCode(from response: PairingV2RecoveryCodeResponseMessage) -> String {
        response.recoveryCode
    }

    private func login(with recoveryCode: String) async throws {
        let syncCode = try SyncCode.decodeBase64String(recoveryCode)
        guard let recovery = syncCode.recovery, let recoveryKey = recovery.legacyRecoveryKey() else {
            throw SyncError.invalidRecoveryKey
        }
        pendingRecoveryKey = recoveryKey
        completedRegisteredDevices = try await syncService.login(recoveryKey, deviceName: deviceName, deviceType: deviceType)
    }

    private func localClient(isPresenter: Bool) -> PairingV2LocalClient {
        PairingV2LocalClient(kind: localKind, hasAccount: syncService.account != nil, isPresenter: isPresenter, userId: syncService.account?.userId)
    }

    private func requiredLocalKeyPair() throws -> PairingV2KeyPair {
        guard let localKeyPair else {
            throw SyncError.failedToPrepareForExchange("Pairing V2 local key pair is not ready")
        }
        return localKeyPair
    }

    private func requiredLocalChannelID() throws -> String {
        try requiredLocalKeyPair().channelID
    }

    private var isTerminal: Bool {
        switch stateMachine.state {
        case .completed, .failed:
            return true
        default:
            return false
        }
    }
}
