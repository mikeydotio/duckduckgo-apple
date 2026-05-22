//
//  SyncModels.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public struct SyncAccount: Codable, Sendable {
    public let deviceId: String
    public let deviceName: String
    public let deviceType: String
    public let userId: String
    public let primaryKey: Data
    public let secretKey: Data
    public let nativeCredentialSecret: String?
    public let token: String?
    public let state: SyncAuthState

    /// Convenience var which calls `SyncCode().toJSON().base64EncodedString()`
    public var recoveryCode: String? {
        nativeRecoveryCode(usesV2Payload: false)
    }

    init(
        deviceId: String,
        deviceName: String,
        deviceType: String,
        userId: String,
        primaryKey: Data,
        secretKey: Data,
        nativeCredentialSecret: String? = nil,
        token: String?,
        state: SyncAuthState
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.userId = userId
        self.primaryKey = primaryKey
        self.secretKey = secretKey
        self.nativeCredentialSecret = nativeCredentialSecret
        self.token = token
        self.state = state
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.deviceId = try container.decode(String.self, forKey: .deviceId)
        self.deviceName = try container.decode(String.self, forKey: .deviceName)
        self.deviceType = try container.decode(String.self, forKey: .deviceType)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.primaryKey = try container.decode(Data.self, forKey: .primaryKey)
        self.secretKey = try container.decode(Data.self, forKey: .secretKey)
        self.nativeCredentialSecret = try container.decodeIfPresent(String.self, forKey: .nativeCredentialSecret)
        self.token = try container.decodeIfPresent(String.self, forKey: .token)
        if let state: SyncAuthState = try container.decodeIfPresent(SyncAuthState.self, forKey: .state) {
            self.state = state
        } else {
            self.state = SyncAuthState.active
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.deviceId, forKey: .deviceId)
        try container.encode(self.deviceName, forKey: .deviceName)
        try container.encode(self.deviceType, forKey: .deviceType)
        try container.encode(self.userId, forKey: .userId)
        try container.encode(self.primaryKey, forKey: .primaryKey)
        try container.encode(self.secretKey, forKey: .secretKey)
        try container.encodeIfPresent(self.nativeCredentialSecret, forKey: .nativeCredentialSecret)
        try container.encodeIfPresent(self.token, forKey: .token)
        try container.encode(self.state, forKey: .state)
    }

    enum CodingKeys: CodingKey {
        case deviceId
        case deviceName
        case deviceType
        case userId
        case primaryKey
        case secretKey
        case nativeCredentialSecret
        case token
        case state
    }
}

extension SyncAccount {
    func nativeRecoveryCode(usesV2Payload: Bool,
                            credentialId: String = SyncCode.RecoveryKeyV2.nativeCredentialId) -> String? {
        do {
            let payloadData = try nativeRecoveryPayloadData(
                usesV2Payload: usesV2Payload,
                credentialId: credentialId
            )
            if usesV2Payload {
                return Base64URL.encode(payloadData)
            }
            return payloadData.base64EncodedString()
        } catch {
            assertionFailure(error.localizedDescription)
            return nil
        }
    }

    func nativeRecoveryPayloadData(usesV2Payload: Bool,
                                   credentialId: String = SyncCode.RecoveryKeyV2.nativeCredentialId) throws -> Data {
        let recoveryPayload: SyncCode.Recovery
        if usesV2Payload {
            let secret: String
            if credentialId == SyncCode.RecoveryKeyV2.nativeCredentialId {
                // Migration fallback for pre-seed accounts created before `nativeCredentialSecret`
                // was persisted. Keep existing recoverability by emitting legacy primary-key bytes.
                if let nativeCredentialSecret, !nativeCredentialSecret.isEmpty {
                    secret = nativeCredentialSecret
                } else {
                    secret = Base64URL.encode(primaryKey)
                }
            } else {
                secret = Base64URL.encode(primaryKey)
            }
            recoveryPayload = .v2(.init(
                userId: userId,
                secret: secret,
                cid: credentialId,
                v: SyncCode.RecoveryKeyV2.currentVersion
            ))
        } else {
            recoveryPayload = .v1(.init(userId: userId, primaryKey: primaryKey))
        }
        return try SyncCode(recovery: recoveryPayload).toJSON()
    }

