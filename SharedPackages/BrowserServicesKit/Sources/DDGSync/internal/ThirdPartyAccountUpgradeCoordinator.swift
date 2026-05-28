//
//  ThirdPartyAccountUpgradeCoordinator.swift
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

import DDGSyncCrypto
import Foundation
import os.log

protocol ThirdPartyAccountUpgradeCoordinating {
    func upgradeThirdPartyAccountToDefaultCredential(_ recoveryCode: String,
                                                     deviceName: String,
                                                     deviceType: String) async throws -> UpgradedThirdPartyAccount
}

struct UpgradedThirdPartyAccount {
    let account: SyncAccount
    let devices: [RegisteredDevice]
    let scopedPassword: Data
    let protectedKeys: [ProtectedKey]
}

struct ThirdPartyAccountUpgradeCoordinator: ThirdPartyAccountUpgradeCoordinating {

    private enum LoginScope {
        static let defaultCredential = "sync"
        static let thirdPartyAccountManagement = "ai_chats"
    }

    let endpoints: Endpoints
    let api: RemoteAPIRequestCreating
    let crypter: CryptingInternal
    let scopedAccess: ScopedAccessCredentialManaging

    private let jweCompactCodec = JWECompactCodec()
    private let scopedAccessCredentialEnvelope = ScopedAccessCredentialEnvelope()

    func upgradeThirdPartyAccountToDefaultCredential(_ recoveryCode: String,
                                                     deviceName: String,
                                                     deviceType: String) async throws -> UpgradedThirdPartyAccount {
        let recoveryKey = try decodeThirdPartyRecoveryKey(from: recoveryCode)
        let scopedPassword = try decodeScopedPassword(from: recoveryKey)

        let thirdPartyLogin: ThirdPartyLogin
        do {
            thirdPartyLogin = try await loginThirdPartyCredential(recoveryKey,
                                                                  scopedPassword: scopedPassword,
                                                                  deviceName: deviceName,
                                                                  deviceType: deviceType)
        } catch {
            Logger.sync.error("3party account upgrade failed during temporary 3party login: \(String(reflecting: error), privacy: .public)")
            throw error
        }

        let thirdPartyAccount = SyncAccount(deviceId: thirdPartyLogin.deviceId,
                                            deviceName: deviceName,
                                            deviceType: deviceType,
                                            userId: recoveryKey.userId,
                                            primaryKey: scopedPassword,
                                            secretKey: thirdPartyLogin.mainKey,
                                            token: thirdPartyLogin.token,
                                            state: .addingNewDevice)

        let accessCredentials = try await fetchAccessCredentials(for: thirdPartyAccount)
        guard !accessCredentials.contains(where: { $0.id == SyncCredentialID.defaultCredential }) else {
            Logger.sync.error("3party account upgrade found an existing native access credential")
            throw PairingV2Error.nativeCredentialAlreadyPresent
        }

        let thirdPartyProtectedKeys = try await fetchUsableThirdPartyProtectedKeys(for: thirdPartyAccount)
        let accountKeys = try generateDefaultCredentialMaterial(userId: recoveryKey.userId)
        let defaultCredentialMainKey = ScopedAccessKeyDerivation.mainKey(from: accountKeys.primaryKey, userID: recoveryKey.userId)
        let rewrappedProtectedKeys = try rewrapThirdPartyProtectedKeys(thirdPartyProtectedKeys,
                                                                       fromWrappingKey: thirdPartyLogin.mainKey,
                                                                       toAccountSecretKey: accountKeys.secretKey)
        let encryptedThirdPartyCredential = try encryptThirdPartyCredential(scopedPassword,
                                                                           defaultCredentialMainKey: defaultCredentialMainKey)
        try await postDefaultAccessCredential(token: thirdPartyLogin.token,
                                             hashedPassword: thirdPartyLogin.hashedPassword,
                                             credentialHashedPassword: accountKeys.passwordHash.base64EncodedString(),
                                             protectedEncryptionKey: accountKeys.protectedSecretKey.base64EncodedString(),
                                             encryptedThirdPartyCredential: encryptedThirdPartyCredential,
                                             keys: rewrappedProtectedKeys)

        let nativeLogin = try await loginDefaultCredential(userId: recoveryKey.userId,
                                                           accountKeys: accountKeys,
                                                           deviceName: deviceName,
                                                           deviceType: deviceType)
        return UpgradedThirdPartyAccount(account: nativeLogin.account,
                                         devices: nativeLogin.devices,
                                         scopedPassword: scopedPassword,
                                         protectedKeys: rewrappedProtectedKeys)
    }

