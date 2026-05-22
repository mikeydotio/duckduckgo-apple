//
//  DDGSyncTests.swift
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

import Combine
import Common
import CryptoKit
import XCTest

@testable import DDGSync

enum SyncOperationEvent: Equatable {
    case started(_ taskID: Int)
    case fetch(_ taskID: Int)
    case handleResponse(_ taskID: Int)
    case finished(_ taskID: Int)
}

final class DDGSyncTests: XCTestCase {
    var dataProvidersSource: MockDataProvidersSource!
    var dependencies: MockSyncDependencies!

    var syncStartedExpectation: XCTestExpectation!
    var fetchExpectation: XCTestExpectation!
    var handleSyncResponseExpectation: XCTestExpectation!
    var syncFinishedExpectation: XCTestExpectation!
    var isInProgressCancellable: AnyCancellable?
    var recordedEvents: [SyncOperationEvent] = []
    var taskID = 1

    override func setUpWithError() throws {
        try super.setUpWithError()

        recordedEvents = []
        taskID = 1

        dataProvidersSource = MockDataProvidersSource()
        dependencies = MockSyncDependencies()
        (dependencies.api as! RemoteAPIRequestCreatingMock).fakeRequests = [
            URL(string: "https://dev.null/sync/credentials")!: HTTPRequestingMock(result: .init(data: "{\"credentials\":{\"last_modified\":\"1234\",\"entries\":[]}}".data(using: .utf8)!, response: .init())),
            URL(string: "https://dev.null/sync/bookmarks")!: HTTPRequestingMock(result: .init(data: "{\"bookmarks\":{\"last_modified\":\"1234\",\"entries\":[]}}".data(using: .utf8)!, response: .init())),
            URL(string: "https://dev.null/sync/data")!: HTTPRequestingMock(result: .init(data: "{\"bookmarks\":{\"last_modified\":\"1234\",\"entries\":[]},\"credentials\":{\"last_modified\":\"1234\",\"entries\":[]}}".data(using: .utf8)!, response: .init()))
        ]

        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock
        try dependencies.keyValueStore.set(true, forKey: DDGSync.Constants.syncEnabledKey)
    }

    override func tearDownWithError() throws {
        isInProgressCancellable?.cancel()
        isInProgressCancellable = nil

        try super.tearDownWithError()
    }

    // MARK: - Setup

    func setUpExpectations(started syncStartedExpectedCount: Int, fetch fetchExpectedCount: Int, handleResponse handleSyncResponseExpectedCount: Int, finished syncFinishedExpectedCount: Int) {
        if syncStartedExpectedCount > 0 {
            syncStartedExpectation = expectation(description: "syncStarted")
            syncStartedExpectation.expectedFulfillmentCount = syncStartedExpectedCount
        }

        if fetchExpectedCount > 0 {
            fetchExpectation = expectation(description: "fetch")
            fetchExpectation.expectedFulfillmentCount = fetchExpectedCount
        }

        if handleSyncResponseExpectedCount > 0 {
            handleSyncResponseExpectation = expectation(description: "handleSyncResponse")
            handleSyncResponseExpectation.expectedFulfillmentCount = handleSyncResponseExpectedCount
        }

        if syncFinishedExpectedCount > 0 {
            syncFinishedExpectation = expectation(description: "syncFinished")
            syncFinishedExpectation.expectedFulfillmentCount = syncFinishedExpectedCount
        }
    }

    func setUpDataProviderCallbacks(for dataProvider: DataProvidingMock) {
        dataProvider._fetchChangedObjects = { _ in
            let syncables = [Syncable(jsonObject: ["taskNumber": self.taskID])]
            self.recordedEvents.append(.fetch(self.taskID))
            self.fetchExpectation.fulfill()
            return syncables
        }
        dataProvider.handleSyncResponse = { sent, _, _, _, _ in
            let taskID = sent[0].payload["taskNumber"] as! Int
            self.recordedEvents.append(.handleResponse(taskID))
            self.handleSyncResponseExpectation.fulfill()
        }
    }

