//
//  CrashReportReaderTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import XCTest
@testable import CrashReporting

final class CrashReportReaderTests: XCTestCase {

    private var fileManager: MockFileManager!
    private let appBundleIdentifier = "com.duckduckgo.macos"
    private let vpnBundleIdentifier = "com.duckduckgo.macos.vpn.network-extension"
    private var validBundleIdentifiers: [String] { [appBundleIdentifier, vpnBundleIdentifier] }

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileManager = MockFileManager()
    }

    override func tearDownWithError() throws {
        fileManager = nil
        try super.tearDownWithError()
    }

    func testWhenFilesHaveUnsupportedExtensionsThenTheyAreIgnored() throws {
        let now = Date()
        try writeReport(named: "DuckDuckGo-valid.ips", contents: sampleIPSReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))
        try writeReport(named: "DuckDuckGo-legacy.crash", contents: sampleLegacyReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))
        try writeReport(named: "DuckDuckGo-unexpected.txt", contents: "text", in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))

        let reports = makeReader(now: now).getCrashReports(since: now.addingTimeInterval(-120))
        XCTAssertEqual(reports.count, 2)
        let returnedNames = Set(reports.map { $0.url.lastPathComponent })
        XCTAssertEqual(returnedNames, ["DuckDuckGo-valid.ips", "DuckDuckGo-legacy.crash"])
    }

    func testWhenIPSBundleIDDoesNotMatchThenItIsFilteredOut() throws {
        let now = Date()
        try writeReport(named: "DuckDuckGo-valid.ips", contents: sampleIPSReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))
        try writeReport(named: "DuckDuckGo-other.ips", contents: sampleIPSReport(bundleID: "com.example.other"), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))

        let reports = makeReader(now: now).getCrashReports(since: now.addingTimeInterval(-120))
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.url.lastPathComponent, "DuckDuckGo-valid.ips")
    }

    private func writeReport(named name: String, contents: String, in directory: URL, creationDate: Date) throws {
        let url = directory.appendingPathComponent(name)
        fileManager.registerFile(at: url, in: directory, contents: contents, creationDate: creationDate)
    }

    private func makeReader(now: Date) -> CrashReportReader {
        let validBundleIDs = validBundleIdentifiers
        return CrashReportReader(fileManager: fileManager,
                                 validBundleIdentifierProvider: { validBundleIDs },
                                 dateProvider: { now })
    }

    private func sampleIPSReport(bundleID: String? = nil) -> String {
        let bundleIDValue = bundleID ?? appBundleIdentifier
        return """
        {"bundleID":"\(bundleIDValue)","app_version":"1.2.3.4","pid":123,"timestamp":"2025-01-01 12:00:00.00 +0000"}
        {"report":"payload"}
        """
    }

    private func sampleLegacyReport() -> String {
        "Process: DuckDuckGo [123]"
    }
}