    private func decodeThirdPartyRecoveryKey(from recoveryCode: String) throws -> SyncCode.RecoveryKeyV2 {
        let syncCode = try SyncCode.decodeBase64String(recoveryCode)
        guard case .v2(let recoveryKey) = syncCode.recovery,
              recoveryKey.cid == SyncCode.RecoveryKeyV2.thirdPartyCredentialId else {
            Logger.sync.error("3party account upgrade received an invalid recovery key")
            throw SyncError.invalidRecoveryKey
        }
        return recoveryKey
    }

    private func decodeScopedPassword(from recoveryKey: SyncCode.RecoveryKeyV2) throws -> Data {
        guard let scopedPassword = Base64URL.decode(recoveryKey.secret), !scopedPassword.isEmpty else {
            Logger.sync.error("3party account upgrade received an invalid recovery code secret")
            throw SyncError.invalidRecoveryKey
        }
        return scopedPassword
    }

    private func fetchAccessCredentials(for account: SyncAccount) async throws -> [AccessCredential] {
        do {
            return try await scopedAccess.fetchAccessCredentials(account)
        } catch {
            Logger.sync.error("3party account upgrade failed to fetch access credentials: \(String(reflecting: error), privacy: .public)")
            throw error
        }
    }

    private func fetchUsableThirdPartyProtectedKeys(for account: SyncAccount) async throws -> [ProtectedKey] {
        let protectedKeys: [ProtectedKey]
        do {
            protectedKeys = try await scopedAccess.fetchProtectedKeys(account)
        } catch {
            Logger.sync.error("3party account upgrade failed to fetch protected keys: \(String(reflecting: error), privacy: .public)")
            throw error
        }

        let thirdPartyProtectedKeys = protectedKeys
            .filter { $0.encryptedWith == SyncCode.RecoveryKeyV2.thirdPartyCredentialId }
            .removingDuplicateWrappingIdentities()
        guard !thirdPartyProtectedKeys.isEmpty else {
            Logger.sync.error("3party account upgrade found no usable 3party protected keys")
            throw SyncError.invalidDataInResponse("3party account has no usable protected keys to upgrade")
        }
        return thirdPartyProtectedKeys
    }

    private func generateDefaultCredentialMaterial(userId: String) throws -> AccountCreationKeys {
        do {
            return try crypter.createAccountCreationKeys(userId: userId, password: UUID().uuidString)
        } catch {
            Logger.sync.error("3party account upgrade failed to generate native credential material: \(String(reflecting: error), privacy: .public)")
            throw error
        }
    }

    private func rewrapThirdPartyProtectedKeys(_ keys: [ProtectedKey],
                                               fromWrappingKey wrappingKey: Data,
                                               toAccountSecretKey accountSecretKey: Data) throws -> [ProtectedKey] {
        do {
            return try keys.map { key in
                let decryptedPrivateKey = try jweCompactCodec.decryptDirect(
                    token: key.encryptedPrivateKey,
                    contentEncryptionKey: wrappingKey)
                let rewrappedEncryptedPrivateKey = try crypter.encrypt(decryptedPrivateKey, using: accountSecretKey)
                return ProtectedKey(kid: key.kid,
                                    encryptedPrivateKey: Base64URL.encode(rewrappedEncryptedPrivateKey),
                                    publicKey: key.publicKey,
                                    encryptedWith: SyncCredentialID.defaultCredential,
                                    purpose: key.purpose)
            }
        } catch {
            Logger.sync.error("3party account upgrade failed to rewrap protected keys: \(String(reflecting: error), privacy: .public)")
            throw error
        }
    }