    func bindInProgressPublisher(for syncService: DDGSyncing) {
        isInProgressCancellable = syncService.isSyncInProgressPublisher.sink { isInProgress in
            if isInProgress {
                self.recordedEvents.append(.started(self.taskID))
                self.syncStartedExpectation.fulfill()
            } else {
                self.recordedEvents.append(.finished(self.taskID))
                self.syncFinishedExpectation.fulfill()
                self.taskID += 1
            }
        }
    }

    // MARK: - Tests

    func testThatRegularSyncOperationsAreSerialized() {
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        dataProvider.updateSyncTimestamps(server: "1234", local: nil)
        setUpDataProviderCallbacks(for: dataProvider)
        setUpExpectations(started: 3, fetch: 3, handleResponse: 3, finished: 3)

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 1)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1),
            .started(2),
            .fetch(2),
            .handleResponse(2),
            .finished(2),
            .started(3),
            .fetch(3),
            .handleResponse(3),
            .finished(3)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallCount, 3)
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.patch, .patch, .patch])
    }

    func testThatFirstSyncAndRegularSyncOperationsAreSerialized() {
        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock.updatingState(.addingNewDevice)
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        setUpDataProviderCallbacks(for: dataProvider)
        setUpExpectations(started: 3, fetch: 3, handleResponse: 3, finished: 3)

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 5)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1),
            .started(2),
            .fetch(2),
            .handleResponse(2),
            .finished(2),
            .started(3),
            .fetch(3),
            .handleResponse(3),
            .finished(3)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallCount, 4)
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.get, .patch, .patch, .patch])
    }

    func testWhenNewSyncAccountIsCreatedWithMultipleModelsThenInitialFetchDoesNotHappen() throws {
        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock.updatingState(.active)
        let bookmarksDataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        bookmarksDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }

        let credentialsDataProvider = DataProvidingMock(feature: .init(name: "credentials"))
        credentialsDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }
        setUpDataProviderCallbacks(for: credentialsDataProvider)
        setUpExpectations(started: 1, fetch: 1, handleResponse: 1, finished: 1)

        dataProvidersSource.dataProviders = [bookmarksDataProvider, credentialsDataProvider]
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 5)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallCount, 2)
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.patch, .patch])
    }

    func testWhenDeviceIsAddedToExistingSyncAccountWithMultipleModelsThenInitialFetchHappens() throws {
        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock.updatingState(.addingNewDevice)
        let bookmarksDataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        bookmarksDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }

        let credentialsDataProvider = DataProvidingMock(feature: .init(name: "credentials"))
        credentialsDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }
        setUpDataProviderCallbacks(for: credentialsDataProvider)
        setUpExpectations(started: 1, fetch: 1, handleResponse: 1, finished: 1)

        dataProvidersSource.dataProviders = [bookmarksDataProvider, credentialsDataProvider]
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 1)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallCount, 4)
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.get, .get, .patch, .patch])
    }

    /// Test initial fetch for newly added models.
    ///
    /// Start with:
    /// * Sync in active state
    /// * bookmarks provider that has been synced
    /// * credentials provider that hasn't been synced
    ///
    /// Request sync twice and test that:
    /// * the first sync operation calls 3 requests: initial for credentials, and regular for bookmarks and credentials
    /// * the second sync operation calls 2 request: regular sync for bookmarks and credentials
    func testThatWhenNewModelIsAddedThenItPerformsInitialFetch() throws {
        (dependencies.secureStore as! SecureStorageStub).theAccount = .mock.updatingState(.active)
        let bookmarksDataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        try bookmarksDataProvider.registerFeature(withState: .readyToSync)
        bookmarksDataProvider.updateSyncTimestamps(server: "1234", local: nil)
        bookmarksDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }

        let credentialsDataProvider = DataProvidingMock(feature: .init(name: "credentials"))
        credentialsDataProvider._fetchChangedObjects = { _ in
            [.init(jsonObject: ["id": UUID().uuidString])]
        }
        setUpDataProviderCallbacks(for: credentialsDataProvider)
        setUpExpectations(started: 2, fetch: 2, handleResponse: 2, finished: 2)

        dataProvidersSource.dataProviders = [bookmarksDataProvider, credentialsDataProvider]
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 5)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1),
            .started(2),
            .fetch(2),
            .handleResponse(2),
            .finished(2)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallCount, 5)
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.get, .patch, .patch, .patch, .patch])
        XCTAssertEqual(api.createRequestCallArgs[0].url.lastPathComponent, "credentials")
    }

    func testWhenSyncOperationIsCancelledThenCurrentOperationReturnsEarlyAndOtherScheduledOperationsDoNotEmitSyncStarted() {
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        dataProvider.updateSyncTimestamps(server: "1234", local: nil)
        setUpDataProviderCallbacks(for: dataProvider)
        setUpExpectations(started: 2, fetch: 1, handleResponse: 1, finished: 2)

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()

        isInProgressCancellable = syncService.isSyncInProgressPublisher.sink { [weak syncService] isInProgress in
            if isInProgress {
                self.recordedEvents.append(.started(self.taskID))
                self.syncStartedExpectation.fulfill()
                if self.taskID == 2 {
                    syncService?.scheduler.cancelSyncAndSuspendSyncQueue()
                }
            } else {
                self.recordedEvents.append(.finished(self.taskID))
                self.syncFinishedExpectation.fulfill()
                self.taskID += 1
            }
        }

        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 1)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1),
            .started(2),
            .finished(2)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.patch])
    }

    func testWhenSyncQueueIsSuspendedThenNewOperationsDoNotStart() {
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        setUpDataProviderCallbacks(for: dataProvider)

        setUpExpectations(started: 1, fetch: 1, handleResponse: 1, finished: 1)
        syncStartedExpectation.isInverted = true
        fetchExpectation.isInverted = true
        handleSyncResponseExpectation.isInverted = true
        syncFinishedExpectation.isInverted = true

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.cancelSyncAndSuspendSyncQueue()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 0.1)

        XCTAssertEqual(recordedEvents, [])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallArgs, [])
    }

    func testWhenSyncQueueIsResumedThenScheduledOperationStarts() {
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        dataProvider.updateSyncTimestamps(server: "1234", local: nil)
        setUpDataProviderCallbacks(for: dataProvider)

        setUpExpectations(started: 1, fetch: 1, handleResponse: 1, finished: 1)

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.cancelSyncAndSuspendSyncQueue()
        syncService.scheduler.requestSyncImmediately()
        syncService.scheduler.resumeSyncQueue()

        waitForExpectations(timeout: 0.1)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .handleResponse(1),
            .finished(1)
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertEqual(api.createRequestCallArgs.map(\.method), [.patch])
    }

    func testWhenSyncGetsDisabledBeforeStartingOperationThenOperationReturnsEarly() throws {
        throw XCTSkip("Flakey test")
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        setUpDataProviderCallbacks(for: dataProvider)
        setUpExpectations(started: 1, fetch: 1, handleResponse: 1, finished: 1)
        fetchExpectation.isInverted = true
        handleSyncResponseExpectation.isInverted = true

        dataProvidersSource.dataProviders = [dataProvider]

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        syncService.scheduler.requestSyncImmediately()
        try dependencies.secureStore.removeAccount()

        waitForExpectations(timeout: 5)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .finished(1),
        ])

        let api = dependencies.api as! RemoteAPIRequestCreatingMock
        XCTAssertTrue(api.createRequestCallArgs.isEmpty)
    }

    func testThatSyncOperationRequestReturningHTTP401CausesLoggingOutOfSync() throws {
        throw XCTSkip("Flakey test")
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        dataProvider.updateSyncTimestamps(server: "1234", local: nil)
        setUpDataProviderCallbacks(for: dataProvider)
        setUpExpectations(started: 1, fetch: 1, handleResponse: 0, finished: 1)

        dataProvidersSource.dataProviders = [dataProvider]
        (dependencies.api as! RemoteAPIRequestCreatingMock).fakeRequests = [:]
        let http401Response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 401, httpVersion: nil, headerFields: [:])!
        dependencies.request.result = HTTPResult(data: Data(), response: http401Response)

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        XCTAssertEqual(syncService.authState, .active)

        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 2)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .finished(1)
        ])

        XCTAssertEqual(syncService.authState, .inactive)
    }

    func testThatSyncOperationRequestThrowingHTTP401CausesLoggingOutOfSync() throws {
        throw XCTSkip("Flakey test")
        let dataProvider = DataProvidingMock(feature: .init(name: "bookmarks"))
        dataProvider.updateSyncTimestamps(server: "1234", local: nil)
        setUpDataProviderCallbacks(for: dataProvider)
        setUpExpectations(started: 1, fetch: 1, handleResponse: 0, finished: 1)

        dataProvidersSource.dataProviders = [dataProvider]
        (dependencies.api as! RemoteAPIRequestCreatingMock).fakeRequests = [:]
        dependencies.request.error = SyncError.unexpectedStatusCode(401)

        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()
        bindInProgressPublisher(for: syncService)

        XCTAssertEqual(syncService.authState, .active)

        syncService.scheduler.requestSyncImmediately()

        waitForExpectations(timeout: 5)

        XCTAssertEqual(recordedEvents, [
            .started(1),
            .fetch(1),
            .finished(1)
        ])

        XCTAssertEqual(syncService.authState, .inactive)
    }

    func testWhenRemovePreservedSyncAccountAndSyncIsActiveThenItDoesNothing() throws {
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)
        syncService.initializeIfNeeded()

        XCTAssertEqual(syncService.authState, .active)
        XCTAssertNotNil((dependencies.secureStore as! SecureStorageStub).theAccount)

        try syncService.removePreservedSyncAccount()

        XCTAssertEqual(syncService.authState, .active)
        XCTAssertNotNil((dependencies.secureStore as! SecureStorageStub).theAccount)
        XCTAssertEqual((dependencies.errorEvents as! MockErrorHandler).handledErrors, [])
    }

    func testWhenNativeRecoveryCodeFeatureFlagIsDisabledThenRecoveryCodeUsesV1Payload() throws {
        dependencies.isScopedAccessCredentialsEnabled = { false }
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        guard let code = syncService.recoveryCode else {
            XCTFail("Expected native recovery code")
            return
        }

        let decoded = try SyncCode.decodeBase64String(code)
        guard case .v1(let payload) = decoded.recovery else {
            XCTFail("Expected v1 native recovery payload")
            return
        }

        XCTAssertEqual(payload.userId, SyncAccount.mock.userId)
        XCTAssertEqual(payload.primaryKey, SyncAccount.mock.primaryKey)
    }

    func testWhenNativeRecoveryCodeFeatureFlagIsEnabledThenRecoveryCodeUsesV2Payload() throws {
        dependencies.isScopedAccessCredentialsEnabled = { true }
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        guard let code = syncService.recoveryCode else {
            XCTFail("Expected native recovery code")
            return
        }

        let decoded = try SyncCode.decodeBase64String(code)
        guard case .v2(let payload) = decoded.recovery else {
            XCTFail("Expected v2 native recovery payload")
            return
        }

        XCTAssertEqual(payload.userId, SyncAccount.mock.userId)
        XCTAssertEqual(payload.cid, SyncCode.RecoveryKeyV2.nativeCredentialId)
        XCTAssertEqual(payload.v, SyncCode.RecoveryKeyV2.currentVersion)
        XCTAssertEqual(payload.secret, try XCTUnwrap(SyncAccount.mock.nativeCredentialSecret))
    }

    func testWhenNativeRecoveryCodeFeatureFlagIsEnabledButNativeSecretIsMissingThenV2PayloadFallsBackToPrimaryKeyBytes() throws {
        dependencies.isScopedAccessCredentialsEnabled = { true }
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = SyncAccount.mock.updatingNativeCredentialSecret(nil)
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        guard let code = syncService.recoveryCode else {
            XCTFail("Expected native recovery code")
            return
        }

        let decoded = try SyncCode.decodeBase64String(code)
        guard case .v2(let payload) = decoded.recovery else {
            XCTFail("Expected v2 native recovery payload")
            return
        }

        XCTAssertEqual(payload.cid, SyncCode.RecoveryKeyV2.nativeCredentialId)
        XCTAssertEqual(Base64URL.decode(payload.secret), SyncAccount.mock.primaryKey)
    }

    func testWhenLoginResponseContainsProtectedKeysThenAllKeysAreCached() async throws {
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = nil
        let protectedKeys = [
            makeProtectedKey(kid: "key-3party", encryptedWith: "3party"),
            makeProtectedKey(kid: "key-ddg", encryptedWith: "ddg"),
            makeProtectedKey(kid: "key-ddg", encryptedWith: "ddg"),
            makeProtectedKey(kid: "key-ddg-secondary", encryptedWith: "ddg")
        ]
        (dependencies.account as? AccountManagingMock)?.loginStub = LoginResult(account: .mock,
                                                                                devices: [],
                                                                                keys: protectedKeys)
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        _ = try await syncService.login(.init(userId: "userId", primaryKey: Data()),
                                        deviceName: "iPhone",
                                        deviceType: "iOS")

        let cachedKeysData = try XCTUnwrap((dependencies.secureStore as? SecureStorageStub)?.theProtectedKeysData)
        let cachedKeys = try JSONDecoder.snakeCaseKeys.decode([ProtectedKey].self, from: cachedKeysData)

        XCTAssertEqual(Set(cachedKeys.map(\.kid)), Set(["key-3party", "key-ddg", "key-ddg-secondary"]))
        XCTAssertEqual(Set(cachedKeys.map(\.encryptedWith)), Set(["3party", "ddg"]))
        XCTAssertEqual(cachedKeys.count, 3)
    }

    func testWhenScopedPasswordRecoveryFailsDuringLoginThenNativeLoginStillSucceeds() async throws {
        (dependencies.secureStore as? SecureStorageStub)?.theAccount = nil
        (dependencies.account as? AccountManagingMock)?.loginStub = LoginResult(
            account: .mock,
            devices: [.mock],
            accessCredentials: [AccessCredential(id: "3party", scope: "sync", encrypted3PartyCredential: "invalid")]
        )
        let scopedAccess = try XCTUnwrap(dependencies.scopedAccess as? ScopedAccessCredentialManagingMock)
        scopedAccess.recoverScopedPasswordError = SyncError.invalidDataInResponse("broken scoped credential")
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        let devices = try await syncService.login(.init(userId: "userId", primaryKey: Data()),
                                                  deviceName: "iPhone",
                                                  deviceType: "iOS")

        XCTAssertEqual(devices.map(\.id), [RegisteredDevice.mock.id])
        XCTAssertNotNil((dependencies.secureStore as? SecureStorageStub)?.theAccount)
        XCTAssertNil((dependencies.secureStore as? SecureStorageStub)?.theScopedPassword)
        XCTAssertEqual(scopedAccess.recoverScopedPasswordCalls.count, 1)
    }

    func testWhenPreparingThirdPartyRecoveryCodeAndCredentialExistsThenRecoveredScopedPasswordIsUsed() async throws {
        let account = try XCTUnwrap((dependencies.secureStore as? SecureStorageStub)?.theAccount)
        let scopedPassword = Data(repeating: 8, count: 32)
        let defaultCredentialMainKey = scopedAccessMainKey(from: account.primaryKey, userID: account.userId)
        let encryptedCredential = try ScopedAccessCredentialEnvelope().encryptScopedPassword(scopedPassword,
                                                                                           using: defaultCredentialMainKey,
                                                                                           kid: "ddg")
        let scopedAccess = try XCTUnwrap(dependencies.scopedAccess as? ScopedAccessCredentialManagingMock)
        scopedAccess.fetchAccessCredentialsStub = [
            AccessCredential(id: "3party", scope: "sync", encrypted3PartyCredential: encryptedCredential)
        ]
        scopedAccess.recoverScopedPasswordStub = scopedPassword
        scopedAccess.fetchProtectedKeysStub = [makeProtectedKey(kid: "key-ddg", encryptedWith: "ddg")]
        scopedAccess.ensureThirdPartyAccessCredentialStub = scopedPassword
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        let code = try await syncService.prepareThirdPartyRecoveryCode(purpose: "ai_chats")
        let decoded = try SyncCode.decodeBase64URLString(code)

        XCTAssertEqual(scopedAccess.fetchAccessCredentialsCalls.count, 1)
        XCTAssertEqual(scopedAccess.recoverScopedPasswordCalls.count, 1)
        XCTAssertTrue(scopedAccess.ensureThirdPartyAccessCredentialCalls.isEmpty)
        XCTAssertEqual((dependencies.secureStore as? SecureStorageStub)?.theScopedPassword, scopedPassword)
        guard case .v2(let payload) = decoded.recovery else {
            XCTFail("Expected v2 recovery payload")
            return
        }
        XCTAssertEqual(Base64URL.decode(payload.secret), scopedPassword)
    }

    func testWhenPreparingThirdPartyRecoveryCodeAndCredentialDoesNotExistThenScopedPasswordIsGenerated() async throws {
        let scopedAccess = try XCTUnwrap(dependencies.scopedAccess as? ScopedAccessCredentialManagingMock)
        scopedAccess.fetchAccessCredentialsStub = []
        scopedAccess.fetchProtectedKeysStub = [makeProtectedKey(kid: "key-ddg", encryptedWith: "ddg")]
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        _ = try await syncService.prepareThirdPartyRecoveryCode(purpose: "ai_chats")

        let scopedPassword = try XCTUnwrap(scopedAccess.ensureThirdPartyAccessCredentialCalls.first?.scopedPassword)
        XCTAssertEqual(scopedAccess.fetchAccessCredentialsCalls.count, 1)
        XCTAssertEqual(scopedPassword.count, 32)
    }

    func testWhenPreparingThirdPartyRecoveryCodeAndNoDefaultKeyExistsThenCredentialIncludesDefaultAndThirdPartyKeys() async throws {
        let scopedAccess = try XCTUnwrap(dependencies.scopedAccess as? ScopedAccessCredentialManagingMock)
        scopedAccess.fetchAccessCredentialsStub = []
        scopedAccess.fetchProtectedKeysStub = []
        let syncService = DDGSync(dataProvidersSource: dataProvidersSource, dependencies: dependencies)

        _ = try await syncService.prepareThirdPartyRecoveryCode(purpose: "ai_chats")

        XCTAssertTrue(scopedAccess.setKeyIfAbsentCalls.isEmpty)
        XCTAssertEqual(scopedAccess.ensureThirdPartyAccessCredentialCalls.first?.keys.count, 1)
        XCTAssertEqual(scopedAccess.ensureThirdPartyAccessCredentialCalls.first?.keys.first?.encryptedWith, "ddg")
        XCTAssertEqual(scopedAccess.ensureThirdPartyAccessCredentialCalls.first?.keys.first?.purpose, "ai_chats")
        XCTAssertEqual(scopedAccess.ensureThirdPartyAccessCredentialCalls.first?.keys.first?.publicKey.use, "enc")
        XCTAssertEqual(scopedAccess.ensureThirdPartyAccessCredentialCalls.first?.includesNewDefaultKeys, true)
    }

    func testWhenGeneratingThirdPartyRecoveryCodeThenPayloadMatchesV2Spec() throws {
        let scopedPassword = Data(repeating: 7, count: 32)

        let code = try XCTUnwrap(SyncAccount.mock.scopedAccessRecoveryCode(scopedPassword: scopedPassword))
        let decoded = try SyncCode.decodeBase64URLString(code)

        guard case .v2(let payload) = decoded.recovery else {
            XCTFail("Expected v2 recovery payload")
            return
        }

        XCTAssertEqual(payload.userId, "userId")
        XCTAssertEqual(payload.cid, "3party")
        XCTAssertEqual(payload.v, "2.0")
        XCTAssertFalse(payload.secret.isEmpty)
        // `secret` is base64URL(no padding) of the raw SP bytes.
        XCTAssertEqual(Base64URL.decode(payload.secret), scopedPassword)
    }

    private func makeProtectedKey(kid: String, encryptedWith: String) -> ProtectedKey {
        ProtectedKey(kid: kid,
                     encryptedPrivateKey: "encrypted-private-key",
                     publicKey: .mock,
                     encryptedWith: encryptedWith,
                     purpose: "browser")
    }

    private func scopedAccessMainKey(from secret: Data, userID: String) -> Data {
        let derivedKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: secret),
                                                salt: Data(userID.utf8),
                                                info: Data("Main Key".utf8),
                                                outputByteCount: 32)
        return derivedKey.withUnsafeBytes { Data($0) }
    }
}
