//
//  ScopedAccessKeyFactory.swift
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

enum ScopedAccessKeyFactoryError: Error {
    case randomBytesGenerationFailed(OSStatus)
    case keyGenerationFailed
    case publicKeyExtractionFailed
    case publicKeyExportFailed
    case privateKeyExportFailed
    case invalidRSAPublicKeyDER
    case invalidWrappingKeyLength(Int)
}

enum ScopedAccessKeyFactory {

    private static let scopedPasswordLength = 32
    private static let rsaKeySizeInBits = 2048

    struct RSAKeyMaterial {
        let publicKeyJWK: ProtectedKeyPublicKey
        let privateKeyPKCS8: Data
    }

    static func makeScopedPassword() throws -> Data {
        try randomBytes(count: scopedPasswordLength)
    }

    static func makeRSAKeyMaterial() throws -> RSAKeyMaterial {
        let keyPair = try makeRSAKeyPair()
        let publicKeyPKCS1 = try copyExternalRepresentation(for: keyPair.publicKey,
                                                            error: .publicKeyExportFailed)
        let privateKeyPKCS1 = try copyExternalRepresentation(for: keyPair.privateKey,
                                                             error: .privateKeyExportFailed)

        return RSAKeyMaterial(
            publicKeyJWK: try makeRSAPublicJWK(fromPKCS1DER: publicKeyPKCS1),
            privateKeyPKCS8: DEREncoding.wrapRSAPrivateKeyInPKCS8(privateKeyPKCS1)
        )
    }

    /// Generates a fresh RSA-2048 KEK pair and wraps its private key using direct JWE
    /// (`alg=dir`, `enc=A256GCM`).
    ///
    /// Native `ddg` key creation encrypts keys with the account secret, not direct JWE.
    /// Keep this helper for JWE-based wrapping use cases, including 3party keys and test fixtures.
    static func makeJWEProtectedKey(wrappingKey: Data,
                                    encryptedWith: String,
                                    purpose: String) throws -> ProtectedKey {
        let keyMaterial = try makeRSAKeyMaterial()
        let encryptedPrivateKey = try encryptAsDirectJWE(keyMaterial.privateKeyPKCS8,
                                                         withWrappingKey: wrappingKey,
                                                         kid: encryptedWith)

        return ProtectedKey(kid: UUID().uuidString,
                            encryptedPrivateKey: encryptedPrivateKey,
                            publicKey: keyMaterial.publicKeyJWK,
                            encryptedWith: encryptedWith,
                            purpose: purpose)
    }

    private static func makeRSAKeyPair() throws -> (publicKey: SecKey, privateKey: SecKey) {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: rsaKeySizeInBits,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false
            ]
        ]

        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, nil) else {
            throw ScopedAccessKeyFactoryError.keyGenerationFailed
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw ScopedAccessKeyFactoryError.publicKeyExtractionFailed
        }

        return (publicKey, privateKey)
    }

    private static func copyExternalRepresentation(for key: SecKey,
                                                   error: ScopedAccessKeyFactoryError) throws -> Data {
        guard let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            throw error
        }
        return keyData
    }

    private static func encryptAsDirectJWE(_ plaintext: Data,
                                           withWrappingKey wrappingKey: Data,
                                           kid: String) throws -> String {
        guard wrappingKey.count == 32 else {
            throw ScopedAccessKeyFactoryError.invalidWrappingKeyLength(wrappingKey.count)
        }
        return try JWECompactCodec().encryptDirect(payload: plaintext,
                                                   contentEncryptionKey: wrappingKey,
                                                   kid: kid)
    }

    private static func randomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }
        guard status == errSecSuccess else {
            throw ScopedAccessKeyFactoryError.randomBytesGenerationFailed(status)
        }
        return data
    }

    private static func makeRSAPublicJWK(fromPKCS1DER der: Data) throws -> ProtectedKeyPublicKey {
        let (modulus, exponent) = try RSAPublicKeyDERParser.parseModulusAndExponent(fromPKCS1DER: der)
        return ProtectedKeyPublicKey(alg: "RSA-OAEP-256",
                                     e: Base64URL.encode(stripLeadingZeroByteIfPresent(exponent)),
                                     ext: true,
                                     keyOps: ["encrypt"],
                                     kty: "RSA",
                                     n: Base64URL.encode(stripLeadingZeroByteIfPresent(modulus)),
                                     use: "enc")
    }

    private static func stripLeadingZeroByteIfPresent(_ value: Data) -> Data {
        guard value.first == 0x00 else {
            return value
        }
        return value.dropFirst()
    }
}

