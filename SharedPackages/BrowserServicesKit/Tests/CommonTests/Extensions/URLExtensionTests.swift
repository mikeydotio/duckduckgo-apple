//
//  URLExtensionTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import CoreFoundation
import Foundation
import Testing

@testable import Common

// swiftlint:disable comma
final class URLExtensionTests {

    // MARK: - isOpaque

    @available(iOS 16, macOS 13, *)
    @Test("isOpaque — opaque URLs", .timeLimit(.minutes(1)),
          arguments: [
              "about:blank",
              "about:newtab",
              "data:text/html,<h1>Hi</h1>",
              "data:text/html;base64,SGVsbG8=",
              "javascript:void(0)",
              "javascript:window.location.href",
              "blob:https://example.com/550e8400-e29b-41d4-a716-446655440000",
          ])
    func isOpaque_trueForOpaqueURLs(rawURL: String) throws {
        let url = try #require(URL(string: rawURL))
        #expect(url.isOpaque == true, "expected isOpaque=true for \(rawURL)")
    }

    @available(iOS 16, macOS 13, *)
    @Test("isOpaque — NSURL-bridged opaque URLs", .timeLimit(.minutes(1)),
          arguments: [
              "about:blank",
              "data:text/html,hello",
              "javascript:void(0)",
          ])
    func isOpaque_trueForNSURLBridgedOpaqueURLs(rawURL: String) throws {
        let nsurl = try #require(NSURL(string: rawURL))
        let url = nsurl as URL
        #expect(url.isOpaque == true, "expected isOpaque=true for NSURL-bridged \(rawURL)")
    }

    @available(iOS 16, macOS 13, *)
    @Test("isOpaque — hierarchical URLs", .timeLimit(.minutes(1)),
          arguments: [
              "https://example.com",
              "https://example.com/path?q=1#frag",
              "http://example.com",
              "file:///Users/user/file.txt",
              "ftp://ftp.example.com/pub",
          ])
    func isOpaque_falseForHierarchicalURLs(rawURL: String) throws {
        let url = try #require(URL(string: rawURL))
        #expect(url.isOpaque == false, "expected isOpaque=false for \(rawURL)")
    }

    // MARK: - External URLs

    @available(iOS 16, macOS 13, *)
    @Test("External URLs are valid", .timeLimit(.minutes(1)))
    func external_urls_are_valid() {
        #expect("mailto://user@host.tld".url!.isValid)
        #expect("sms://+44776424232323".url!.isValid)
        #expect("ftp://example.com".url!.isValid)
    }

