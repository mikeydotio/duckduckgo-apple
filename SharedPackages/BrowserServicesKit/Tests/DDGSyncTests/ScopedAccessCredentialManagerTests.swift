//
//  ScopedAccessCredentialManagerTests.swift
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
import XCTest

@testable import DDGSync

final class ScopedAccessCredentialManagerTests: XCTestCase {

    private static let baseURL = URL(string: "https://dev.null")!

    func testWhenEnsuringThirdPartyAccessCredentialThenUsesHKDFAndJWEAndPostsThirdPartyKeysOnly() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        var crypter = CryptingMock()
        crypter._extractLoginInfo = { recoveryKey in
            ExtractedLoginInfo(userId: recoveryKey.userId,
                               primaryKey: recoveryKey.primaryKey,
                               passwordHash: Data([0xAB]),
                               stretchedPrimaryKey: Data())
        }
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: crypter)

        let accountPrimaryKey = Data((0..<32).map(UInt8.init))
        let scopedPassword = Data((32..<64).map(UInt8.init))
        let account = makeAccount(primaryKey: accountPrimaryKey)
        let defaultCredentialMainKey = hkdf(input: accountPrimaryKey, salt: account.userId, info: "Main Key")
        let ddgWrappedProtectedKey = try makeNativeEncryptedProtectedKey(privateKey: Data("default-private-key".utf8), account: account, crypter: crypter)
        let thirdPartyWrappedProtectedKey = ProtectedKey(kid: ddgWrappedProtectedKey.kid,
                                                         encryptedPrivateKey: "rewrapped-private-key",
                                                         publicKey: ddgWrappedProtectedKey.publicKey,
                                                         encryptedWith: "3party",
                                                         purpose: ddgWrappedProtectedKey.purpose)
        api.fakeRequests[endpoints.accessCredential("3party")] = makeRequest(statusCode: 201)

        let returnedScopedPassword = try await manager.ensureThirdPartyAccessCredential(for: account,
                                                                                       scopedPassword: scopedPassword,
                                                                                       keys: [ddgWrappedProtectedKey, thirdPartyWrappedProtectedKey],
                                                                                       includesNewDefaultKeys: false)

        XCTAssertEqual(returnedScopedPassword, scopedPassword)

        let requestBody = try XCTUnwrap(api.createRequestCallArgs.last?.body)
        let payload = try decodeJSONObject(requestBody)

        XCTAssertEqual(payload["hashed_password"] as? String, Data([0xAB]).base64EncodedString())
        XCTAssertEqual(payload["credential_hashed_password"] as? String, Base64URL.encode(hkdf(input: scopedPassword, salt: account.userId, info: "Password")))

        let encryptedCredential = try XCTUnwrap(payload["encrypted_3party_credential"] as? String)
        let decryptedCredential = try ScopedAccessCredentialEnvelope().decryptScopedPassword(from: encryptedCredential, using: defaultCredentialMainKey)
        XCTAssertEqual(decryptedCredential, scopedPassword)

        let keys = try XCTUnwrap(payload["keys"] as? [[String: Any]])
        XCTAssertEqual(keys.count, 1)
        XCTAssertNil(keys.first { $0["encrypted_with"] as? String == "ddg" })
        let keyPayload = try XCTUnwrap(keys.first)
        XCTAssertEqual(keyPayload["kid"] as? String, ddgWrappedProtectedKey.kid)
        XCTAssertEqual(keyPayload["purpose"] as? String, "ai_chats")
        XCTAssertEqual(keyPayload["encrypted_with"] as? String, "3party")
    }

    func testWhenEnsuringThirdPartyAccessCredentialWithNewDefaultKeyThenPostsOriginalAndRewrappedKeys() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        var crypter = CryptingMock()
        crypter._extractLoginInfo = { recoveryKey in
            ExtractedLoginInfo(userId: recoveryKey.userId,
                               primaryKey: recoveryKey.primaryKey,
                               passwordHash: Data([0xAB]),
                               stretchedPrimaryKey: Data())
        }
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: crypter)

        let accountPrimaryKey = Data((0..<32).map(UInt8.init))
        let scopedPassword = Data((32..<64).map(UInt8.init))
        let account = makeAccount(primaryKey: accountPrimaryKey)
        let thirdPartyMainKey = hkdf(input: scopedPassword, salt: account.userId, info: "Main Key")
        let originalPrivateKey = Data("default-private-key".utf8)
        let ddgWrappedProtectedKey = try makeNativeEncryptedProtectedKey(privateKey: originalPrivateKey, account: account, crypter: crypter)
        api.fakeRequests[endpoints.accessCredential("3party")] = makeRequest(statusCode: 201)

        _ = try await manager.ensureThirdPartyAccessCredential(for: account,
                                                               scopedPassword: scopedPassword,
                                                               keys: [ddgWrappedProtectedKey, ddgWrappedProtectedKey],
                                                               includesNewDefaultKeys: true)

        let requestBody = try XCTUnwrap(api.createRequestCallArgs.last?.body)
        let payload = try decodeJSONObject(requestBody)
        let keys = try XCTUnwrap(payload["keys"] as? [[String: Any]])
        XCTAssertEqual(keys.count, 2)

        let ddgKeyPayload = try XCTUnwrap(keys.first { $0["encrypted_with"] as? String == "ddg" })
        XCTAssertEqual(ddgKeyPayload["kid"] as? String, ddgWrappedProtectedKey.kid)
        XCTAssertEqual(ddgKeyPayload["purpose"] as? String, "ai_chats")

        let rewrappedKeyPayload = try XCTUnwrap(keys.first { $0["encrypted_with"] as? String == "3party" })
        XCTAssertEqual(rewrappedKeyPayload["kid"] as? String, ddgWrappedProtectedKey.kid)
        XCTAssertEqual(rewrappedKeyPayload["purpose"] as? String, "ai_chats")

        let rewrappedEncryptedPrivateKey = try XCTUnwrap(rewrappedKeyPayload["encrypted_private_key"] as? String)
        let decryptedRewrappedPrivateKey = try JWECompactCodec().decryptDirect(token: rewrappedEncryptedPrivateKey, contentEncryptionKey: thirdPartyMainKey)
        XCTAssertEqual(decryptedRewrappedPrivateKey, originalPrivateKey)
    }

    func testWhenDefaultCredentialProtectedKeyIsDirectJWEThenThrowsInvalidDataInResponse() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        var crypter = CryptingMock()
        crypter._extractLoginInfo = { recoveryKey in
            ExtractedLoginInfo(userId: recoveryKey.userId,
                               primaryKey: recoveryKey.primaryKey,
                               passwordHash: Data([0xAB]),
                               stretchedPrimaryKey: Data())
        }
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: crypter)

        let accountPrimaryKey = Data((0..<32).map(UInt8.init))
        let scopedPassword = Data((32..<64).map(UInt8.init))
        let account = makeAccount(primaryKey: accountPrimaryKey)
        let defaultCredentialMainKey = hkdf(input: accountPrimaryKey, salt: account.userId, info: "Main Key")
        let ddgWrappedProtectedKey = try ScopedAccessKeyFactory.makeJWEProtectedKey(wrappingKey: defaultCredentialMainKey,
                                                                                    encryptedWith: "ddg",
                                                                                    purpose: "ai_chats")

        do {
            _ = try await manager.ensureThirdPartyAccessCredential(for: account,
                                                                   scopedPassword: scopedPassword,
                                                                   keys: [ddgWrappedProtectedKey],
                                                                   includesNewDefaultKeys: false)
            XCTFail("Expected direct-JWE ddg source key to be rejected")
        } catch SyncError.invalidDataInResponse(let message) {
            XCTAssertTrue(message.contains("encrypted_private_key"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWhenSetKeyIfAbsentReturns409ThenRefetchesAndReconciles() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: CryptingMock())
        let account = makeAccount(primaryKey: Data(repeating: 0x1, count: 32))
        let requestedKey = makeProtectedKey(kid: "requested", encryptedWith: "ddg", purpose: "ai_chats")

        let conflictRequest = HTTPRequestingMock()
        conflictRequest.error = SyncError.unexpectedStatusCode(409)
        api.fakeRequests[endpoints.setKeyIfAbsent(purpose: "ai_chats")] = conflictRequest
        api.fakeRequests[endpoints.keys] = makeRequest(statusCode: 200,
                                                       body: """
                                                       {
                                                         "keys": [
                                                           {
                                                             "kid": "server-ddg",
                                                             "encrypted_private_key": "enc-private",
                                                             "public_key": {
                                                               "kty": "RSA",
                                                               "alg": "RSA-OAEP-256",
                                                               "use": "enc",
                                                               "n": "mod",
                                                               "e": "AQAB"
                                                             },
                                                             "encrypted_with": "ddg",
                                                             "purpose": "ai_chats"
                                                           }
                                                         ]
                                                       }
                                                       """)

        let result = try await manager.setKeyIfAbsent(purpose: "ai_chats", key: requestedKey, for: account)

        XCTAssertEqual(result?.kid, "server-ddg")
        XCTAssertEqual(result?.encryptedWith, "ddg")
        XCTAssertEqual(result?.purpose, "ai_chats")
        XCTAssertEqual(api.createRequestCallArgs.count, 2)
    }

    func testWhenSetKeyIfAbsentReturns409WithOnlyPurposeMatchThenThrows() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: CryptingMock())
        let account = makeAccount(primaryKey: Data(repeating: 0x1, count: 32))
        let requestedKey = makeProtectedKey(kid: "requested", encryptedWith: "ddg", purpose: "ai_chats")

        let conflictRequest = HTTPRequestingMock()
        conflictRequest.error = SyncError.unexpectedStatusCode(409)
        api.fakeRequests[endpoints.setKeyIfAbsent(purpose: "ai_chats")] = conflictRequest
        api.fakeRequests[endpoints.keys] = makeRequest(statusCode: 200,
                                                       body: """
                                                       {
                                                         "keys": [
                                                           {
                                                             "kid": "server-3party",
                                                             "encrypted_private_key": "enc-private",
                                                             "public_key": {
                                                               "kty": "RSA",
                                                               "alg": "RSA-OAEP-256",
                                                               "use": "enc",
                                                               "n": "mod",
                                                               "e": "AQAB"
                                                             },
                                                             "encrypted_with": "3party",
                                                             "purpose": "ai_chats"
                                                           }
                                                         ]
                                                       }
                                                       """)

        do {
            _ = try await manager.setKeyIfAbsent(purpose: "ai_chats", key: requestedKey, for: account)
            XCTFail("Expected setKeyIfAbsent to throw")
        } catch SyncError.invalidDataInResponse(let message) {
            XCTAssertTrue(message.contains("no matching key"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(api.createRequestCallArgs.count, 2)
    }

    func testWhenSetKeyIfAbsentReturnsWrappedKeysThenMatchingKeyIsReturned() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: CryptingMock())
        let account = makeAccount(primaryKey: Data(repeating: 0x3, count: 32))
        let requestedKey = makeProtectedKey(kid: "requested", encryptedWith: "ddg", purpose: "ai_chats")

        api.fakeRequests[endpoints.setKeyIfAbsent(purpose: "ai_chats")] = makeRequest(statusCode: 201,
                                                                                       body: """
                                                                                       {
                                                                                         "keys": [
                                                                                           {
                                                                                             "kid": "server-other",
                                                                                             "encrypted_private_key": "enc-private-other",
                                                                                             "public_key": {
                                                                                               "kty": "RSA",
                                                                                               "alg": "RSA-OAEP-256",
                                                                                               "use": "enc",
                                                                                               "n": "mod",
                                                                                               "e": "AQAB"
                                                                                             },
                                                                                             "encrypted_with": "3party",
                                                                                             "purpose": "bookmarks"
                                                                                           },
                                                                                           {
                                                                                             "kid": "server-ddg",
                                                                                             "encrypted_private_key": "enc-private",
                                                                                             "public_key": {
                                                                                               "kty": "RSA",
                                                                                               "alg": "RSA-OAEP-256",
                                                                                               "use": "enc",
                                                                                               "n": "mod",
                                                                                               "e": "AQAB"
                                                                                             },
                                                                                             "encrypted_with": "ddg",
                                                                                             "purpose": "ai_chats"
                                                                                           }
                                                                                         ]
                                                                                       }
                                                                                       """)

        let result = try await manager.setKeyIfAbsent(purpose: "ai_chats", key: requestedKey, for: account)

        XCTAssertEqual(result?.kid, "server-ddg")
        XCTAssertEqual(result?.encryptedWith, "ddg")
        XCTAssertEqual(result?.purpose, "ai_chats")
    }

    func testWhenSetKeyIfAbsentReturns200ThenThrowsUnexpectedStatusCode() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: CryptingMock())
        let account = makeAccount(primaryKey: Data(repeating: 0x4, count: 32))
        let requestedKey = makeProtectedKey(kid: "requested", encryptedWith: "ddg", purpose: "ai_chats")

        api.fakeRequests[endpoints.setKeyIfAbsent(purpose: "ai_chats")] = makeRequest(statusCode: 200)

        do {
            _ = try await manager.setKeyIfAbsent(purpose: "ai_chats", key: requestedKey, for: account)
            XCTFail("Expected setKeyIfAbsent to throw")
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            XCTAssertEqual(statusCode, 200)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(api.createRequestCallArgs.count, 1)
    }

    func testWhenKeysPayloadIsRejectedThenThrowsUnexpectedStatusCode() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: CryptingMock())
        let account = makeAccount(primaryKey: Data(repeating: 0x9, count: 32))
        let requestedKey = makeProtectedKey(kid: "requested",
                                            encryptedWith: "ddg",
                                            purpose: "ai_chats")

        let rejectingRequest = HTTPRequestingMock()
        rejectingRequest.error = SyncError.unexpectedStatusCode(422)
        api.fakeRequests[endpoints.setKeyIfAbsent(purpose: "ai_chats")] = rejectingRequest

        do {
            _ = try await manager.setKeyIfAbsent(purpose: "ai_chats", key: requestedKey, for: account)
            XCTFail("Expected setKeyIfAbsent to throw")
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            XCTAssertEqual(statusCode, 422)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(api.createRequestCallArgs.count, 1)
    }

    private func makeAccount(primaryKey: Data) -> SyncAccount {
        SyncAccount(deviceId: "device-1",
                    deviceName: "iPhone",
                    deviceType: "ios",
                    userId: "user-1",
                    primaryKey: primaryKey,
                    secretKey: Data(repeating: 0x2, count: 32),
                    token: "token-1",
                    state: .active)
    }

    private func makeProtectedKey(kid: String,
                                  encryptedWith: String,
                                  purpose: String,
                                  publicKey: ProtectedKeyPublicKey = .mock) -> ProtectedKey {
        ProtectedKey(kid: kid,
                     encryptedPrivateKey: "enc-private",
                     publicKey: publicKey,
                     encryptedWith: encryptedWith,
                     purpose: purpose)
    }

    private func makeNativeEncryptedProtectedKey(privateKey: Data,
                                                 account: SyncAccount,
                                                 crypter: CryptingInternal) throws -> ProtectedKey {
        let encryptedPrivateKey = try crypter.encrypt(privateKey, using: account.secretKey)
        return ProtectedKey(kid: UUID().uuidString,
                            encryptedPrivateKey: Base64URL.encode(encryptedPrivateKey),
                            publicKey: .mock,
                            encryptedWith: "ddg",
                            purpose: "ai_chats")
    }

    private func makeRequest(statusCode: Int, body: String? = nil) -> HTTPRequestingMock {
        HTTPRequestingMock(result: .init(data: body.map { Data($0.utf8) },
                                         response: makeHTTPURLResponse(statusCode: statusCode)))
    }

    private func makeHTTPURLResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://dev.null/test")!,
                        statusCode: statusCode,
                        httpVersion: nil,
                        headerFields: nil)!
    }

    private func decodeJSONObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Expected dictionary JSON payload")
            return [:]
        }
        return object
    }

    private func hkdf(input: Data, salt: String, info: String) -> Data {
        let derivedKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: input),
                                                salt: Data(salt.utf8),
                                                info: Data(info.utf8),
                                                outputByteCount: 32)
        return derivedKey.withUnsafeBytes { Data($0) }
    }
}