    /// Builds the V2 recovery code payload:
    /// `{ "recovery": { "user_id", "secret", "cid", "v": "2.0" } }`, JSON-encoded,
    /// then base64URL-encoded (no padding, `-`/`_` alphabet).
    func scopedAccessRecoveryCode(scopedPassword: Data,
                                  credentialId: String = SyncCode.RecoveryKeyV2.thirdPartyCredentialId) -> String? {
        guard !scopedPassword.isEmpty else {
            return nil
        }
        let payload = SyncCode.RecoveryKeyV2(
            userId: userId,
            secret: Base64URL.encode(scopedPassword),
            cid: credentialId,
            v: SyncCode.RecoveryKeyV2.currentVersion
        )
        do {
            let json = try SyncCode(recovery: .v2(payload)).toJSON()
            return Base64URL.encode(json)
        } catch {
            assertionFailure(error.localizedDescription)
            return nil
        }
    }

    func updatingNativeCredentialSecret(_ nativeCredentialSecret: String?) -> SyncAccount {
        SyncAccount(deviceId: self.deviceId,
                    deviceName: self.deviceName,
                    deviceType: self.deviceType,
                    userId: self.userId,
                    primaryKey: self.primaryKey,
                    secretKey: self.secretKey,
                    nativeCredentialSecret: nativeCredentialSecret,
                    token: self.token,
                    state: self.state)
    }
}

public struct RegisteredDevice: Codable, Sendable {

    public let id: String
    public let name: String
    public let type: String

}

public struct AccessCredential: Codable, Sendable {

    public let id: String
    public let scope: String?
    public let encrypted3PartyCredential: String?
}

public struct ProtectedKey: Codable, Sendable {

    public let kid: String
    public let encryptedPrivateKey: String
    public let publicKey: ProtectedKeyPublicKey
    public let encryptedWith: String
    public let purpose: String
}

public struct ProtectedKeyPublicKey: Codable, Sendable, Equatable {
    public let alg: String
    public let e: String?
    public let ext: Bool?
    public let keyOps: [String]?
    public let kty: String
    public let n: String?
    public let use: String?
}

extension ProtectedKey {
    func hasSameWrappingIdentity(as other: ProtectedKey) -> Bool {
        kid == other.kid && encryptedWith == other.encryptedWith && purpose == other.purpose
    }
}

extension Sequence where Element == ProtectedKey {
    func removingDuplicateWrappingIdentities() -> [ProtectedKey] {
        var seenIdentities: Set<ProtectedKeyWrappingIdentity> = []
        return filter { key in
            seenIdentities.insert(ProtectedKeyWrappingIdentity(key: key)).inserted
        }
    }
}

private struct ProtectedKeyWrappingIdentity: Hashable {
    let kid: String
    let encryptedWith: String
    let purpose: String

    init(key: ProtectedKey) {
        self.kid = key.kid
        self.encryptedWith = key.encryptedWith
        self.purpose = key.purpose
    }
}

public struct AccountCreationKeys {
    public let primaryKey: Data
    public let secretKey: Data
    public let protectedSecretKey: Data
    public let passwordHash: Data
}

public struct ExtractedLoginInfo {
    public let userId: String
    public let primaryKey: Data
    public let passwordHash: Data
    public let stretchedPrimaryKey: Data
}

public struct ConnectInfo {
    public let deviceID: String
    public let publicKey: Data
    public let secretKey: Data
}

public struct ExchangeInfo {
    public let keyId: String
    public let publicKey: Data
    public let secretKey: Data
}

public struct ExchangeMessage: Codable, Sendable {
    public let keyId: String
    public let publicKey: Data
    public let deviceName: String
}

public struct PairingInfo {
    enum Keys {
        static let code = "code"
        static let deviceName = "deviceName"
    }

    public let base64Code: String
    public let deviceName: String

    public init?(url: URL) {
        guard Self.isPairing(url: url) else {
            return nil
        }
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment else {
            return nil
        }
        let params = fragment
            .split(separator: "&")
            .compactMap { part -> (String, String)? in
                let keyValue = part.split(separator: "=", maxSplits: 1).map(String.init)
                guard keyValue.count == 2 else { return nil }
                return (keyValue[0], keyValue[1].removingPercentEncoding ?? keyValue[1])
            }

        let dict = Dictionary(uniqueKeysWithValues: params)
        guard let code = dict[Keys.code], let deviceName = dict[Keys.deviceName] else {
            return nil
        }
        self.init(base64Code: Self.restoreBase64(from: code),
                  deviceName: deviceName)
    }