private enum RSAPublicKeyDERParser {
    private struct Cursor {
        var index = 0
    }

    static func parseModulusAndExponent(fromPKCS1DER der: Data) throws -> (modulus: Data, exponent: Data) {
        var cursor = Cursor()
        let bytes = [UInt8](der)

        try expectTag(0x30, in: bytes, cursor: &cursor)
        _ = try readLength(in: bytes, cursor: &cursor)

        try expectTag(0x02, in: bytes, cursor: &cursor)
        let modulusLength = try readLength(in: bytes, cursor: &cursor)
        let modulus = try readBytes(count: modulusLength, in: bytes, cursor: &cursor)

        try expectTag(0x02, in: bytes, cursor: &cursor)
        let exponentLength = try readLength(in: bytes, cursor: &cursor)
        let exponent = try readBytes(count: exponentLength, in: bytes, cursor: &cursor)

        return (Data(modulus), Data(exponent))
    }

    private static func expectTag(_ expected: UInt8, in bytes: [UInt8], cursor: inout Cursor) throws {
        guard cursor.index < bytes.count, bytes[cursor.index] == expected else {
            throw ScopedAccessKeyFactoryError.invalidRSAPublicKeyDER
        }
        cursor.index += 1
    }

    private static func readLength(in bytes: [UInt8], cursor: inout Cursor) throws -> Int {
        guard cursor.index < bytes.count else {
            throw ScopedAccessKeyFactoryError.invalidRSAPublicKeyDER
        }

        let first = bytes[cursor.index]
        cursor.index += 1

        if first & 0x80 == 0 {
            return Int(first)
        }

        let byteCount = Int(first & 0x7F)
        guard byteCount > 0, byteCount <= 4 else {
            throw ScopedAccessKeyFactoryError.invalidRSAPublicKeyDER
        }

        var length = 0
        for _ in 0..<byteCount {
            guard cursor.index < bytes.count else {
                throw ScopedAccessKeyFactoryError.invalidRSAPublicKeyDER
            }
            length = (length << 8) | Int(bytes[cursor.index])
            cursor.index += 1
        }
        return length
    }

    private static func readBytes(count: Int, in bytes: [UInt8], cursor: inout Cursor) throws -> [UInt8] {
        guard count >= 0, cursor.index + count <= bytes.count else {
            throw ScopedAccessKeyFactoryError.invalidRSAPublicKeyDER
        }
        let value = Array(bytes[cursor.index..<(cursor.index + count)])
        cursor.index += count
        return value
    }
}

private enum DEREncoding {
    private static let rsaEncryptionOID = Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])
    private static let null = Data([0x05, 0x00])
    private static let integerZero = Data([0x02, 0x01, 0x00])

    private static var rsaAlgorithmIdentifier: Data {
        sequence([rsaEncryptionOID, null])
    }

    static func wrapRSAPrivateKeyInPKCS8(_ privateKeyPKCS1: Data) -> Data {
        sequence([
            integerZero,
            rsaAlgorithmIdentifier,
            octetString(privateKeyPKCS1)
        ])
    }

    private static func sequence(_ parts: [Data]) -> Data {
        var contents = Data()
        parts.forEach { contents.append($0) }
        return wrap(tag: 0x30, contents: contents)
    }

    private static func octetString(_ data: Data) -> Data {
        wrap(tag: 0x04, contents: data)
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
        var bytes = [UInt8]()
        while remainingLength > 0 {
            bytes.insert(UInt8(remainingLength & 0xFF), at: 0)
            remainingLength >>= 8
        }

        var encoded = Data([0x80 | UInt8(bytes.count)])
        encoded.append(contentsOf: bytes)
        return encoded
    }
}
