//
//  ScopedAccessCredentialManager.swift
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

import CryptoKit
import Foundation

struct ScopedAccessCredentialManager: ScopedAccessCredentialManaging {

    private static let defaultCredentialId = "ddg"
    private static let thirdPartyCredentialId = "3party"

    let endpoints: Endpoints
    let api: RemoteAPIRequestCreating
    let crypter: CryptingInternal
    private let jweCompactCodec = JWECompactCodec()
    private let scopedAccessCredentialEnvelope = ScopedAccessCredentialEnvelope()

    func recoverScopedPassword(from accessCredentials: [AccessCredential]?,
                               primaryKey: Data,
                               userID: String) throws -> Data? {
        guard let thirdPartyCredential = accessCredentials?.first(where: { $0.id == Self.thirdPartyCredentialId }) else {
            return nil
        }
        guard let encryptedCredential = thirdPartyCredential.encrypted3PartyCredential, !encryptedCredential.isEmpty else {
            throw SyncError.invalidDataInResponse("3P access credential missing encrypted_3party_credential")
        }
        let defaultCredentialMainKey = ScopedAccessKeyDerivation.mainKey(from: primaryKey, userID: userID)
        return try scopedAccessCredentialEnvelope.decryptScopedPassword(from: encryptedCredential,
                                                                        using: defaultCredentialMainKey)
    }

    func ensureThirdPartyAccessCredential(for account: SyncAccount,
                                          scopedPassword: Data,
                                          keys: [ProtectedKey],
                                          includesNewDefaultKeys: Bool) async throws -> Data {
        guard let token = account.token else {
            throw SyncError.noToken
        }

        let existingCredentialInfo = try crypter.extractLoginInfo(
            recoveryKey: SyncCode.RecoveryKey(userId: account.userId, primaryKey: account.primaryKey)
        )
        let hashedPassword = existingCredentialInfo.passwordHash.base64EncodedString()
        let credentialHashedPassword = ScopedAccessKeyDerivation.hashedPassword(from: scopedPassword, userID: account.userId)
        let defaultCredentialMainKey = ScopedAccessKeyDerivation.mainKey(from: account.primaryKey, userID: account.userId)
        let encryptedThirdPartyCredentialToken = try scopedAccessCredentialEnvelope.encryptScopedPassword(scopedPassword,
                                                                                                          using: defaultCredentialMainKey,
                                                                                                          kid: Self.defaultCredentialId)

        let createCredentialKeys = try accessCredentialProtectedKeys(from: keys,
                                                                     scopedPassword: scopedPassword,
                                                                     account: account,
                                                                     includesNewDefaultKeys: includesNewDefaultKeys)
            .removingDuplicateWrappingIdentities()
            .map(ProtectedKeyPayload.init)

        try await postThirdPartyAccessCredential(token: token,
                                                 hashedPassword: hashedPassword,
                                                 credentialHashedPassword: credentialHashedPassword,
                                                 encryptedThirdPartyCredential: encryptedThirdPartyCredentialToken,
                                                 keys: createCredentialKeys)
        return scopedPassword
    }

    func fetchAccessCredentials(_ account: SyncAccount) async throws -> [AccessCredential] {
        guard let token = account.token else {
            throw SyncError.noToken
        }

        let request = api.createAuthenticatedGetRequest(url: endpoints.accessCredentials, authToken: token)
        do {
            let result = try await request.execute()
            guard let body = result.data else {
                throw SyncError.noResponseBody
            }
            return try decodeAccessCredentials(from: body)
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            if statusCode == 404 {
                return []
            }
            throw SyncError.unexpectedStatusCode(statusCode)
        }
    }

    func fetchProtectedKeys(_ account: SyncAccount) async throws -> [ProtectedKey] {
        guard let token = account.token else {
            throw SyncError.noToken
        }

        let request = api.createAuthenticatedGetRequest(url: endpoints.keys, authToken: token)
        do {
            let result = try await request.execute()
            guard let body = result.data else {
                throw SyncError.noResponseBody
            }
            return try decodeProtectedKeys(from: body)
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            if statusCode == 404 {
                return []
            }
            throw SyncError.unexpectedStatusCode(statusCode)
        }
    }

    func setKeyIfAbsent(purpose: String,
                        key: ProtectedKey,
                        for account: SyncAccount) async throws -> ProtectedKey? {
        try await setKeysIfAbsent(purpose: purpose,
                                  keys: [key],
                                  for: account)
            .first
    }