    private func encryptThirdPartyCredential(_ scopedPassword: Data, defaultCredentialMainKey: Data) throws -> String {
        do {
            let encryptedCredential = try scopedAccessCredentialEnvelope.encryptScopedPassword(
                scopedPassword,
                using: defaultCredentialMainKey,
                kid: SyncCredentialID.defaultCredential)
            return encryptedCredential
        } catch {
            Logger.sync.error("3party account upgrade failed to encrypt the 3party credential: \(String(reflecting: error), privacy: .public)")
            throw error
        }
    }

    private func loginThirdPartyCredential(_ recoveryKey: SyncCode.RecoveryKeyV2,
                                           scopedPassword: Data,
                                           deviceName: String,
                                           deviceType: String) async throws -> ThirdPartyLogin {
        let deviceId = UUID().uuidString
        let hashedPassword = ScopedAccessKeyDerivation.hashedPassword(from: scopedPassword, userID: recoveryKey.userId)
        let params = ThirdPartyLoginParameters(userId: recoveryKey.userId,
                                               hashedPassword: hashedPassword,
                                               deviceId: deviceId,
                                               deviceName: deviceName.base64EncodedUTF8(),
                                               deviceType: deviceType.base64EncodedUTF8(),
                                               scope: LoginScope.thirdPartyAccountManagement)
        let requestJson = try JSONEncoder.snakeCaseKeys.encode(params)
        let request = api.createUnauthenticatedJSONRequest(url: endpoints.login, method: .post, json: requestJson)
        let result = try await request.execute()
        guard let body = result.data else {
            throw SyncError.noResponseBody
        }
        let loginResult = try JSONDecoder.snakeCaseKeys.decode(ThirdPartyLoginResult.self, from: body)
        return ThirdPartyLogin(deviceId: deviceId,
                               token: loginResult.token,
                               hashedPassword: hashedPassword,
                               mainKey: ScopedAccessKeyDerivation.mainKey(from: scopedPassword, userID: recoveryKey.userId),
                               devices: loginResult.registeredDevices)
    }

    private func postDefaultAccessCredential(token: String,
                                             hashedPassword: String,
                                             credentialHashedPassword: String,
                                             protectedEncryptionKey: String,
                                             encryptedThirdPartyCredential: String,
                                             keys: [ProtectedKey]) async throws {
        let params = CreateDefaultCredentialParameters(
            hashedPassword: hashedPassword,
            credentialHashedPassword: credentialHashedPassword,
            protectedEncryptionKey: protectedEncryptionKey,
            encrypted3partyCredential: encryptedThirdPartyCredential,
            keys: keys
        )
        let requestJson = try JSONEncoder.snakeCaseKeys.encode(params)
        let request = api.createAuthenticatedJSONRequest(url: accessCredentialURL(id: SyncCredentialID.defaultCredential),
                                                         method: .post,
                                                         authToken: token,
                                                         json: requestJson)
        let result: HTTPResult
        do {
            result = try await request.execute()
        } catch SyncError.unexpectedStatusCode(let statusCode) where statusCode == 409 {
            Logger.sync.error("3party account upgrade hit a native credential creation conflict")
            throw PairingV2Error.nativeCredentialAlreadyPresent
        } catch {
            Logger.sync.error("3party account upgrade failed to create the native access credential: \(String(reflecting: error), privacy: .public)")
            throw error
        }
        guard result.response.statusCode != 409 else {
            Logger.sync.error("3party account upgrade hit a native credential creation conflict")
            throw PairingV2Error.nativeCredentialAlreadyPresent
        }
        guard [200, 201, 204].contains(result.response.statusCode) else {
            Logger.sync.error("3party account upgrade native credential creation returned unexpected status=\(result.response.statusCode, privacy: .public)")
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }
    }