    init(base64Code: String, deviceName: String) {
        self.base64Code = base64Code
        self.deviceName = deviceName
    }

    public func toURL(baseURL: URL) -> URL {
        let url = baseURL.appendingPathComponent("sync/pairing/")
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let fragment = "&\(Keys.code)=\(base64URLCode)&\(Keys.deviceName)=\(deviceName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceName)"
        urlComponents?.fragment = fragment
        return urlComponents?.url ?? url
    }

    private static func isPairing(url: URL) -> Bool {
        url.pathComponents.contains("sync") && url.pathComponents.last == "pairing" && url.isPart(ofDomain: "duckduckgo.com")
    }

    private static func restoreBase64(from base64URLCode: String) -> String {
        let paddingLength = (4 - (base64URLCode.count % 4)) % 4
        let padding = String(repeating: "=", count: paddingLength)
        return base64URLCode.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/").appending(padding)
    }

    private var base64URLCode: String {
        base64Code.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

public struct SyncCode: Codable {

    public enum Base64Error: Error {
        case error
    }

    public enum RecoveryCodeVersionError: Error, Equatable {
        case malformed(String)
        case unsupported(String)
    }

    public struct RecoveryKey: Codable, Sendable, Equatable {
        let userId: String
        let primaryKey: Data
        let fallbackPrimaryKey: Data?
        let nativeCredentialSecret: String?

        init(userId: String,
             primaryKey: Data,
             fallbackPrimaryKey: Data? = nil,
             nativeCredentialSecret: String? = nil) {
            self.userId = userId
            self.primaryKey = primaryKey
            self.fallbackPrimaryKey = fallbackPrimaryKey
            self.nativeCredentialSecret = nativeCredentialSecret
        }

        enum CodingKeys: CodingKey {
            case userId
            case primaryKey
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.userId = try container.decode(String.self, forKey: .userId)
            self.primaryKey = try container.decode(Data.self, forKey: .primaryKey)
            self.fallbackPrimaryKey = nil
            self.nativeCredentialSecret = nil
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.userId, forKey: .userId)
            try container.encode(self.primaryKey, forKey: .primaryKey)
        }
    }

    public struct ConnectCode: Codable, Sendable {
        let deviceId: String
        let secretKey: Data
    }

    public struct ExchangeKey: Codable, Sendable {
        let keyId: String
        let publicKey: Data
    }

    /// V2 recovery code payload. All fields are snake_case on the wire.
    /// `secret` semantics are credential-specific:
    /// - `cid == "ddg"`: native credential secret seed string (base64URL).
    /// - `cid == "3party"`: base64URL of raw scoped-password bytes.
    /// `v` is `"major.minor"` for compatibility across minor schema changes.
    public struct RecoveryKeyV2: Codable, Sendable, Equatable {
        static let currentVersion = "2.0"
        static let nativeCredentialId = "ddg"
        static let thirdPartyCredentialId = "3party"

        let userId: String
        let secret: String
        let cid: String
        let v: String
    }

    /// Versioned `recovery` payload. Distinguishes v1 (no `v` field — current native shape
    /// with `primary_key`) from v2 (`v: "2.0"` — new shape with `secret`/`cid`).
    ///
    /// Per versioning rules:
    /// - missing `v` field is treated as v1
    /// - `v` major == `Self.supportedMajor` is accepted; unknown fields ignored (minor compat)
    /// - `v` major > `Self.supportedMajor` is rejected with `RecoveryCodeVersionError.unsupported`,
    ///   even if the payload is otherwise structurally parseable
    public enum Recovery: Codable, Sendable, Equatable {
        case v1(RecoveryKey)
        case v2(RecoveryKeyV2)

        /// Highest major version of the recovery payload this client understands.
        public static let supportedMajor = 2

        private enum ProbeKeys: CodingKey {
            case v
        }

        public init(from decoder: Decoder) throws {
            let probe = try decoder.container(keyedBy: ProbeKeys.self)
            let rawVersion = try probe.decodeIfPresent(String.self, forKey: .v)
            switch rawVersion {
            case nil:
                self = .v1(try RecoveryKey(from: decoder))
            case let raw?:
                let major = try Self.parseMajor(raw)
                guard major <= Self.supportedMajor else {
                    throw RecoveryCodeVersionError.unsupported(raw)
                }
                self = .v2(try RecoveryKeyV2(from: decoder))
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .v1(let v1):
                try v1.encode(to: encoder)
            case .v2(let v2):
                try v2.encode(to: encoder)
            }
        }

        /// Legacy conversion helper that interprets v2 `secret` as base64URL(primaryKey).
        /// Internal native login paths should prefer `nativeRecoveryKey(using:)`.
        public func nativeRecoveryKey() -> RecoveryKey? {
            switch self {
            case .v1(let recoveryKey):
                return recoveryKey
            case .v2(let payload):
                guard payload.cid == RecoveryKeyV2.nativeCredentialId,
                      let primaryKey = Base64URL.decode(payload.secret) else {
                    return nil
                }
                return RecoveryKey(userId: payload.userId,
                                   primaryKey: primaryKey,
                                   nativeCredentialSecret: payload.secret)
            }
        }

        func nativeRecoveryKey(using crypter: CryptingInternal) -> RecoveryKey? {
            switch self {
            case .v1(let recoveryKey):
                return recoveryKey
            case .v2(let payload):
                guard payload.cid == RecoveryKeyV2.nativeCredentialId else {
                    return nil
                }

                let legacyPrimaryKey = Base64URL.decode(payload.secret)
                guard let accountCreationKeys = try? crypter.createAccountCreationKeys(userId: payload.userId, password: payload.secret) else {
                    guard let legacyPrimaryKey else {
                        return nil
                    }
                    return RecoveryKey(userId: payload.userId,
                                       primaryKey: legacyPrimaryKey,
                                       nativeCredentialSecret: payload.secret)
                }

                let derivedPrimaryKey = accountCreationKeys.primaryKey
                let fallbackPrimaryKey = legacyPrimaryKey == derivedPrimaryKey ? nil : legacyPrimaryKey
                // Migration compatibility: pre-fix native v2 payloads stored primary-key bytes in
                // `secret`. Keep that candidate so login can retry if the new seed-based path fails.
                return RecoveryKey(userId: payload.userId,
                                   primaryKey: derivedPrimaryKey,
                                   fallbackPrimaryKey: fallbackPrimaryKey,
                                   nativeCredentialSecret: payload.secret)
            }
        }

        private static func parseMajor(_ raw: String) throws -> Int {
            guard
                let majorString = raw.split(separator: ".").first,
                let major = Int(majorString)
            else {
                throw RecoveryCodeVersionError.malformed(raw)
            }
            return major
        }
    }

    public var recovery: Recovery?
    public var connect: ConnectCode?
    public var exchangeKey: ExchangeKey?

    public static func decode(_ data: Data) throws -> Self {
        return try JSONDecoder.snakeCaseKeys.decode(self, from: data)
    }

    public func toJSON() throws -> Data {
        return try JSONEncoder.snakeCaseKeys.encode(self)
    }

    /// Decodes a `SyncCode` payload from either encoding. Tries standard base64
    /// first (the v1 wire format), then falls back to base64URL (the v2 wire
    /// format). The fallback is unambiguous because Foundation's
    /// `Data(base64Encoded:)` strictly rejects the URL-safe alphabet (`-`/`_`),
    /// so the second branch only matches inputs the first one couldn't decode.
    public static func decodeBase64String(_ string: String) throws -> Self {
        if let data = Data(base64Encoded: string) {
            return try Self.decode(data)
        }
        if let data = Base64URL.decode(string) {
            return try Self.decode(data)
        }
        throw Base64Error.error
    }

    /// Decodes a strictly base64URL-encoded `SyncCode` payload. Most callers
    /// should use `decodeBase64String(_:)` instead, which accepts both encodings.
    public static func decodeBase64URLString(_ string: String) throws -> Self {
        guard let data = Base64URL.decode(string) else {
            throw Base64Error.error
        }
        return try Self.decode(data)
    }

}
