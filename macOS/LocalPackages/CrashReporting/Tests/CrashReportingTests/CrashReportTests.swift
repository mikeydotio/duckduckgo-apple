//
//  CrashReportTests.swift
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

import XCTest
@testable import CrashReporting

final class CrashReportTests: XCTestCase {

    func testWhenParsingIPSCrashReportsThenCrashReportDataDoesNotIncludeIdentifyingInformation() throws {
        let fileManager = MockFileManager()
        let reportURL = URL(fileURLWithPath: "/tmp/DuckDuckGo-ExampleCrash.ips")
        let contents = """
        {"bundleID":"com.duckduckgo.macos.browser","app_version":"1.2.3.4","sleepWakeUUID":"2384290E-F858-4024-9488-11D3FF94B4DD","deviceIdentifierForVendor":"483B097A-A969-596F-9F2A-357347BB1DEC","rolloutId":"601d9415f79519000ccd4b69","slice_uuid":"7fc6ff2c-a85d-3116-96d9-9368ec955ba1","pid":123,"timestamp":"2025-01-01 12:00:00.00 +0000"}
        {"report":"payload"}
        """
        fileManager.registerFile(at: reportURL, in: FileManager.userDiagnosticReports, contents: contents, creationDate: .now)
        let report = JSONCrashReport(url: reportURL, fileManager: fileManager)

        XCTAssertNotNil(report.content)
        XCTAssertNotNil(report.contentData)

        XCTAssertTrue(report.content!.contains("7fc6ff2c-a85d-3116-96d9-9368ec955ba1"))
        XCTAssertFalse(report.content!.contains("2384290E-F858-4024-9488-11D3FF94B4DD"))
        XCTAssertFalse(report.content!.contains("483B097A-A969-596F-9F2A-357347BB1DEC"))
        XCTAssertFalse(report.content!.contains("601d9415f79519000ccd4b69"))
        XCTAssertTrue(report.content!.contains(#""sleepWakeUUID":"<removed>""#))
        XCTAssertTrue(report.content!.contains(#""deviceIdentifierForVendor":"<removed>""#))
    }
}