    private func loginDefaultCredential(userId: String,
                                        accountKeys: AccountCreationKeys,
                                        deviceName: String,
                                        deviceType: String) async throws -> LoginResult {
        let deviceId = UUID().uuidString
        let loginInfo = try crypter.extractLoginInfo(
            recoveryKey: SyncCode.RecoveryKey(userId: userId, primaryKey: accountKeys.primaryKey))
        let params = DefaultCredentialLoginParameters(
            userId: userId,
            hashedPassword: accountKeys.passwordHash.base64EncodedString(),
            deviceId: deviceId,
            deviceName: try crypter.encryptAndBase64Encode(deviceName, using: accountKeys.primaryKey),
            deviceType: try crypter.encryptAndBase64Encode(deviceType, using: accountKeys.primaryKey),
            scope: LoginScope.defaultCredential
        )
        let requestJson = try JSONEncoder.snakeCaseKeys.encode(params)
        let request = api.createUnauthenticatedJSONRequest(url: endpoints.login, method: .post, json: requestJson)
        let result = try await request.execute()
        guard let body = result.data else {
            throw SyncError.noResponseBody
        }
        let loginResult = try JSONDecoder.snakeCaseKeys.decode(DefaultCredentialLoginResult.self, from: body)
        guard let protectedSecretKey = Data(base64Encoded: loginResult.protectedEncryptionKey) else {
            throw SyncError.invalidDataInResponse("protected_key missing from response")
        }
        let secretKey = try crypter.extractSecretKey(protectedSecretKey: protectedSecretKey,
                                                     stretchedPrimaryKey: loginInfo.stretchedPrimaryKey)
        let devices = try loginResult.devices.map {
            RegisteredDevice(
                id: $0.id,
                name: try crypter.base64DecodeAndDecrypt($0.name, using: accountKeys.primaryKey),
                type: try crypter.base64DecodeAndDecrypt($0.type, using: accountKeys.primaryKey)
            )
        }
        return LoginResult(
            account: SyncAccount(
                deviceId: deviceId,
                deviceName: deviceName,
                deviceType: deviceType,
                userId: userId,
                primaryKey: accountKeys.primaryKey,
                secretKey: secretKey,
                token: loginResult.token,
                state: .addingNewDevice
            ),
            devices: devices,
            keys: loginResult.keys,
            accessCredentials: loginResult.accessCredentials
        )
    }

    private func accessCredentialURL(id: String) -> URL {
        endpoints.accessCredentials.appendingPathComponent(id)
    }

}

private extension String {
    func base64EncodedUTF8() -> String {
        Data(utf8).base64EncodedString()
    }

    func base64DecodedUTF8() -> String? {
        guard let data = Data(base64Encoded: self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

private struct CreateDefaultCredentialParameters: Encodable {
    let hashedPassword: String
    let credentialHashedPassword: String
    let protectedEncryptionKey: String
    let encrypted3partyCredential: String
    let keys: [ProtectedKey]

    enum CodingKeys: String, CodingKey {
        case hashedPassword = "hashed_password"
        case credentialHashedPassword = "credential_hashed_password"
        case protectedEncryptionKey = "protected_encryption_key"
        case encrypted3partyCredential = "encrypted_3party_credential"
        case keys
    }
}

private struct ThirdPartyLoginParameters: Encodable {
    let userId: String
    let hashedPassword: String
    let deviceId: String
    let deviceName: String
    let deviceType: String
    let scope: String
}

private struct DefaultCredentialLoginParameters: Encodable {
    let userId: String
    let hashedPassword: String
    let deviceId: String
    let deviceName: String
    let deviceType: String
    let scope: String
}

private struct DefaultCredentialLoginResult: Decodable {
    let devices: [RegisteredDevice]
    let token: String
    let protectedEncryptionKey: String
    let accessCredentials: [AccessCredential]?
    let keys: [ProtectedKey]?
}

private struct ThirdPartyLoginResult: Decodable {
    let devices: [ThirdPartyLoginDevice]?
    let token: String

    var registeredDevices: [RegisteredDevice] {
        devices?.map { $0.registeredDevice } ?? []
    }
}

private struct ThirdPartyLoginDevice: Decodable {
    let id: String
    let name: String
    let type: String?

    var registeredDevice: RegisteredDevice {
        RegisteredDevice(id: id,
                         name: name.base64DecodedUTF8() ?? name,
                         type: type?.base64DecodedUTF8() ?? type ?? "")
    }
}

private struct ThirdPartyLogin {
    let deviceId: String
    let token: String
    let hashedPassword: String
    let mainKey: Data
    let devices: [RegisteredDevice]
}
