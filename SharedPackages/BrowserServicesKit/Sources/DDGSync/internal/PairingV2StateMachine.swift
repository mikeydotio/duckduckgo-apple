//
//  PairingV2StateMachine.swift
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

enum PairingV2DeviceKind: String, Codable, Equatable {
    case ddg
    case thirdParty = "3party"
}

struct PairingV2LocalClient: Equatable {
    let kind: PairingV2DeviceKind
    let hasAccount: Bool
    let isPresenter: Bool
    let userId: String?

    init(kind: PairingV2DeviceKind, hasAccount: Bool, isPresenter: Bool, userId: String? = nil) {
        self.kind = kind
        self.hasAccount = hasAccount
        self.isPresenter = isPresenter
        self.userId = userId
    }
}

struct PairingV2PeerStatus: Equatable {
    let kind: PairingV2DeviceKind
    let hasAccount: Bool
    let userId: String?

    static func recoveryCodeAvailable(kind: PairingV2DeviceKind, userId: String? = nil) -> PairingV2PeerStatus {
        PairingV2PeerStatus(kind: kind, hasAccount: true, userId: userId)
    }

    static func recoveryCodeRequest(kind: PairingV2DeviceKind) -> PairingV2PeerStatus {
        PairingV2PeerStatus(kind: kind, hasAccount: false, userId: nil)
    }
}

enum PairingV2ScannedCode: Equatable {
    case v1Linking
    case v2Linking(channelID: String)
    case recoveryCode(kind: PairingV2DeviceKind, code: String)
    case unknown
}

struct PairingV2RolloutFlags: Equatable {
    let isV2ScanningEnabled: Bool
    let isV2CodeEnabled: Bool
}

struct PairingV2Session: Equatable {
    let localClient: PairingV2LocalClient
    let channelID: String?
    let peerStatus: PairingV2PeerStatus?
    let purpose: String

    init(localClient: PairingV2LocalClient, channelID: String?, peerStatus: PairingV2PeerStatus? = nil, purpose: String = "ai_chats") {
        self.localClient = localClient
        self.channelID = channelID
        self.peerStatus = peerStatus
        self.purpose = purpose
    }

    func withPeerStatus(_ peerStatus: PairingV2PeerStatus) -> PairingV2Session {
        PairingV2Session(localClient: localClient, channelID: channelID, peerStatus: peerStatus, purpose: purpose)
    }
}

enum PairingV2State: Equatable {
    enum Completion: Equatable {
        case recoveryCodeSent
        case loggedIn
    }

    case idle
    case waitingForPeerHello(PairingV2Session)
    case waitingForPeerStatus(PairingV2Session)
    case validatingAccountCanHostNativeJoiner(PairingV2Session)
    case hostPreparingRecoveryCode(PairingV2Session, credentialKind: PairingV2DeviceKind)
    case hostSendingRecoveryCode(PairingV2Session, recoveryCode: String)
    case joinerWaitingForRecoveryCode(PairingV2Session)
    case joinerLoggingIn(PairingV2Session, recoveryCode: String)
    case completed(Completion)
    case failed(PairingV2Error)
}

enum PairingV2Event: Equatable {
    case presentCodeRequested(localClient: PairingV2LocalClient, flags: PairingV2RolloutFlags)
    case scannedCode(PairingV2ScannedCode, localClient: PairingV2LocalClient, flags: PairingV2RolloutFlags)
    case receivedHello(PairingV2HelloMessage)
    case receivedPeerStatus(PairingV2PeerStatus)
    case nativeCredentialAbsenceValidated
    case nativeCredentialAlreadyPresent
    case recoveryCodePrepared(String)
    case recoveryCodeSent
    case receivedRecoveryCode(String)
    case loginSucceeded
    case failed(PairingV2Error)
}

enum PairingV2Command: Equatable {
    case openV2Channel(channelID: String?)
    case stopPolling
    case sendHello
    case sendPeerStatus(PairingV2PeerStatus)
    case prepareRecoveryCode(credentialKind: PairingV2DeviceKind, purpose: String)
    case sendRecoveryCode(String)
    case loginWithRecoveryCode(String)
    case abort(PairingV2Error)
}

enum PairingV2Error: Error, Equatable {
    case v2ScanningDisabled
    case unknownCode
    case incompatibleRecoveryCode(scanningKind: PairingV2DeviceKind, codeKind: PairingV2DeviceKind)
    case unexpectedEvent(String)
    case nativeCredentialAlreadyPresent
    case recoveryCodePreparationFailed
    case recoveryCodeSendFailed
    case loginFailed
    case recoveryCodeDenied
    case recoveryCodeUnavailable
    case sameAccount
    case unsupportedVersion(String)
    case unsupportedFlow(String)
    case cancelled
}