    static let navigational_urls_args: [(String, UInt)] = [
        ("http://example.com", #line),
        ("https://example.com", #line),
        ("http://localhost", #line),
        ("http://localdomain", #line),
        ("https://dax%40duck.com:123%3A456A@www.duckduckgo.com/test.php?test=S&info=test#fragment", #line),
        ("user@somehost.local:9091/index.html", #line),
        ("user:@something.local:9100", #line),
        ("user:%20@localhost:5000", #line),
        ("user:passwOrd@localhost:5000", #line),
        ("user%40local:pa%24%24s@localhost:5000", #line),
        ("mailto:test@example.com", #line),
        ("192.168.1.1", #line),
        ("http://192.168.1.1", #line),
        ("http://sheep%2B:P%40%24swrd@192.168.1.1", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1/", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1:8900/", #line),
        ("sheep%2B:P%40%24swrd@💩.la?arg=b#1", #line),
        ("sheep%2B:P%40%24swrd@xn--ls8h.la/?arg=b#1", #line),
        ("https://sheep%2B:P%40%24swrd@💩.la", #line),
        ("data:text/vnd-example+xyz;foo=bar;base64,R0lGODdh", #line),
        ("http://192.168.0.1", #line),
        ("http://203.0.113.0", #line),
        ("http://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]", #line),
        ("http://[2001:0db8::1]", #line),
        ("http://[::]:8080", #line),
        ("https://www.duckduckgo.com/html?q =search", #line),
    ]

    @available(iOS 16, macOS 13, *)
    @Test("Navigational URLs are valid", .timeLimit(.minutes(1)), arguments: navigational_urls_args)
    func navigational_urls_are_valid(rawValue: String, line: UInt) throws {
        if #available(macOS 14, *) {
            // This test can't run on macOS 14 or higher
            return
        }

        let url = rawValue.decodedURL
        #expect(url != nil, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
        #expect(url!.isValid, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }

    static let non_valid_urls_args = [
        "about:user:pass@blank",
        "data:user:pass@text/vnd-example+xyz;foo=bar;base64,R0lGODdh",
    ]

    @available(iOS 16, macOS 13, *)
    @Test("Non-valid URLs", .timeLimit(.minutes(1)))
    func non_valid_urls() throws {
        if #available(macOS 14, *) {
            // This test can't run on macOS 14 or higher
            return
        }

        for item in Self.non_valid_urls_args {
            #expect(item.url == nil)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL scheme is added when missing", .timeLimit(.minutes(1)))
    func when_no_scheme_in_string_url_has_scheme() {
        #expect("duckduckgo.com".url!.absoluteString == "http://duckduckgo.com")
        #expect("example.com".url!.absoluteString == "http://example.com")
        #expect("localhost".url!.absoluteString == "http://localhost")
        #expect("localdomain".url == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("IPv4 addresses must contain four octets", .timeLimit(.minutes(1)))
    func ipv4AddressMustContainFourOctets() {
        #expect("1.4".url == nil)
        #expect("1.4/3.4".url == nil)
        #expect("1.0.4".url == nil)
        #expect("127.0.1".url == nil)

        #expect("127.0.0.1".url?.absoluteString == "http://127.0.0.1")
        #expect("1.0.0.4/3.4".url?.absoluteString == "http://1.0.0.4/3.4")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.naked returns a normalized URL without scheme, www prefix, and trailing slash", .timeLimit(.minutes(1)))
    func nakedIsCalled_returnsURLWithNoSchemeWWWPrefixAndLastSlash() {
        let url = URL(string: "http://duckduckgo.com")!
        let duplicate = URL(string: "https://www.duckduckgo.com/")!

        #expect(url.naked == duplicate.naked)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.root returns a URL with the host only, removing all other components", .timeLimit(.minutes(1)))
    func rootIsCalled_returnsURLWithNoPathQueryFragmentUserAndPassword() {
        let url = URL(string: "https://dax:123456@www.duckduckgo.com/test.php?test=S&info=test#fragment")!

        let rootUrl = url.root!
        #expect(rootUrl == URL(string: "https://www.duckduckgo.com/")!)
        #expect(rootUrl.isRoot)
    }

    static let basicAuthCredential_args: [(String, String?, String?, UInt)] = [
        ("https://dax%40duck.com:123%3A456A@www.duckduckgo.com/test.php?test=S&info=test#fragment", "dax@duck.com", "123:456A", #line),
        ("user@somehost.local:9091/index.html", "user", "", #line),
        ("user:@something.local:9100", "user", "", #line),
        ("user:%20@localhost:5000", "user", " ", #line),
        ("user:passwOrd@localhost:5000", "user", "passwOrd", #line),
        ("user%40local:pa%24%24@localhost:5000", "user@local", "pa$$", #line),
        ("mailto:test@example.com", nil, nil, #line),
        ("sheep%2B:P%40%24swrd@💩.la", "sheep+", "P@$swrd", #line),
        ("sheep%2B:P%40%24swrd@xn--ls8h.la/", "sheep+", "P@$swrd", #line),
        ("https://sheep%2B:P%40%24swrd@💩.la", "sheep+", "P@$swrd", #line),
        ("http://sheep%2B:P%40%24swrd@192.168.1.1", "sheep+", "P@$swrd", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1", "sheep+", "P@$swrd", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1/", "sheep+", "P@$swrd", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1:8900/", "sheep+", "P@$swrd", #line),
    ]

    @available(iOS 16, macOS 13, *)
    @Test("Basic auth credentials are correctly extracted from URLs", .timeLimit(.minutes(1)), arguments: basicAuthCredential_args)
    func basicAuthCredential(url: String, user: String?, password: String?, line: UInt) throws {
        if #available(macOS 14, *) {
            // This test can't run on macOS 14 or higher
            return
        }

        let credential = url.decodedURL!.basicAuthCredential
        #expect(credential?.user == user, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
        #expect(credential?.password == password, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }

    static let urlRemovingBasicAuthCredential_args: [(String, String, UInt)] = [
        ("https://dax%40duck.com:123%3A456A@www.duckduckgo.com/test.php?test=S&info=test#fragment", "https://www.duckduckgo.com/test.php?test=S&info=test#fragment", #line),
        ("user@somehost.local:9091/index.html", "http://somehost.local:9091/index.html", #line),
        ("user:@something.local:9100", "http://something.local:9100", #line),
        ("user:%20@localhost:5000", "http://localhost:5000", #line),
        ("user:passwOrd@localhost:5000", "http://localhost:5000", #line),
        ("user%40local:pa%24%24s@localhost:5000", "http://localhost:5000", #line),
        ("mailto:test@example.com", "mailto:test@example.com", #line),
        ("sheep%2B:P%40%24swrd@💩.la", "http://xn--ls8h.la", #line),
        ("sheep%2B:P%40%24swrd@xn--ls8h.la/", "http://xn--ls8h.la/", #line),
        ("https://sheep%2B:P%40%24swrd@💩.la", "https://xn--ls8h.la", #line),
        ("http://sheep%2B:P%40%24swrd@192.168.1.1", "http://192.168.1.1", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1", "http://192.168.1.1", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1/", "http://192.168.1.1/", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1:8900", "http://192.168.1.1:8900", #line),
        ("sheep%2B:P%40%24swrd@192.168.1.1:8900/", "http://192.168.1.1:8900/", #line),
    ]

    @available(iOS 16, macOS 13, *)
    @Test("Basic auth credentials are correctly removed from URLs", .timeLimit(.minutes(1)), arguments: urlRemovingBasicAuthCredential_args)
    func urlRemovingBasicAuthCredential(url: String, removingCredential: String, line: UInt) throws {
        if #available(macOS 14, *) {
            // This test can't run on macOS 14 or higher
            return
        }

        let filtered = url.decodedURL!.removingBasicAuthCredential()
        #expect(filtered.absoluteString == removingCredential, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.isRoot correctly identifies root URLs", .timeLimit(.minutes(1)))
    func isRoot() {
        let url = URL(string: "https://www.server.com:8080/path?query=string#fragment")!
        let rootUrl = URL(string: "https://www.server.com:8080/")!

        #expect(rootUrl.isRoot)
        #expect(!url.isRoot)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.appendingParameter doesn't change the original URL", .timeLimit(.minutes(1)))
    func addParameterIsCalled_doesNotChangeExistingURL() {
        let url = URL(string: "https://duckduckgo.com/?q=Battle%20star+Galactica%25a")!

        #expect(
            url.appendingParameter(name: "ia", value: "web") ==
            URL(string: "https://duckduckgo.com/?q=Battle%20star+Galactica%25a&ia=web")!
        )
    }

    static let rfc3986QueryReservedChars_args: [(String, String, String, UInt)] = [
        (":", ":", "https://duck.com/?%3A=%3A", #line),
        ("/", "/", "https://duck.com/?%2F=%2F", #line),
        ("?", "?", "https://duck.com/?%3F=%3F", #line),
        ("#", "#", "https://duck.com/?%23=%23", #line),
        ("[", "[", "https://duck.com/?%5B=%5B", #line),
        ("]", "]", "https://duck.com/?%5D=%5D", #line),
        ("@", "@", "https://duck.com/?%40=%40", #line),
        ("!", "!", "https://duck.com/?%21=%21", #line),
        ("$", "$", "https://duck.com/?%24=%24", #line),
        ("&", "&", "https://duck.com/?%26=%26", #line),
        ("'", "'", "https://duck.com/?%27=%27", #line),
        ("(", "(", "https://duck.com/?%28=%28", #line),
        (")", ")", "https://duck.com/?%29=%29", #line),
        ("*", "*", "https://duck.com/?%2A=%2A", #line),
        ("+", "+", "https://duck.com/?%2B=%2B", #line),
        (",", ",", "https://duck.com/?%2C=%2C", #line),
        (";", ";", "https://duck.com/?%3B=%3B", #line),
        ("=", "=", "https://duck.com/?%3D=%3D", #line),
    ]

    @available(iOS 16, macOS 13, *)
    @Test("URL.appendingParameter correctly encodes RFC3986 reserved characters", .timeLimit(.minutes(1)), arguments: rfc3986QueryReservedChars_args)
    func addParameterIsCalled_encodesRFC3986QueryReservedCharactersInTheParameter(name: String, value: String, expected: String, line: UInt) {
        let url = URL(string: "https://duck.com/")!
        #expect(url.appendingParameter(name: name, value: value).absoluteString == expected, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.appendingParameter allows unescaped reserved characters when specified", .timeLimit(.minutes(1)))
    func addParameterIsCalled_allowsUnescapedReservedCharactersAsSpecified() {
        let url = URL(string: "https://duck.com/")!

        #expect(
            url.appendingParameter(
                name: "domains",
                value: "test.com,example.com/test,localhost:8000/api",
                allowedReservedCharacters: .init(charactersIn: ",:")
            ).absoluteString ==
            "https://duck.com/?domains=test.com,example.com%2Ftest,localhost:8000%2Fapi"
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString returns nil for empty input", .timeLimit(.minutes(1)))
    func punycodeUrlIsCalledOnEmptyStringReturnsNil() {
        #expect(URL(trimmedAddressBarString: "")?.absoluteString == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString returns nil for space input", .timeLimit(.minutes(1)))
    func punycodeUrlIsCalledOnQueryReturnsNil() {
        #expect(URL(trimmedAddressBarString: " ")?.absoluteString == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString returns nil for URLs with spaces in the hostname", .timeLimit(.minutes(1)))
    func punycodeUrlIsCalledOnQueryWithSpaceThenUrlIsNotReturned() {
        #expect(URL(trimmedAddressBarString: "https://www.duckduckgo .com/html?q=search")?.absoluteString == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString returns nil for unicode local hostnames", .timeLimit(.minutes(1)))
    func punycodeUrlIsCalledOnLocalHostnameReturnsNil() {
        #expect(URL(trimmedAddressBarString: "💩")?.absoluteString == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString doesn't interpret 'define:' as a local URL", .timeLimit(.minutes(1)))
    func defineSearchRequestIsMadeNotInterpretedAsLocalURL() {
        #expect(URL(trimmedAddressBarString: "define:300/spartans")?.absoluteString == nil)
    }

    static let addressBarURLParsing_args: [(String, String?, String?, UInt)] = [
        ("user@somehost.local:9091/index.html", "http://user@somehost.local:9091/index.html", "http", #line),
        ("something.local:9100", "http://something.local:9100/", "http", #line),
        ("user@localhost:5000", "http://user@localhost:5000/", "http", #line),
        ("user:password@localhost:5000", "http://user:password@localhost:5000/", "http", #line),
        ("localhost", "http://localhost/", "http", #line),
        ("localhost:5000", "http://localhost:5000/", "http", #line),
        ("sms://+44123123123", nil, nil, #line),
        ("mailto:test@example.com", "mailto:test@example.com", "mailto", #line),
        ("mailto:u%24ser@💩.la?arg=b", "mailto:u%24ser@%F0%9F%92%A9.la?arg=b", "mailto", #line), // note: this needs to be fixed in URLPredictorRust to use punycode
        ("http://u%24ser@💩.la?arg=b#1", "http://u%24ser@xn--ls8h.la/?arg=b#1", "http", #line),
        ("62.12.14.111", "http://62.12.14.111/", "http", #line),
        ("https://", nil, nil, #line),
        ("http://duckduckgo.com", "http://duckduckgo.com/", "http", #line),
        ("https://duckduckgo.com", "https://duckduckgo.com/", "https", #line),
        ("https://duckduckgo.com/", "https://duckduckgo.com/", "https", #line),
        ("duckduckgo.com", "http://duckduckgo.com/", "http", #line),
        ("duckduckgo.com/html?q=search", "http://duckduckgo.com/html?q=search", "http", #line),
        ("www.duckduckgo.com", "http://www.duckduckgo.com/", "http", #line),
        ("https://www.duckduckgo.com/html?q=search", "https://www.duckduckgo.com/html?q=search", "https", #line),
        ("https://www.duckduckgo.com/html/?q=search", "https://www.duckduckgo.com/html/?q=search", "https", #line),
        ("ftp://www.duckduckgo.com", nil, nil, #line),
        ("file:///users/user/Documents/afile", "file:///users/user/Documents/afile", "file", #line),
        ("https://www.duckduckgo.com/html?q =search", "https://www.duckduckgo.com/html?q%20=search", "https", #line),
    ]

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString correctly parses various address bar inputs", .timeLimit(.minutes(1)), arguments: addressBarURLParsing_args)
    func addressBarURLParsing(address: String, expectedString: String? = nil, expectedScheme: String? = nil, line: UInt) {
        let url = URL(trimmedAddressBarString: address, useUnifiedLogic: true)
        #expect(url?.scheme == expectedScheme, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
        #expect(url?.absoluteString == expectedString, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString escapes invalid characters in URL parameters", .timeLimit(.minutes(1)))
    func urlParametersModifiedWithInvalidCharactersThenParametersArePercentEscaped() {
        #expect(URL(trimmedAddressBarString: "https://www.duckduckgo.com/html?q=a%20search with+space?+and%25plus&ia=calculator")!.absoluteString ==
                "https://www.duckduckgo.com/html?q=a%20search%20with+space?+and%25plus&ia=calculator")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString preserves empty query markers", .timeLimit(.minutes(1)))
    func urlWithEmptyQueryIsFixedUpQuestionCharIsKept() {
        #expect(URL(trimmedAddressBarString: "https://duckduckgo.com/?")!.absoluteString ==
               "https://duckduckgo.com/?")
        #expect(URL(trimmedAddressBarString: "https://duckduckgo.com?")!.absoluteString ==
               "https://duckduckgo.com?")
        #expect(URL(trimmedAddressBarString: "https:/duckduckgo.com/?")!.absoluteString ==
               "https://duckduckgo.com/?")
        #expect(URL(trimmedAddressBarString: "https:/duckduckgo.com?")!.absoluteString ==
               "https://duckduckgo.com?")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString escapes hash fragments correctly", .timeLimit(.minutes(1)))
    func urlWithHashIsFixedUpHashIsCorrectlyEscaped() {
        #expect(URL(trimmedAddressBarString: "https://duckduckgo.com/#hash with #")!.absoluteString ==
               "https://duckduckgo.com/#hash%20with%20%23")
        #expect(URL(trimmedAddressBarString: "https://duckduckgo.com/html?q=a b#hash with #")!.absoluteString ==
               "https://duckduckgo.com/html?q=a%20b#hash%20with%20%23")
        #expect(URL(trimmedAddressBarString: "https://duckduckgo.com/html#hash with #")!.absoluteString ==
               "https://duckduckgo.com/html#hash%20with%20%23")
        #expect(URL(trimmedAddressBarString: "https://duckduckgo.com/html?q#hash with #")!.absoluteString ==
               "https://duckduckgo.com/html?q#hash%20with%20%23")
        #expect(URL(trimmedAddressBarString: "https://duckduckgo.com/html?#hash with? #")!.absoluteString ==
               "https://duckduckgo.com/html?#hash%20with?%20%23")
        #expect(URL(trimmedAddressBarString: "https://duckduckgo.com/html?q=a b#")!.absoluteString ==
               "https://duckduckgo.com/html?q=a%20b#")
    }

    static let punycodeUrls_args: [(String, String, UInt)] = [
        ("💩.la", "http://xn--ls8h.la", #line),
        ("💩.la/", "http://xn--ls8h.la/", #line),
        ("82.мвд.рф", "http://82.xn--b1aew.xn--p1ai", #line),
        ("http://💩.la:8080", "http://xn--ls8h.la:8080", #line),
        ("http://💩.la", "http://xn--ls8h.la", #line),
        ("https://💩.la", "https://xn--ls8h.la", #line),
        ("https://💩.la/", "https://xn--ls8h.la/", #line),
        ("https://💩.la/path/to/resource", "https://xn--ls8h.la/path/to/resource", #line),
        ("https://💩.la/path/to/resource?query=true", "https://xn--ls8h.la/path/to/resource?query=true", #line),
        ("https://💩.la/💩", "https://xn--ls8h.la/%F0%9F%92%A9", #line),
    ]

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString correctly handles punycode URLs", .timeLimit(.minutes(1)), arguments: punycodeUrls_args)
    func punycodeUrlIsCalledWithEncodedUrlsReturnsCorrectURL(input: String, expected: String, line: UInt) {
        #expect(input.decodedURL?.absoluteString == expected, sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.getParameter returns the correct value when the parameter exists", .timeLimit(.minutes(1)))
    func paramExistsThengetParameterReturnsCorrectValue() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let expected = "secondValue"
        let actual = url.getParameter(named: "secondParam")
        #expect(actual == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.getParameter returns nil when the parameter doesn't exist", .timeLimit(.minutes(1)))
    func paramDoesNotExistThengetParameterIsNil() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let result = url.getParameter(named: "someOtherParam")
        #expect(result == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.removeParameter returns a URL without the specified parameter", .timeLimit(.minutes(1)))
    func paramExistsThenRemovingReturnUrlWithoutParam() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let expected = URL(string: "http://test.com?secondParam=secondValue")!
        let actual = url.removeParameter(name: "firstParam")
        #expect(actual == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.removeParameter returns the same URL when the parameter doesn't exist", .timeLimit(.minutes(1)))
    func paramDoesNotExistThenRemovingReturnsSameUrl() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let actual = url.removeParameter(name: "someOtherParam")
        #expect(actual == url)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.removeParameter preserves plus signs in remaining parameters", .timeLimit(.minutes(1)))
    func removingAParamThenRemainingUrlWebPlusesAreEncodedToEnsureTheyAreMaintainedAsSpaces() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=45+%2B+5")!
        let expected = URL(string: "http://test.com?secondParam=45+%2B+5")!
        let actual = url.removeParameter(name: "firstParam")
        #expect(actual == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.removingParameters returns a URL without the specified parameters", .timeLimit(.minutes(1)))
    func removingParamsThenRemovingReturnsUrlWithoutParams() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue&thirdParam=thirdValue")!
        let expected = URL(string: "http://test.com?secondParam=secondValue")!
        let actual = url.removingParameters(named: ["firstParam", "thirdParam"])
        #expect(actual == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.removingParameters returns the same URL when no parameters match", .timeLimit(.minutes(1)))
    func paramsDoNotExistThenRemovingReturnsSameUrl() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let actual = url.removingParameters(named: ["someParam", "someOtherParam"])
        #expect(actual == url)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.removingParameters returns the same URL when given an empty array", .timeLimit(.minutes(1)))
    func emptyParamArrayIsUsedThenRemovingReturnsSameUrl() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=secondValue")!
        let actual = url.removingParameters(named: [])
        #expect(actual == url)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.removingParameters preserves plus signs in remaining parameters", .timeLimit(.minutes(1)))
    func removingParamsThenRemainingUrlWebPlusesAreEncodedToEnsureTheyAreMaintainedAsSpaces() {
        let url = URL(string: "http://test.com?firstParam=firstValue&secondParam=45+%2B+5")!
        let expected = URL(string: "http://test.com?secondParam=45+%2B+5")!
        let actual = url.removingParameters(named: ["firstParam"])
        #expect(actual == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.appendingParameter adds a query string when there are no parameters", .timeLimit(.minutes(1)))
    func noParamsThenAddingAppendsQuery() throws {
        let url = URL(string: "http://test.com")!
        let expected = URL(string: "http://test.com?aParam=aValue")!
        let actual = url.appendingParameter(name: "aParam", value: "aValue")
        #expect(actual == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.appendingParameter appends to existing query parameters", .timeLimit(.minutes(1)))
    func paramDoesNotExistThenAddingParamAppendsItToExistingQuery() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue")!
        let expected = URL(string: "http://test.com?firstParam=firstValue&anotherParam=anotherValue")!
        let actual = url.appendingParameter(name: "anotherParam", value: "anotherValue")
        #expect(actual == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.appendingParameter encodes parameters with invalid characters", .timeLimit(.minutes(1)))
    func paramHasInvalidCharactersThenAddingParamAppendsEncodedVersion() throws {
        let url = URL(string: "http://test.com")!
        let expected = URL(string: "http://test.com?aParam=43%20%2B%205")!
        let actual = url.appendingParameter(name: "aParam", value: "43 + 5")
        #expect(actual == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.appendingParameter adds a new value for an existing parameter", .timeLimit(.minutes(1)))
    func paramExistsThenAddingNewValueAppendsParam() throws {
        let url = URL(string: "http://test.com?firstParam=firstValue")!
        let expected = URL(string: "http://test.com?firstParam=firstValue&firstParam=newValue")!
        let actual = url.appendingParameter(name: "firstParam", value: "newValue")
        #expect(actual == expected)
    }

    static let matches_comparator_args: [(String, String, Bool, UInt)] = [
        ("youtube.com", "http://youtube.com", true, #line),
        ("youtube.com/", "http://youtube.com", true, #line),
        ("youtube.com", "http://youtube.com/", true, #line),
        ("youtube.com/", "http://youtube.com/", true, #line),
        ("http://youtube.com/", "youtube.com", true, #line),
        ("http://youtube.com", "youtube.com/", true, #line),
        ("https://youtube.com/", "https://youtube.com", true, #line),
        ("https://youtube.com/#link#1", "https://youtube.com#link#1", true, #line),
        ("https://youtube.com/#link#1", "https://youtube.com#link#1", true, #line),
        ("https://youtube.com/#link#1", "https://youtube.com/#link#1", true, #line),
        ("https://youtube.com#link#1", "https://youtube.com/#link#1", true, #line),

        ("youtube.com", "https://youtube.com", false, #line),
        ("youtube.com/", "https://youtube.com", false, #line),
        ("youtube.com/#link#1", "https://youtube.com#link#2", false, #line),
        ("youtube.com/#link#1", "https://youtube.com#link", false, #line),
    ]

    @available(iOS 16, macOS 13, *)
    @Test("URL.matches correctly compares URLs", .timeLimit(.minutes(1)), arguments: matches_comparator_args)
    func matchesComparator(url1: String, url2: String, expected: Bool, line: UInt) {
        if expected {
            #expect(url1.url!.equals(url2.url!, by: .fuzzyIdentity), sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
        } else {
            #expect(!url1.url!.equals(url2.url!, by: .fuzzyIdentity), sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
        }
    }

    static let matches_protection_space_args: [(String, String, Int, String, Bool, UInt)] = [
        ("youtube.com", "youtube.com", 80, "http", true, #line),
        ("http://youtube.com", "youtube.com", 80, "http", true, #line),
        ("https://youtube.com:123", "youtube.com", 123, "https", true, #line),

        ("https://youtube.com:123", "youtube.com", 1234, "https", false, #line),
        ("https://youtube.com:123", "youtube.com", 123, "http", false, #line),
        ("https://www.youtube.com:123", "youtube.com", 123, "https", false, #line),
    ]

    @available(iOS 16, macOS 13, *)
    @Test("URL.matches correctly matches against protection spaces", .timeLimit(.minutes(1)), arguments: matches_protection_space_args)
    func matchesProtectionSpace(url: String, host: String, port: Int, scheme: String, expected: Bool, line: UInt) {
        let protectionSpace = URLProtectionSpace(host: host, port: port, protocol: scheme, realm: "realm", authenticationMethod: "basic")
        if expected {
            #expect(url.url!.matches(protectionSpace), sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
        } else {
            #expect(!url.url!.matches(protectionSpace), sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.getQueryItem returns the correct query item when it exists", .timeLimit(.minutes(1)))
    func queryItemWithNameAndURLHasQueryItemReturnsQueryItem() throws {
        // GIVEN
        let url = try #require(URL(string: "www.duckduckgo.com?origin=test"))

        // WHEN
        let result = url.getQueryItem(named: "origin")

        // THEN
        let queryItem = try #require(result)
        #expect(queryItem.name == "origin")
        #expect(queryItem.value == "test")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.getQueryItem returns nil when the query item doesn't exist", .timeLimit(.minutes(1)))
    func queryItemWithNameAndURLDoesNotHaveQueryItemReturnsNil() throws {
        // GIVEN
        let url = try #require(URL(string: "www.duckduckgo.com"))

        // WHEN
        let result = url.getQueryItem(named: "test")

        // THEN
        #expect(result == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.appending(percentEncodedQueryItem:) correctly adds a query item", .timeLimit(.minutes(1)))
    func appendingQueryItemReturnsURLWithQueryItem() throws {
        // GIVEN
        let url = try #require(URL(string: "www.duckduckgo.com"))

        // WHEN
        let result = url.appending(percentEncodedQueryItem: .init(name: "origin", value: "test"))

        // THEN
        #expect(result.absoluteString == "www.duckduckgo.com?origin=test")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.appending(percentEncodedQueryItems:) correctly adds multiple query items", .timeLimit(.minutes(1)))
    func appendingQueryItemsReturnsURLWithQueryItems() throws {
        // GIVEN
        let queryItems = [URLQueryItem(name: "origin", value: "test"), URLQueryItem(name: "another_item", value: "test_2")]
        let url = try #require(URL(string: "www.duckduckgo.com"))

        // WHEN
        let result = url.appending(percentEncodedQueryItems: queryItems)

        // THEN
        #expect(result.absoluteString == "www.duckduckgo.com?origin=test&another_item=test_2")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.getQueryItems returns all query items for a URL", .timeLimit(.minutes(1)))
    func getQueryItemsReturnsQueryItemsForURL() throws {
        // GIVEN
        let url = try #require(URL(string: "www.duckduckgo.com?origin=test&another_item=test_2"))

        // WHEN
        let result = try #require(url.getQueryItems())

        // THEN
        #expect(result.first == .init(name: "origin", value: "test"))
        #expect(result.last == .init(name: "another_item", value: "test_2"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.trimmedAddressBarString handles user and password information correctly", .timeLimit(.minutes(1)))
    func userInfoDoesNotContaintPassword_NavigateToSearch() {
        #expect(URL(trimmedAddressBarString: "user@domain.com") == nil)

        let url1 = URL(trimmedAddressBarString: "user: @domain.com")
        #expect(url1?.host == "domain.com")
        #expect(url1?.user(percentEncoded: false) == "user")
        #expect(url1?.password(percentEncoded: false) == " ")

        let url2 = URL(trimmedAddressBarString: "user:,,@domain.com")
        #expect(url2?.host == "domain.com")
        #expect(url2?.user(percentEncoded: false) == "user")
        #expect(url2?.password(percentEncoded: false) == ",,")

        let url3 = URL(trimmedAddressBarString: "user:pass@domain.com")
        #expect(url3?.host == "domain.com")
        #expect(url3?.user(percentEncoded: false) == "user")
        #expect(url3?.password(percentEncoded: false) == "pass")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL handles spaces in path, query, and fragment components", .timeLimit(.minutes(1)))
    func normalizingURLsWithSpacesInDifferentComponents() throws {
        // Path with spaces
        let urlWithSpacesInPath = URL(string: "https://example.com/path with spaces/file.html")
        #expect(urlWithSpacesInPath?.absoluteString == "https://example.com/path%20with%20spaces/file.html")

        // Query with spaces
        let urlWithSpacesInQuery = URL(string: "https://example.com/search?q=test query&page=1")
        #expect(urlWithSpacesInQuery?.absoluteString == "https://example.com/search?q=test%20query&page=1")

        // Fragment with spaces
        let urlWithSpacesInFragment = URL(string: "https://example.com/page#section with spaces")
        #expect(urlWithSpacesInFragment?.absoluteString == "https://example.com/page#section%20with%20spaces")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL correctly handles international characters", .timeLimit(.minutes(1)))
    func internationalCharactersInURLComponents() throws {
        // Test with international characters in path
        let urlWithInternationalPath = URL(string: "https://example.com/пример/测试")
        #expect(urlWithInternationalPath?.absoluteString == "https://example.com/%D0%BF%D1%80%D0%B8%D0%BC%D0%B5%D1%80/%E6%B5%8B%E8%AF%95")

        // Test with international characters in query
        let urlWithInternationalQuery = URL(string: "https://example.com/search?q=こんにちは")
        #expect(urlWithInternationalQuery?.absoluteString == "https://example.com/search?q=%E3%81%93%E3%82%93%E3%81%AB%E3%81%A1%E3%81%AF")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL correctly handles spaces specifically in auth, path, and query parameters", .timeLimit(.minutes(1)))
    func spacesInAuthPathAndQueryParameters() throws {
        // URL with spaces in auth
        let urlWithSpacesInAuth = URL(string: "https://user name:pass word@example.com")
        #expect(urlWithSpacesInAuth?.absoluteString == "https://user%20name:pass%20word@example.com")

        // URL with spaces in path
        let urlWithSpacesInPath = URL(string: "https://example.com/path with/spaces here")
        #expect(urlWithSpacesInPath?.absoluteString == "https://example.com/path%20with/spaces%20here")

        // URL with spaces in query parameters
        let urlWithSpacesInQueryParams = URL(string: "https://example.com/search?query=hello world&category=books and magazines")
        #expect(urlWithSpacesInQueryParams?.absoluteString == "https://example.com/search?query=hello%20world&category=books%20and%20magazines")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL maintains plus signs in query parameters", .timeLimit(.minutes(1)))
    func plusSignsInQueryParametersArePreserved() throws {
        let url = URL(string: "https://example.com/search?q=c++programming&lang=c++")?
            .appendingParameter(name: "rating", value: "4+")

        #expect(url?.absoluteString == "https://example.com/search?q=c++programming&lang=c++&rating=4%2B")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL handles email addresses in mailto: URLs correctly", .timeLimit(.minutes(1)))
    func emailAddressesInMailtoURLs() throws {
        let url = URL(string: "mailto:test@example.com,user@domain.com")
        #expect(url?.absoluteString == "mailto:test@example.com,user@domain.com")

        let emailAddresses = url?.emailAddresses
        #expect(emailAddresses?.count == 2)
        #expect(emailAddresses?[0] == "test@example.com")
        #expect(emailAddresses?[1] == "user@domain.com")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.removingTextFragment removes text fragment if it exists", .timeLimit(.minutes(1)), arguments: [
        ("example.com#:~:text=abcd%20", "example.com"),
        ("https://youtube.com/watch?v=12345#:~:text=ab%20cd", "https://youtube.com/watch?v=12345"),
        ("https://example.com/#:~:", "https://example.com/"),
        ("https://example.com/#:~:foo", "https://example.com/"),
        ("https://example.com/#anchor", "https://example.com/#anchor"),
        ("https://example.com/#", "https://example.com/#")
    ])
    func removingTextFragment(source: String, processed: String) throws {
        #expect(source.url!.removingTextFragment() == processed.url)
    }

}

extension String {
    var url: URL? {
        return URL(trimmedAddressBarString: self)
    }
    var decodedURL: URL? {
        URL(trimmedAddressBarString: self)
    }
}

extension URL {
    func removeParameter(name: String) -> URL {
        return self.removingParameters(named: [name])
    }

    var emailAddresses: [String]? {
        guard scheme == "mailto" else { return nil }

        // Extract email part after mailto:
        let emailsString = absoluteString.replacingOccurrences(of: "mailto:", with: "")

        // Split by comma and filter out empty strings
        return emailsString.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - URL.equals(_:by:) tests

final class URLEqualityComponentsTests {

    // MARK: .sameDocument
    static let sameDocument_args: [(String, String, Bool, UInt)] = [
        // Same URL, no fragment → equal
        ("http://example.com/page",      "http://example.com/page",       true,  #line),
        // Same URL, different fragments → still same document
        ("http://example.com/page#a",    "http://example.com/page#b",     true,  #line),
        ("http://example.com/page#a",    "http://example.com/page",       true,  #line),
        ("http://example.com/page",      "http://example.com/page#b",     true,  #line),
        // Foundation normalises path trailing slash, so /page/ and /page compare equal
        ("http://example.com/page/",     "http://example.com/page",       true,  #line),
        // Different paths → not same document
        ("http://example.com/page",      "http://example.com/other",      false, #line),
        ("http://example.com/path",      "http://example.com/",           false, #line),
        // Same path, different query → not same document
        ("http://example.com/page?q=1",  "http://example.com/page?q=2",  false, #line),
        ("http://example.com/page?q=1",  "http://example.com/page",       false, #line),
        // query+fragment combo: query difference dominates
        ("http://example.com/page?q#a",  "http://example.com/page",       false, #line),
        ("http://example.com/page?q#a",  "http://example.com/page#a",     false, #line),
        // Different scheme → not same document
        ("http://example.com/page",      "https://example.com/page",      false, #line),
        // Different host → not same document
        ("http://example.com/page",      "http://other.com/page",         false, #line),
        ("http://example.com/#hash",     "file://example.com",            false, #line),
        ("http://example.com",           "file://example.com",            false, #line),
        // Different port → not same document
        ("http://example.com:8080/page", "http://example.com:9090/page",  false, #line),
        ("http://example.com:81/",       "http://example.com/",           false, #line),
        // Non-default explicit port: same port ± fragment → same document
        ("http://example.com:81/#hash",  "http://example.com:81/",        true,  #line),
        ("http://example.com:81/p#hash", "http://example.com:81/p",       true,  #line),
        // Foundation's URL.port does NOT normalise default ports, so explicit :80
        // and no-port are treated as different even though they resolve to the same server.
        ("http://example.com:80/page",   "http://example.com/page",       false, #line),
        // about:blank — same document regardless of fragment
        ("about:blank",                  "about:blank",                   true,  #line),
        ("about:blank#section",          "about:blank",                   true,  #line),
        ("about:blank#section",          "about:blank#other",             true,  #line),
        // about:blank with percent-encoded fragment (%23): Foundation treats it as part
        // of the path, so effectivePath strips it — both sides are "blank" → same document.
        ("about:blank",                  "about:blank%23section",         true,  #line),
        ("about:blank%23foo",            "about:blank%23bar",             true,  #line),
        // about: with query — query is part of the document identity
        ("about:blank?lang=en",          "about:blank?lang=en",           true,  #line),
        ("about:blank?lang=en",          "about:blank?lang=fr",           false, #line),
        // about: with both query and fragment — fragment ignored, query compared
        ("about:blank?lang=en#sec",      "about:blank?lang=en",           true,  #line),
        ("about:blank?lang=en#sec",      "about:blank?lang=fr#sec",       false, #line),
        // file:// URLs
        ("file:///path/to/file.html",    "file:///path/to/file.html",     true,  #line),
        ("file:///path/to/file.html#a",  "file:///path/to/file.html",     true,  #line),
        ("file:///path/to/file.html?q",  "file:///path/to/file.html",     false, #line),
        ("file:///path/to/file.html?q#a","file:///path/to/file.html",     false, #line),
        ("file:///path/to/other.html",   "file:///path/to/file.html",     false, #line),
        ("file:///path/sub/file.html",   "file:///path/to/file.html",     false, #line),
        // data: URLs — identical path → same document; different path → not same document
        ("data:text/plain,hello",        "data:text/plain,hello",         true,  #line),
        ("data:text/plain,hello",        "data:text/plain,world",         false, #line),
        // data: with fragment — fragment ignored for sameDocument
        ("data:text/plain,hello#anchor", "data:text/plain,hello",         true,  #line),
        ("data:text/plain,hello#anchor", "data:text/plain,hello#other",   true,  #line),
        // data: with query — query is part of document identity
        ("data:text/plain,hello?x=1",    "data:text/plain,hello?x=1",     true,  #line),
        ("data:text/plain,hello?x=1",    "data:text/plain,hello?x=2",     false, #line),
    ]

    @available(iOS 16, macOS 13, *)
    @Test("URL.equals(by:.sameDocument) — fragment-blind equality", .timeLimit(.minutes(1)),
          arguments: sameDocument_args)
    func equalsSameDocument(url1: String, url2: String, expected: Bool, line: UInt) {
        let loc = Testing.SourceLocation(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1)
        #expect(url1.url!.equals(url2.url!, by: .sameDocument) == expected, sourceLocation: loc)
    }

    // MARK: .fuzzyIdentity — mirrors matches(_: URL) semantics

    static let fuzzyIdentity_args: [(String, String, Bool, UInt)] = [
        // Trailing slash normalisation
        ("http://youtube.com/",          "http://youtube.com",            true,  #line),
        ("http://youtube.com",           "http://youtube.com/",           true,  #line),
        ("https://youtube.com/",         "https://youtube.com",           true,  #line),
        // Same fragment both sides → equal
        ("https://youtube.com/#link#1",  "https://youtube.com#link#1",   true,  #line),
        ("https://youtube.com/#link#1",  "https://youtube.com/#link#1",  true,  #line),
        ("https://youtube.com#link#1",   "https://youtube.com/#link#1",  true,  #line),
        // Different fragments → not equal
        ("youtube.com/#link#1",          "https://youtube.com#link#2",   false, #line),
        ("youtube.com/#link#1",          "https://youtube.com#link",     false, #line),
        // Scheme mismatch
        ("youtube.com",                  "https://youtube.com",          false, #line),
        // Different paths
        ("http://example.com/a",         "http://example.com/b",         false, #line),
        // Opaque URLs — fragment-sensitive (fuzzyIdentity includes fragment)
        ("about:blank#section",          "about:blank#section",          true,  #line),
        ("about:blank#section",          "about:blank#other",            false, #line),
        ("about:blank#section",          "about:blank",                  false, #line),
        // Opaque URLs with query — query is compared
        ("about:blank?lang=en",          "about:blank?lang=en",          true,  #line),
        ("about:blank?lang=en",          "about:blank?lang=fr",          false, #line),
        // data: with fragment
        ("data:text/plain,hello#sec",    "data:text/plain,hello#sec",    true,  #line),
        ("data:text/plain,hello#sec",    "data:text/plain,hello#other",  false, #line),
    ]

    @available(iOS 16, macOS 13, *)
    @Test("URL.equals(by:.fuzzyIdentity) — trailing-slash normalised, fragment-sensitive",
          .timeLimit(.minutes(1)), arguments: fuzzyIdentity_args)
    func equalsFuzzyIdentity(url1: String, url2: String, expected: Bool, line: UInt) {
        let loc = Testing.SourceLocation(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1)
        #expect(url1.url!.equals(url2.url!, by: .fuzzyIdentity) == expected, sourceLocation: loc)
    }

    // MARK: Custom component combinations

    @available(iOS 16, macOS 13, *)
    @Test("URL.equals(by:) — host only ignores everything else", .timeLimit(.minutes(1)))
    func equalsHostOnly() {
        let a = URL(string: "https://example.com:443/path?q=1#frag")!
        let b = URL(string: "http://example.com:80/other?q=2#other")!
        #expect(a.equals(b, by: [.host]))
        #expect(!a.equals(URL(string: "https://other.com/path")!, by: [.host]))
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.equals(by:) — scheme+host without port", .timeLimit(.minutes(1)))
    func equalsSchemeAndHostIgnoresPort() {
        let a = URL(string: "https://example.com:8080/")!
        let b = URL(string: "https://example.com:9090/")!
        #expect(a.equals(b, by: [.scheme, .host]))
        #expect(!a.equals(URL(string: "http://example.com:8080/")!, by: [.scheme, .host]))
    }

    // MARK: about: URLs — effectiveFragment and effectivePath

    @available(iOS 16, macOS 13, *)
    @Test("URL.equals — about:blank with %23 fragment is same document as about:blank", .timeLimit(.minutes(1)))
    func aboutBlankPercentEncodedFragmentIsSameDocument() {
        let blank   = URL(string: "about:blank")!
        let hashed  = URL(string: "about:blank%23section")!
        let hashed2 = URL(string: "about:blank%23other")!
        #expect(blank.equals(hashed,  by: .sameDocument))
        #expect(blank.equals(hashed2, by: .sameDocument))
        #expect(hashed.equals(hashed2, by: .sameDocument))
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.equals — about:blank with %23 differs in fragment under .fuzzyIdentity", .timeLimit(.minutes(1)))
    func aboutBlankPercentEncodedFragmentDiffersUnderFuzzyIdentity() {
        let hashed  = URL(string: "about:blank%23section")!
        let hashed2 = URL(string: "about:blank%23other")!
        // different %23 suffixes → different effective fragments → not equal
        #expect(!hashed.equals(hashed2, by: .fuzzyIdentity))
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.equals — about:blank with real #fragment vs %23 fragment", .timeLimit(.minutes(1)))
    func aboutBlankRealHashVsPercentEncodedSameDocument() {
        let real    = URL(string: "about:blank#section")!
        let encoded = URL(string: "about:blank%23section")!
        // Both should be same document as plain about:blank
        let blank = URL(string: "about:blank")!
        #expect(blank.equals(real,    by: .sameDocument))
        #expect(blank.equals(encoded, by: .sameDocument))
    }

    // MARK: NSURL vs URL path consistency (WebKit uses NSURL internally)
    //
    // Foundation's URL.path returns inconsistent values for opaque about: URLs depending on
    // whether the URL was created via Swift URL(string:) or ObjC NSURL(string:):
    //   URL(string:  "about:blank")!.path  → "blank"
    //   NSURL(string:"about:blank")!.path  → ""  ← WebKit's representation
    //
    // This is the raw Foundation bug that the effectivePath fix targets.
    // data: URLs do NOT share this inconsistency — NSURL and URL agree on their path.

    /// Confirm the raw Foundation inconsistency exists.
    /// This test always passes; it documents the underlying behaviour our fix depends on.
    @available(iOS 16, macOS 13, *)
    @Test("Foundation: NSURL.path returns \"\" for opaque URLs; URL(string:).path returns content",
          .timeLimit(.minutes(1)))
    func foundationNSURLPathInconsistencyForOpaqueURLs() {
        // about:blank
        let swiftAbout = URL(string: "about:blank")!
        let objcAbout  = NSURL(string: "about:blank")! as URL
        #expect(swiftAbout.path == "blank", "URL(string:) should return \"blank\" for about:blank path")
        #expect(objcAbout.path  == "",      "NSURL(string:) should return \"\" for about:blank path")
        #expect(swiftAbout.absoluteString == objcAbout.absoluteString)

        // data: — same inconsistency
        let swiftData = URL(string: "data:text/plain,hello")!
        let objcData  = NSURL(string: "data:text/plain,hello")! as URL
        #expect(swiftData.path == "text/plain,hello", "URL(string:) returns the data payload as path")
        #expect(objcData.path  == "",                 "NSURL(string:) returns \"\" for data: URL path too")
        #expect(swiftData.absoluteString == objcData.absoluteString)
    }

    /// Documents how NSURL handles opaque URLs with fragment/query.
    @available(iOS 16, macOS 13, *)
    @Test("Foundation: NSURL opaque URL fragment/query/absoluteString diagnostics", .timeLimit(.minutes(1)))
    func foundationNSURLOpaqueComponentsDiagnostics() {
        let cases = [
            "about:blank#section",
            "about:blank?lang=en",
            "about:blank?lang=en#sec",
            "data:text/plain,hello#anchor",
            "data:text/plain,hello?x=1",
        ]
        for str in cases {
            guard let nsurl = NSURL(string: str) else {
                Issue.record("NSURL(string: \(str)) returned nil — unexpected")
                continue
            }
            print("\(nsurl.absoluteString! as NSString) address: \(Unmanaged.passUnretained(nsurl.absoluteString! as NSString).toOpaque())")
            print("\(nsurl.absoluteString! as NSString) address: \(Unmanaged.passUnretained(nsurl.absoluteString! as NSString).toOpaque())")

            let url = nsurl as URL
            let uc = NSURLComponents(url: nsurl as URL, resolvingAgainstBaseURL: false)
            print("""
                [diagnostic] \(str):
                  absoluteString=\(url.absoluteString)
                  path=\(url.path.debugDescription)  fragment=\(url.fragment.debugDescription)  query=\(url.query.debugDescription)
                  URLComponents(string:)=\(uc == nil ? "nil" : "ok")
                    .path=\(uc?.percentEncodedPath.debugDescription ?? "n/a")
                    .query=\(uc?.percentEncodedQuery.debugDescription ?? "n/a")
                    .fragment=\(uc?.percentEncodedFragment.debugDescription ?? "n/a")
                """)
            continue
        }
    }

    // Reuse sameDocument_args and fuzzyIdentity_args with lhs constructed via NSURL(string:).
    // Entries where NSURL returns nil (e.g. scheme-less strings) are skipped.

    @available(iOS 16, macOS 13, *)
    @Test("URL.equals(by:.sameDocument) — NSURL-created lhs gives same result as URL(string:)",
          .timeLimit(.minutes(1)), arguments: sameDocument_args)
    func equalsSameDocumentNSURLvsURL(url1: String, url2: String, expected: Bool, line: UInt) {
        guard let lhsURL = NSURL(string: url1) as URL?, let rhsURL = URL(string: url2) else { return }
        let loc = Testing.SourceLocation(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1)
        let actual = lhsURL.equals(rhsURL, by: .sameDocument)
        #expect(actual == expected,
                "NSURL(\(url1)).equals(\(url2), by:.sameDocument) → \(actual), expected \(expected)",
                sourceLocation: loc)
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.equals(by:.fuzzyIdentity) — NSURL-created lhs gives same result as URL(string:)",
          .timeLimit(.minutes(1)), arguments: fuzzyIdentity_args)
    func equalsFuzzyIdentityNSURLvsURL(url1: String, url2: String, expected: Bool, line: UInt) {
        guard let lhsURL = NSURL(string: url1) as URL?, let rhsURL = URL(string: url2) else { return }
        let loc = Testing.SourceLocation(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1)
        let actual = lhsURL.equals(rhsURL, by: .fuzzyIdentity)
        #expect(actual == expected,
                "NSURL(\(url1)).equals(\(url2), by:.fuzzyIdentity) → \(actual), expected \(expected)",
                sourceLocation: loc)
    }

    // MARK: data: URL performance — equals must not O(n)-scan a 20 MB payload

    @available(iOS 16, macOS 13, *)
    @Test("URL.equals(by:.sameDocument) is near-instant on a 20 MB data: URI (URL)", .timeLimit(.minutes(1)))
    func equalsSameDocumentIsFastForLargeDataURL() {
        let payload = String(repeating: "A", count: 20 * 1024 * 1024)
        guard let url1 = URL(string: "data:text/html," + payload),
              let url2 = URL(string: "data:text/html," + payload + "#anchor") else {
            Issue.record("Failed to construct 20 MB data: URLs")
            return
        }
        let start = Date()
        let result = url1.equals(url2, by: .sameDocument)
        let elapsed = Date().timeIntervalSince(start)

        _ = result
        #expect(elapsed < 0.1,
                "equals(by:.sameDocument) took \(elapsed)s on a 20 MB data: URI — component access must be O(1)")
    }

    @available(iOS 16, macOS 13, *)
    @Test("URL.equals(by:.sameDocument) is near-instant on a 20 MB data: URI (NSURL-bridged)", .timeLimit(.minutes(1)))
    func equalsSameDocumentIsFastForLargeDataURLFromNSURL() {
        let payload = String(repeating: "A", count: 20 * 1024 * 1024)
        // NSURL returns "" for path and nil for fragment/query of opaque URLs.
        guard let nsurl1 = NSURL(string: "data:text/html," + payload),
              let nsurl2 = NSURL(string: "data:text/html," + payload + "#anchor") else {
            Issue.record("Failed to construct 20 MB NSURL data: URLs")
            return
        }
        let url1 = nsurl1 as URL
        let url2 = nsurl2 as URL
        let start = Date()
        let result = url1.equals(url2, by: .sameDocument)
        let elapsed = Date().timeIntervalSince(start)

        _ = result
        print("equals(by:.sameDocument) 20 MB NSURL data: comparison took \(String(format: "%.3f", elapsed))s")
        #expect(elapsed < 0.1,
                "equals(by:.sameDocument) took \(elapsed)s on a 20 MB NSURL data: URI — path body must not be scanned")
    }

    @available(iOS 16, macOS 13, *)
    @Test("TEMP: opaque 20 MB NSURL component access timings", .timeLimit(.minutes(2)))
    func tempOpaqueNSURLComponentTimings() {
        var sink: Any?
        func printDescription(_ value: Any) {
            if let fullString = String(describing: value) as String? {
                let prefixLimit = 200
                let suffixLimit = 40
                if fullString.count > prefixLimit + suffixLimit {
                    let prefix = fullString.prefix(prefixLimit)
                    let suffix = fullString.suffix(suffixLimit)
                    let s = "\(prefix)…\(suffix)"
                    print(s)
                } else {
                    print(fullString)
                }
            } else {
                print(String(describing: sink))
            }
        }
        func measure<T>(_ label: String, _ block: () -> T) -> T {
            let t = Date()
            sink = nil
            let result = block()
            let elapsed = Date().timeIntervalSince(t)
            print(String(format: "%-55@ %.4fs", label as NSString, elapsed))
            if let sink, !(sink is URL || sink is NSURL) {
                printDescription(sink)
            }
            return result
        }

        let raw = measure("build 20 MB random-ASCII payload") {
            let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
            let count = 20 * 1024 * 1024
            var payload = ""
            payload.reserveCapacity(count)
            for _ in 0..<count {
                payload.append(chars.randomElement()!)
            }
            return "data:text/html," + payload + /*"?key=value" + */"#anchor"
        }

        let nsurl = measure("NSURL(string: raw)") { NSURL(string: raw)! }
        let url = measure("NSURL to URL") { nsurl as URL }
        var data = nsurl.absoluteString!.data(using: .utf8)!
        typealias CFURLCreateAbsoluteURLWithBytesFn = @convention(c) (CFAllocator?,
                                                                       UnsafeRawPointer?,
                                                                       CFIndex,
                                                                       CFStringEncoding,
                                                                       CFURL?,
                                                                       Bool) -> CFURL?
        let cfURLCreateAbsoluteURLWithBytes = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                                                  "CFURLCreateAbsoluteURLWithBytes"),
                                                            to: CFURLCreateAbsoluteURLWithBytesFn.self)
        let cfurl = data.withUnsafeBytes { bytes in
            cfURLCreateAbsoluteURLWithBytes(nil,
                                            bytes.baseAddress,
                                            data.count,
                                            CFStringBuiltInEncodings.UTF8.rawValue,
                                            nil, true)
        }

        var fragmentRange = CFRangeMake(0, nsurl.absoluteString!.utf16.count)
        CFURLGetByteRangeForComponent(cfurl, .fragment, &fragmentRange)
        print(fragmentRange)

        let result = data.withUnsafeMutableBytes { bytes in
            CFURLGetBytes(cfurl, bytes.baseAddress, bytes.count)
        }
        let str = String(data: data, encoding: .utf8)
        print(result)
        printDescription(str)

        measure("NSURL.absoluteString") {
            sink = nsurl.absoluteString
        }
        measure("URL.absoluteString") {
            sink = url.absoluteString
        }
        measure("NSURL.path") {
            sink = nsurl.path ?? "<nil>"
        }
        measure("NSURL.query") {
            sink = nsurl.query ?? "<nil>"
        }
        measure("NSURL.fragment") {
            sink = nsurl.fragment ?? "<nil>"
        }
        measure("URL.path") {
            sink = "\"" + url.path + "\""
        }
        measure("URL.query") {
            sink = url.query ?? "<nil>"
        }
        measure("URL.fragment") {
            sink = url.fragment ?? "<nil>"
        }
        measure("URLComponents(string: absoluteString)") {
            sink = URLComponents(string: nsurl.absoluteString ?? "")
        }
        measure("URLComponents(string:).path") {
            sink = URLComponents(string: nsurl.absoluteString ?? "")?.path
        }
        measure("URLComponents(string:).query") {
            sink = URLComponents(string: nsurl.absoluteString ?? "")?.query
        }
        measure("URLComponents(string:).fragment") {
            sink = URLComponents(string: nsurl.absoluteString ?? "")?.fragment
        }
        measure("URLComponents(url: url, resolvingAgainstBaseURL: false)") {
            sink = URLComponents(url: url, resolvingAgainstBaseURL: false)
        }
        measure("URLComponents(url:).path") {
            sink = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path
        }
        measure("URLComponents(url:).query") {
            sink = URLComponents(url: url, resolvingAgainstBaseURL: false)?.query
        }
        measure("URLComponents(url:).fragment") {
            sink = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment
        }
        measure("NSURLComponents(url: nsurl, resolvingAgainstBaseURL: false)") {
            sink = NSURLComponents(url: nsurl as URL, resolvingAgainstBaseURL: false)
        }
        measure("NSURLComponents(url:).path") {
            sink = NSURLComponents(url: nsurl as URL, resolvingAgainstBaseURL: false)?.path
        }
        measure("NSURLComponents(url:).query") {
            sink = NSURLComponents(url: nsurl as URL, resolvingAgainstBaseURL: false)?.query
        }
        measure("NSURLComponents(url:).fragment") {
            sink = NSURLComponents(url: nsurl as URL, resolvingAgainstBaseURL: false)?.fragment
        }
        measure("NSURLComponents(string: absoluteString)") {
            sink = NSURLComponents(string: nsurl.absoluteString ?? "")
        }
        measure("NSURLComponents(string:).path") {
            sink = NSURLComponents(string: nsurl.absoluteString ?? "")?.path
        }
        measure("NSURLComponents(string:).query") {
            sink = NSURLComponents(string: nsurl.absoluteString ?? "")?.query
        }
        measure("NSURLComponents(string:).fragment") {
            sink = NSURLComponents(string: nsurl.absoluteString ?? "")?.fragment
        }
        measure("NSString.range(of: \"#\")") {
            let ns = url.absoluteString as NSString
            sink = ns.range(of: "#")
        }
        measure("String.firstIndex(of: \"#\")") {
            sink = url.absoluteString.firstIndex(of: "#")
        }
        _ = sink
    }
}
    // MARK: - shortDescription

    @Test("shortDescription — short URL returned as-is")
    func testShortDescriptionReturnedAsIsForShortURL() {
        let url = URL(string: "https://example.com/path?q=1#frag")!
        #expect(url.shortDescription == url.absoluteString)
    }

    @Test("shortDescription — long URL is truncated to 1024 characters")
    func testShortDescriptionTruncatesLongURL() {
        let longPath = String(repeating: "a", count: 2000)
        let url = URL(string: "https://example.com/" + longPath)!
        #expect(url.shortDescription.count == 1024)
    }

    @Test("shortDescription — truncated URL contains ellipsis")
    func testShortDescriptionContainsEllipsisWhenTruncated() {
        let longPath = String(repeating: "a", count: 2000)
        let url = URL(string: "https://example.com/" + longPath)!
        #expect(url.shortDescription.contains("…"))
    }

    @Test("shortDescription — truncated URL preserves scheme prefix")
    func testShortDescriptionPreservesSchemePrefix() {
        let longPath = String(repeating: "a", count: 2000)
        let url = URL(string: "https://example.com/" + longPath)!
        #expect(url.shortDescription.hasPrefix("https://"))
    }

// swiftlint:enable comma