    private func setKeysIfAbsent(purpose: String,
                                 keys: [ProtectedKey],
                                 for account: SyncAccount) async throws -> [ProtectedKey] {
        guard let token = account.token else {
            throw SyncError.noToken
        }

        let deduplicatedKeys = keys.removingDuplicateWrappingIdentities()
        let params = try SetKeyIfAbsentParameters(keys: deduplicatedKeys)
        let requestJSON = try JSONEncoder.snakeCaseKeys.encode(params)
        let request = api.createAuthenticatedJSONRequest(url: endpoints.setKeyIfAbsent(purpose: purpose),
                                                         method: .post,
                                                         authToken: token,
                                                         json: requestJSON)
        do {
            let result = try await request.execute()
            guard result.response.statusCode == 201 else {
                throw SyncError.unexpectedStatusCode(result.response.statusCode)
            }
            guard let body = result.data, !body.isEmpty else {
                return deduplicatedKeys
            }
            return try decodeProtectedKeys(from: body, expectedKeys: deduplicatedKeys)
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            if statusCode == 409 {
                return try await reconcileConflictingProtectedKeys(purpose: purpose,
                                                                   expectedKeys: deduplicatedKeys,
                                                                   account: account)
            }
            throw SyncError.unexpectedStatusCode(statusCode)
        }
    }

    private func postThirdPartyAccessCredential(token: String,
                                                hashedPassword: String,
                                                credentialHashedPassword: String,
                                                encryptedThirdPartyCredential: String,
                                                keys: [ProtectedKeyPayload]) async throws {
        let params = CreateThirdPartyCredentialParameters(
            hashedPassword: hashedPassword,
            credentialHashedPassword: credentialHashedPassword,
            encrypted3partyCredential: encryptedThirdPartyCredential,
            keys: keys
        )
        let requestJson = try JSONEncoder.snakeCaseKeys.encode(params)
        let request = api.createAuthenticatedJSONRequest(url: endpoints.accessCredential(Self.thirdPartyCredentialId),
                                                         method: .post,
                                                         authToken: token,
                                                         json: requestJson)
        let result = try await request.execute()
        guard result.response.statusCode == 201 else {
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }
    }

    private func decodeAccessCredentials(from data: Data) throws -> [AccessCredential] {
        let wrappedResult = try JSONDecoder.snakeCaseKeys.decode(FetchAccessCredentialsResult.self, from: data)
        guard let accessCredentials = wrappedResult.accessCredentials else {
            throw SyncError.unableToDecodeResponse("Failed to decode access credentials")
        }
        return accessCredentials
    }

    private func decodeProtectedKeys(from data: Data) throws -> [ProtectedKey] {
        let wrappedResult = try JSONDecoder.snakeCaseKeys.decode(FetchProtectedKeysResult.self, from: data)
        guard let keys = wrappedResult.keys else {
            throw SyncError.unableToDecodeResponse("Failed to decode protected keys")
        }
        return keys
    }

    private func reconcileConflictingProtectedKeys(purpose: String,
                                                   expectedKeys: [ProtectedKey],
                                                   account: SyncAccount) async throws -> [ProtectedKey] {
        let keys = try await fetchProtectedKeys(account)
        let matchingKeys = selectBestMatchingKeys(in: keys, expectedKeys: expectedKeys)
        if matchingKeys.count == expectedKeys.count {
            return matchingKeys
        }
        throw SyncError.invalidDataInResponse(
            "set-if-absent returned 409 for purpose=\(purpose), but no matching keys were found after refetch"
        )
    }

    private func decodeProtectedKeys(from data: Data, expectedKeys: [ProtectedKey]) throws -> [ProtectedKey] {
        let result = try JSONDecoder.snakeCaseKeys.decode(SetKeyIfAbsentResult.self, from: data)
        guard let keys = result.keys else {
            throw SyncError.unableToDecodeResponse("Failed to decode protected keys")
        }
        return selectBestMatchingKeys(in: keys, expectedKeys: expectedKeys)
    }

    private func selectBestMatchingKeys(in keys: [ProtectedKey],
                                        expectedKeys: [ProtectedKey]) -> [ProtectedKey] {
        expectedKeys.compactMap { expectedKey in
            if let key = keys.first(where: { $0.hasSameWrappingIdentity(as: expectedKey) }) {
                return key
            }
            if let key = keys.first(where: { $0.purpose == expectedKey.purpose && $0.encryptedWith == expectedKey.encryptedWith }) {
                return key
            }
            return nil
        }
    }

    private func accessCredentialProtectedKeys(from keys: [ProtectedKey],
                                               scopedPassword: Data,
                                               account: SyncAccount,
                                               includesNewDefaultKeys: Bool) throws -> [ProtectedKey] {
        let existingThirdPartyKeys = keys
            .filter { $0.encryptedWith == Self.thirdPartyCredentialId }
            .removingDuplicateWrappingIdentities()
        let defaultKeysToRewrap = keys
            .filter { key in
                key.encryptedWith == Self.defaultCredentialId
                && !existingThirdPartyKeys.contains { thirdPartyKey in
                    thirdPartyKey.kid == key.kid && thirdPartyKey.purpose == key.purpose
                }
            }
        let defaultKeysToUpload = includesNewDefaultKeys ? defaultKeysToRewrap : []
        let defaultCredentialMainKey = ScopedAccessKeyDerivation.mainKey(from: account.primaryKey, userID: account.userId)
        let thirdPartyMainKey = ScopedAccessKeyDerivation.mainKey(from: scopedPassword, userID: account.userId)
        let rewrappedKeys = try rewrapProtectedKeys(defaultKeysToRewrap,
                                                    fromWrappingKey: defaultCredentialMainKey,
                                                    toWrappingKey: thirdPartyMainKey,
                                                    accountSecretKey: account.secretKey)
        return defaultKeysToUpload + rewrappedKeys + existingThirdPartyKeys
    }