enum PairingV2RoleDecision: Equatable {
    case host(joinerKind: PairingV2DeviceKind, requiresNativeCredentialAbsenceValidation: Bool)
    case joiner(hostKind: PairingV2DeviceKind)
}

enum PairingV2RoleElection {

    static func decideRole(localClient: PairingV2LocalClient, peerStatus: PairingV2PeerStatus) -> PairingV2RoleDecision {
        let peerKind = peerStatus.kind
        let peerHasAccount = peerStatus.hasAccount

        if peerHasAccount {
            if !localClient.hasAccount {
                return .joiner(hostKind: peerKind)
            }

            if localClient.kind != peerKind {
                return localClient.kind == .ddg
                    ? .host(joinerKind: peerKind, requiresNativeCredentialAbsenceValidation: false)
                    : .joiner(hostKind: peerKind)
            }

            return localClient.isPresenter
                ? .host(joinerKind: peerKind, requiresNativeCredentialAbsenceValidation: false)
                : .joiner(hostKind: peerKind)
        }

        if localClient.hasAccount {
            return .host(
                joinerKind: peerKind,
                requiresNativeCredentialAbsenceValidation: localClient.kind == .thirdParty && peerKind == .ddg
            )
        }

        if localClient.kind != peerKind {
            return localClient.kind == .ddg
                ? .host(joinerKind: peerKind, requiresNativeCredentialAbsenceValidation: false)
                : .joiner(hostKind: peerKind)
        }

        return localClient.isPresenter
            ? .host(joinerKind: peerKind, requiresNativeCredentialAbsenceValidation: false)
            : .joiner(hostKind: peerKind)
    }
}

struct PairingV2StateMachine {

    private(set) var state: PairingV2State = .idle

    mutating func handle(_ event: PairingV2Event) -> [PairingV2Command] {
        switch event {
        case .presentCodeRequested:
            return fail(with: .unsupportedFlow("Pairing V2 code presentation is not implemented"))

        case .scannedCode(let scannedCode, let localClient, let flags):
            return handleScannedCode(scannedCode, localClient: localClient, flags: flags)

        case .receivedHello(let message):
            return handleReceivedHello(message)

        case .receivedPeerStatus(let peerStatus):
            return handleReceivedPeerStatus(peerStatus)

        case .nativeCredentialAbsenceValidated:
            return handleNativeCredentialAbsenceValidated()

        case .nativeCredentialAlreadyPresent:
            return fail(with: .nativeCredentialAlreadyPresent)

        case .recoveryCodePrepared(let recoveryCode):
            return handleRecoveryCodePrepared(recoveryCode)

        case .recoveryCodeSent:
            return handleRecoveryCodeSent()

        case .receivedRecoveryCode(let recoveryCode):
            return handleReceivedRecoveryCode(recoveryCode)

        case .loginSucceeded:
            return handleLoginSucceeded()

        case .failed(let error):
            return fail(with: error)
        }
    }

    private mutating func handleScannedCode(_ scannedCode: PairingV2ScannedCode,
                                            localClient: PairingV2LocalClient,
                                            flags: PairingV2RolloutFlags) -> [PairingV2Command] {
        switch scannedCode {
        case .v1Linking:
            return fail(with: .unsupportedFlow("V1 fallback is handled outside Pairing V2"))

        case .v2Linking(let channelID):
            guard flags.isV2ScanningEnabled else {
                return fail(with: .v2ScanningDisabled)
            }

            guard localClient.kind == .ddg, localClient.hasAccount else {
                return fail(with: .unsupportedFlow("Pairing V2 scanning requires an existing native account in this slice"))
            }

            let session = PairingV2Session(localClient: localClient, channelID: channelID)
            state = .waitingForPeerStatus(session)

            let commands: [PairingV2Command] = [
                .openV2Channel(channelID: nil),
                .sendHello,
                .sendPeerStatus(Self.statusMessage(for: localClient))
            ]
            return commands

        case .recoveryCode(let codeKind, _):
            guard codeKind == localClient.kind else {
                return fail(with: .incompatibleRecoveryCode(scanningKind: localClient.kind, codeKind: codeKind))
            }

            return fail(with: .unsupportedFlow("Pairing V2 recovery-code scanning is not implemented"))

        case .unknown:
            return fail(with: .unknownCode)
        }
    }

    private mutating func handleReceivedHello(_ message: PairingV2HelloMessage) -> [PairingV2Command] {
        guard Self.supports(version: message.version) else {
            return fail(with: .unsupportedVersion(message.version))
        }

        guard case .waitingForPeerHello(let session) = state else {
            return fail(with: .unexpectedEvent("scanner received hello after sending scan hello; simultaneous scan handling is out of scope"))
        }

        state = .waitingForPeerStatus(session)
        return [.sendPeerStatus(Self.statusMessage(for: session.localClient))]
    }

