//
//  PairingV2MessageCrypto.swift
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
import Security

enum PairingV2MessageCryptoError: Error, Equatable {
    case invalidPublicKey
    case invalidPrivateKey
    case invalidTokenPartCount(Int)
    case invalidBase64URLComponent
    case unsupportedVersion(String)
    case unsupportedProtectedHeader
    case keyGenerationFailed
    case publicKeyExtractionFailed
    case publicKeyExportFailed
    case randomBytesGenerationFailed(OSStatus)
    case rsaEncryptionFailed
    case rsaDecryptionFailed
    case aesGCMEncryptionFailed
    case aesGCMDecryptionFailed
}

struct PairingV2KeyPair {
    let channelID: String
    let publicKey: String
    let privateKey: SecKey
}

enum PairingV2KeyPairFactory {

    private static let rsaKeySizeInBits = 2048

    static func makeKeyPair(channelID: String = UUID().uuidString) throws -> PairingV2KeyPair {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: rsaKeySizeInBits,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false
            ]
        ]

        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, nil) else {
            throw PairingV2MessageCryptoError.keyGenerationFailed
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw PairingV2MessageCryptoError.publicKeyExtractionFailed
        }
        guard let publicKeyPKCS1 = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw PairingV2MessageCryptoError.publicKeyExportFailed
        }

        return PairingV2KeyPair(channelID: channelID,
                                publicKey: Base64URL.encode(PairingV2DER.wrapRSAPublicKeyInSPKI(publicKeyPKCS1)),
                                privateKey: privateKey)
    }
}

final class PairingV2MessageCrypto {

    private static let supportedMajorVersion = 2
    private let contentEncryptionKeyLength = 32
    private let ivLength = 12

    func encrypt(_ message: PairingV2ApplicationMessage,
                 recipientPublicKey: String,
                 senderChannelID: String) throws -> PairingV2EncryptedMessage {
        let payload = try encode(message)
        let publicKey = try makePublicKey(fromSPKIBase64URL: recipientPublicKey)
        let compactJWE = try encrypt(payload, recipientPublicKey: publicKey, kid: senderChannelID)
        return PairingV2EncryptedMessage(payload: compactJWE)
    }

    func decrypt(_ message: PairingV2EncryptedMessage,
                 privateKey: SecKey,
                 expectedSenderChannelID: String? = nil) throws -> PairingV2ApplicationMessage? {
        try validateSupportedVersion(message.version)
        let payload = try decrypt(token: message.payload, privateKey: privateKey, expectedSenderChannelID: expectedSenderChannelID)
        return try decode(payload)
    }

    private func encode(_ message: PairingV2ApplicationMessage) throws -> Data {
        switch message {
        case .hello(let message):
            return try JSONEncoder.snakeCaseKeys.encode(message)
        case .recoveryCodeAvailable(let message),
                .recoveryCodeRequest(let message):
            return try JSONEncoder.snakeCaseKeys.encode(message)
        case .recoveryCodeDenied(let message),
                .recoveryCodeUnavailable(let message):
            return try JSONEncoder.snakeCaseKeys.encode(message)
        case .recoveryCodeResponse(let message):
            return try JSONEncoder.snakeCaseKeys.encode(message)
        }
    }

    private func decode(_ payload: Data) throws -> PairingV2ApplicationMessage? {
        let type = try JSONDecoder.snakeCaseKeys.decode(MessageTypeProbe.self, from: payload).type
        switch type {
        case PairingV2HelloMessage.messageType:
            return .hello(try JSONDecoder.snakeCaseKeys.decode(PairingV2HelloMessage.self, from: payload))
        case PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable:
            return .recoveryCodeAvailable(try JSONDecoder.snakeCaseKeys.decode(PairingV2RecoveryCodeStatusMessage.self, from: payload))
        case PairingV2ApplicationMessage.MessageType.recoveryCodeRequest:
            return .recoveryCodeRequest(try JSONDecoder.snakeCaseKeys.decode(PairingV2RecoveryCodeStatusMessage.self, from: payload))
        case PairingV2ApplicationMessage.MessageType.recoveryCodeDenied:
            return .recoveryCodeDenied(try JSONDecoder.snakeCaseKeys.decode(PairingV2RecoveryCodeTerminalMessage.self, from: payload))
        case PairingV2ApplicationMessage.MessageType.recoveryCodeUnavailable:
            return .recoveryCodeUnavailable(try JSONDecoder.snakeCaseKeys.decode(PairingV2RecoveryCodeTerminalMessage.self, from: payload))
        case PairingV2RecoveryCodeResponseMessage.messageType:
            return .recoveryCodeResponse(try JSONDecoder.snakeCaseKeys.decode(PairingV2RecoveryCodeResponseMessage.self, from: payload))
        default:
            return nil
        }
    }