    private func rewrapProtectedKeys(_ keys: [ProtectedKey],
                                     fromWrappingKey: Data,
                                     toWrappingKey: Data,
                                     accountSecretKey: Data) throws -> [ProtectedKey] {
        let keysToRewrap = keys
            .filter { $0.encryptedWith == Self.defaultCredentialId }
            .removingDuplicateWrappingIdentities()
        return try keysToRewrap.map { key in
            let decryptedPrivateKey = try decryptDefaultCredentialPrivateKeyForRewrap(
                key,
                fromWrappingKey: fromWrappingKey,
                accountSecretKey: accountSecretKey
            )
            let rewrappedEncryptedPrivateKey = try jweCompactCodec.encryptDirect(payload: decryptedPrivateKey,
                                                                                 contentEncryptionKey: toWrappingKey,
                                                                                 kid: Self.thirdPartyCredentialId)
            return ProtectedKey(kid: key.kid,
                                encryptedPrivateKey: rewrappedEncryptedPrivateKey,
                                publicKey: key.publicKey,
                                encryptedWith: Self.thirdPartyCredentialId,
                                purpose: key.purpose)
        }
    }

    private func decryptDefaultCredentialPrivateKeyForRewrap(_ key: ProtectedKey,
                                                             fromWrappingKey: Data,
                                                             accountSecretKey: Data) throws -> Data {
        if let encryptedPrivateKeyBytes = Base64URL.decode(key.encryptedPrivateKey) {
            do {
                return try crypter.decryptData(encryptedPrivateKeyBytes, using: accountSecretKey)
            } catch {
                // Legacy iOS rows stored ddg source keys as direct JWE; keep backward compatibility.
            }
        }

        return try jweCompactCodec.decryptDirect(token: key.encryptedPrivateKey,
                                                 contentEncryptionKey: fromWrappingKey)
    }

    struct FetchProtectedKeysResult: Decodable {
        let keys: [ProtectedKey]?
    }

    struct FetchAccessCredentialsResult: Decodable {
        let accessCredentials: [AccessCredential]?
    }

    struct ProtectedKeyPayload: Encodable {
        let kid: String
        let purpose: String
        let encryptedPrivateKey: String
        let publicKey: ProtectedKeyPublicKey
        let encryptedWith: String

        init(key: ProtectedKey) throws {
            self.kid = key.kid
            self.purpose = key.purpose
            self.encryptedPrivateKey = key.encryptedPrivateKey
            self.publicKey = key.publicKey
            self.encryptedWith = key.encryptedWith
        }
    }

    struct CreateThirdPartyCredentialParameters: Encodable {
        let hashedPassword: String
        let credentialHashedPassword: String
        let encrypted3partyCredential: String
        let keys: [ProtectedKeyPayload]

        enum CodingKeys: String, CodingKey {
            case hashedPassword = "hashed_password"
            case credentialHashedPassword = "credential_hashed_password"
            case encrypted3partyCredential = "encrypted_3party_credential"
            case keys
        }
    }

    struct SetKeyIfAbsentParameters: Encodable {
        let keys: [ProtectedKeyPayload]

        init(keys: [ProtectedKey]) throws {
            self.keys = try keys.map(ProtectedKeyPayload.init)
        }

        init(key: ProtectedKey) throws {
            try self.init(keys: [key])
        }
    }

    struct SetKeyIfAbsentResult: Decodable {
        let keys: [ProtectedKey]?
    }

}

private enum ScopedAccessKeyDerivation {

    private static let passwordInfo = "Password"
    private static let mainKeyInfo = "Main Key"

    static func hashedPassword(from secret: Data, userID: String) -> String {
        Base64URL.encode(derive(input: secret, salt: userID, info: passwordInfo))
    }

    static func mainKey(from secret: Data, userID: String) -> Data {
        derive(input: secret, salt: userID, info: mainKeyInfo)
    }

    private static func derive(input: Data, salt: String, info: String, length: Int = 32) -> Data {
        let derivedKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: input),
                                                salt: Data(salt.utf8),
                                                info: Data(info.utf8),
                                                outputByteCount: length)
        return derivedKey.withUnsafeBytes { Data($0) }
    }
}