    private mutating func handleReceivedPeerStatus(_ peerStatus: PairingV2PeerStatus) -> [PairingV2Command] {
        guard case .waitingForPeerStatus(let session) = state else {
            return fail(with: .unexpectedEvent("peer status received before channel hierarchy was ready"))
        }

        if peerStatus.hasAccount,
           let peerUserId = peerStatus.userId,
           let localUserId = session.localClient.userId,
           peerUserId == localUserId {
            return fail(with: .sameAccount)
        }

        let updatedSession = session.withPeerStatus(peerStatus)
        switch PairingV2RoleElection.decideRole(localClient: updatedSession.localClient, peerStatus: peerStatus) {
        case .host(_, true):
            return fail(with: .unsupportedFlow("3party host native-joiner validation is not implemented"))

        case .host(let joinerKind, false):
            let credentialKind = Self.recoveryCredentialKind(hostKind: updatedSession.localClient.kind, joinerKind: joinerKind)
            guard updatedSession.localClient.kind == .ddg, credentialKind == .thirdParty else {
                return fail(with: .unsupportedFlow("Pairing V2 native host currently supports only 3party recovery codes"))
            }

            state = .hostPreparingRecoveryCode(updatedSession, credentialKind: credentialKind)
            return [.prepareRecoveryCode(credentialKind: credentialKind, purpose: updatedSession.purpose)]

        case .joiner(let hostKind):
            guard updatedSession.localClient.kind == .ddg, hostKind == .ddg else {
                return fail(with: .unsupportedFlow("Pairing V2 native joiner currently supports only native recovery codes"))
            }

            state = .joinerWaitingForRecoveryCode(updatedSession)
            return []
        }
    }

    private mutating func handleNativeCredentialAbsenceValidated() -> [PairingV2Command] {
        guard case .validatingAccountCanHostNativeJoiner(let session) = state,
              let peerStatus = session.peerStatus else {
            return fail(with: .unexpectedEvent("native credential validation completed outside validation state"))
        }

        let credentialKind = Self.recoveryCredentialKind(hostKind: session.localClient.kind, joinerKind: peerStatus.kind)
        state = .hostPreparingRecoveryCode(session, credentialKind: credentialKind)
        return [.prepareRecoveryCode(credentialKind: credentialKind, purpose: session.purpose)]
    }

    private mutating func handleRecoveryCodePrepared(_ recoveryCode: String) -> [PairingV2Command] {
        guard case .hostPreparingRecoveryCode(let session, _) = state else {
            return fail(with: .unexpectedEvent("recovery code prepared while not hosting"))
        }

        state = .hostSendingRecoveryCode(session, recoveryCode: recoveryCode)
        return [.sendRecoveryCode(recoveryCode)]
    }

    private mutating func handleReceivedRecoveryCode(_ recoveryCode: String) -> [PairingV2Command] {
        guard case .joinerWaitingForRecoveryCode(let session) = state else {
            return fail(with: .unexpectedEvent("recovery code received while not joining"))
        }

        state = .joinerLoggingIn(session, recoveryCode: recoveryCode)
        return [.loginWithRecoveryCode(recoveryCode)]
    }

    private mutating func handleRecoveryCodeSent() -> [PairingV2Command] {
        guard case .hostSendingRecoveryCode = state else {
            return fail(with: .unexpectedEvent("recovery code sent while not sending"))
        }

        state = .completed(.recoveryCodeSent)
        return [.stopPolling]
    }

    private mutating func handleLoginSucceeded() -> [PairingV2Command] {
        guard case .joinerLoggingIn = state else {
            return fail(with: .unexpectedEvent("login succeeded while not logging in"))
        }

        state = .completed(.loggedIn)
        return [.stopPolling]
    }

    private mutating func fail(with error: PairingV2Error) -> [PairingV2Command] {
        state = .failed(error)
        return [.abort(error)]
    }

    private static func statusMessage(for localClient: PairingV2LocalClient) -> PairingV2PeerStatus {
        localClient.hasAccount ? .recoveryCodeAvailable(kind: localClient.kind) : .recoveryCodeRequest(kind: localClient.kind)
    }

    private static func recoveryCredentialKind(hostKind: PairingV2DeviceKind, joinerKind: PairingV2DeviceKind) -> PairingV2DeviceKind {
        if hostKind == .ddg && joinerKind == .thirdParty {
            return .thirdParty
        }
        return hostKind
    }

    private static func supports(version: String) -> Bool {
        guard let majorString = version.split(separator: ".").first, let major = Int(majorString) else {
            return false
        }
        return major == 2
    }
}