    private func encrypt(_ payload: Data, recipientPublicKey: SecKey, kid: String) throws -> String {
        let contentEncryptionKey = try randomBytes(count: contentEncryptionKeyLength)
        let encryptedContentEncryptionKey = try encryptContentEncryptionKey(contentEncryptionKey, recipientPublicKey: recipientPublicKey)
        let iv = try randomBytes(count: ivLength)
        let protectedHeader = Self.encodedProtectedHeader(kid: kid)
        let encryptedPayload = try aesGCMEncrypt(plaintext: payload,
                                                 contentEncryptionKey: contentEncryptionKey,
                                                 iv: iv,
                                                 additionalAuthenticatedData: Data(protectedHeader.utf8))

        return [
            protectedHeader,
            Base64URL.encode(encryptedContentEncryptionKey),
            Base64URL.encode(iv),
            Base64URL.encode(encryptedPayload.ciphertext),
            Base64URL.encode(encryptedPayload.authenticationTag)
        ].joined(separator: ".")
    }

    private func decrypt(token: String, privateKey: SecKey, expectedSenderChannelID: String?) throws -> Data {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5 else {
            throw PairingV2MessageCryptoError.invalidTokenPartCount(parts.count)
        }
        try decodeProtectedHeader(parts[0], expectedSenderChannelID: expectedSenderChannelID)

        guard let encryptedContentEncryptionKey = Base64URL.decode(parts[1]),
              let iv = Base64URL.decode(parts[2]),
              let ciphertext = Base64URL.decode(parts[3]),
              let authenticationTag = Base64URL.decode(parts[4]),
              authenticationTag.count == 16
        else {
            throw PairingV2MessageCryptoError.invalidBase64URLComponent
        }

        let contentEncryptionKey = try decryptContentEncryptionKey(encryptedContentEncryptionKey, privateKey: privateKey)
        return try aesGCMDecrypt(ciphertext: ciphertext,
                                 authenticationTag: authenticationTag,
                                 contentEncryptionKey: contentEncryptionKey,
                                 iv: iv,
                                 additionalAuthenticatedData: Data(parts[0].utf8))
    }

    private static func encodedProtectedHeader(kid: String) -> String {
        Base64URL.encode(Data(#"{"alg":"RSA-OAEP-256","enc":"A256GCM","kid":"\#(kid)"}"#.utf8))
    }

    private func decodeProtectedHeader(_ encodedHeader: String, expectedSenderChannelID: String?) throws {
        guard let protectedHeaderData = Base64URL.decode(encodedHeader),
              let protectedHeader = try? JSONDecoder().decode(ProtectedHeader.self, from: protectedHeaderData),
              protectedHeader.alg == "RSA-OAEP-256",
              protectedHeader.enc == "A256GCM" else {
            throw PairingV2MessageCryptoError.unsupportedProtectedHeader
        }
        if let expectedSenderChannelID, protectedHeader.kid != expectedSenderChannelID {
            throw PairingV2MessageCryptoError.unsupportedProtectedHeader
        }
    }

    private func validateSupportedVersion(_ version: String) throws {
        guard let majorString = version.split(separator: ".").first,
              let major = Int(majorString),
              major == Self.supportedMajorVersion else {
            throw PairingV2MessageCryptoError.unsupportedVersion(version)
        }
    }

    private func makePublicKey(fromSPKIBase64URL publicKey: String) throws -> SecKey {
        guard let spki = Base64URL.decode(publicKey),
              let publicKeyPKCS1 = try? PairingV2DER.unwrapRSAPublicKeySPKI(spki) else {
            throw PairingV2MessageCryptoError.invalidPublicKey
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 2048
        ]
        guard let key = SecKeyCreateWithData(publicKeyPKCS1 as CFData, attributes as CFDictionary, nil) else {
            throw PairingV2MessageCryptoError.invalidPublicKey
        }
        return key
    }

    private func encryptContentEncryptionKey(_ contentEncryptionKey: Data, recipientPublicKey: SecKey) throws -> Data {
        guard SecKeyIsAlgorithmSupported(recipientPublicKey, .encrypt, .rsaEncryptionOAEPSHA256) else {
            throw PairingV2MessageCryptoError.invalidPublicKey
        }

        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(recipientPublicKey,
                                                        .rsaEncryptionOAEPSHA256,
                                                        contentEncryptionKey as CFData,
                                                        &error) as Data? else {
            throw PairingV2MessageCryptoError.rsaEncryptionFailed
        }
        return encrypted
    }

    private func decryptContentEncryptionKey(_ encryptedContentEncryptionKey: Data, privateKey: SecKey) throws -> Data {
        guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, .rsaEncryptionOAEPSHA256) else {
            throw PairingV2MessageCryptoError.invalidPrivateKey
        }

        var error: Unmanaged<CFError>?
        guard let decrypted = SecKeyCreateDecryptedData(privateKey,
                                                        .rsaEncryptionOAEPSHA256,
                                                        encryptedContentEncryptionKey as CFData,
                                                        &error) as Data? else {
            throw PairingV2MessageCryptoError.rsaDecryptionFailed
        }
        return decrypted
    }

    private func randomBytes(count: Int) throws -> Data {
        do {
            return try JWEA256GCMCipher.randomBytes(count: count)
        } catch JWEA256GCMCipherError.randomBytesGenerationFailed(let status) {
            throw PairingV2MessageCryptoError.randomBytesGenerationFailed(status)
        } catch {
            throw error
        }
    }

    private func aesGCMEncrypt(plaintext: Data,
                               contentEncryptionKey: Data,
                               iv: Data,
                               additionalAuthenticatedData: Data) throws -> (ciphertext: Data, authenticationTag: Data) {
        do {
            return try JWEA256GCMCipher.aesGCMEncrypt(plaintext: plaintext,
                                                      contentEncryptionKey: contentEncryptionKey,
                                                      iv: iv,
                                                      additionalAuthenticatedData: additionalAuthenticatedData)
        } catch JWEA256GCMCipherError.aesGCMEncryptionFailed {
            throw PairingV2MessageCryptoError.aesGCMEncryptionFailed
        } catch {
            throw error
        }
    }

    private func aesGCMDecrypt(ciphertext: Data,
                               authenticationTag: Data,
                               contentEncryptionKey: Data,
                               iv: Data,
                               additionalAuthenticatedData: Data) throws -> Data {
        do {
            return try JWEA256GCMCipher.aesGCMDecrypt(ciphertext: ciphertext,
                                                      authenticationTag: authenticationTag,
                                                      contentEncryptionKey: contentEncryptionKey,
                                                      iv: iv,
                                                      additionalAuthenticatedData: additionalAuthenticatedData)
        } catch JWEA256GCMCipherError.aesGCMDecryptionFailed {
            throw PairingV2MessageCryptoError.aesGCMDecryptionFailed
        } catch {
            throw error
        }
    }

    private struct MessageTypeProbe: Decodable {
        let type: String
    }

    private struct ProtectedHeader: Decodable {
        let alg: String
        let enc: String
        let kid: String?
    }
}

private enum PairingV2DER {
    private static let rsaEncryptionOID = Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])
    private static let null = Data([0x05, 0x00])

    static func wrapRSAPublicKeyInSPKI(_ publicKeyPKCS1: Data) -> Data {
        sequence([
            sequence([rsaEncryptionOID, null]),
            bitString(publicKeyPKCS1)
        ])
    }

    static func unwrapRSAPublicKeySPKI(_ spki: Data) throws -> Data {
        var cursor = Cursor(bytes: [UInt8](spki))
        try cursor.expect(tag: 0x30)
        _ = try cursor.readLength()
        try cursor.expect(tag: 0x30)
        let algorithmIdentifierLength = try cursor.readLength()
        _ = try cursor.readBytes(count: algorithmIdentifierLength)
        try cursor.expect(tag: 0x03)
        let bitStringLength = try cursor.readLength()
        let bitString = try cursor.readBytes(count: bitStringLength)
        guard bitString.first == 0x00 else {
            throw PairingV2MessageCryptoError.invalidPublicKey
        }
        return Data(bitString.dropFirst())
    }

    private static func sequence(_ parts: [Data]) -> Data {
        var contents = Data()
        parts.forEach { contents.append($0) }
        return wrap(tag: 0x30, contents: contents)
    }

    private static func bitString(_ data: Data) -> Data {
        var contents = Data([0x00])
        contents.append(data)
        return wrap(tag: 0x03, contents: contents)
    }

    private static func wrap(tag: UInt8, contents: Data) -> Data {
        var output = Data([tag])
        output.append(lengthBytes(for: contents.count))
        output.append(contents)
        return output
    }

    private static func lengthBytes(for length: Int) -> Data {
        if length < 0x80 {
            return Data([UInt8(length)])
        }

        var remainingLength = length
        var bytes: [UInt8] = []
        while remainingLength > 0 {
            bytes.insert(UInt8(remainingLength & 0xFF), at: 0)
            remainingLength >>= 8
        }

        var encoded = Data([0x80 | UInt8(bytes.count)])
        encoded.append(contentsOf: bytes)
        return encoded
    }

    private struct Cursor {
        let bytes: [UInt8]
        var index = 0

        mutating func expect(tag: UInt8) throws {
            guard index < bytes.count, bytes[index] == tag else {
                throw PairingV2MessageCryptoError.invalidPublicKey
            }
            index += 1
        }

        mutating func readLength() throws -> Int {
            guard index < bytes.count else {
                throw PairingV2MessageCryptoError.invalidPublicKey
            }

            let first = bytes[index]
            index += 1

            if first & 0x80 == 0 {
                return Int(first)
            }

            let byteCount = Int(first & 0x7F)
            guard byteCount > 0, byteCount <= 4 else {
                throw PairingV2MessageCryptoError.invalidPublicKey
            }

            var length = 0
            for _ in 0..<byteCount {
                guard index < bytes.count else {
                    throw PairingV2MessageCryptoError.invalidPublicKey
                }
                length = (length << 8) | Int(bytes[index])
                index += 1
            }
            return length
        }

        mutating func readBytes(count: Int) throws -> [UInt8] {
            guard count >= 0, index + count <= bytes.count else {
                throw PairingV2MessageCryptoError.invalidPublicKey
            }

            let value = Array(bytes[index..<(index + count)])
            index += count
            return value
        }
    }
}
