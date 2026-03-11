//
//  DBPContinuedProcessingProgressReporter.swift
//  DuckDuckGo
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

import DataBrokerProtectionCore
import Foundation

@MainActor
final class DBPContinuedProcessingProgressReporter {

    struct ScanJobID: Hashable, Sendable {
        let brokerId: Int64
        let profileQueryId: Int64
    }

    struct OptOutJobID: Hashable, Sendable {
        let brokerId: Int64
        let profileQueryId: Int64
        let extractedProfileId: Int64
    }

    struct ScanJobSummary: Sendable {
        let id: ScanJobID
    }

    struct OptOutJobSummary: Sendable {
        let id: OptOutJobID
    }

    struct InitialScanSummary {
        let scanJobs: [ScanJobSummary]

        var scanCount: Int {
            scanJobs.count
        }
    }

    struct OptOutSummary {
        let optOutJobs: [OptOutJobSummary]

        var optOutCount: Int {
            optOutJobs.count
        }
    }

    struct Snapshot {
        let completed: Int64
        let total: Int64
    }

    private enum Phase {
        case scan
        case optOut
    }

    private enum Constants {
        static let preparingScanSubtitle = "Preparing scan"
        static let preparingOptOutSubtitle = "Continuing opt-outs for found matches"
    }

    private struct SummaryKey: Hashable {
        let brokerId: Int64
        let profileQueryId: Int64
    }

    private struct PlannedItemProgress<ID: Hashable> {
        let id: ID
        let allottedUnits: Int64
        var isCompleted: Bool
    }

    private var phase: Phase?
    private var scanCompletedUnits: Int64 = 0
    private var scanTotalUnits: Int64 = 0
    private var optOutCompletedUnits: Int64 = 0
    private var optOutTotalUnits: Int64 = 0
    private var reservedOptOutUnits: Int64 = 0
    private var plannedScans: [ScanJobID: PlannedItemProgress<ScanJobID>] = [:]
    private var plannedOptOuts: [OptOutJobID: PlannedItemProgress<OptOutJobID>] = [:]

    // MARK: - Run Setup

    func startInitialRun(summary: InitialScanSummary, scanBudgetUnitsPerJob: Int64) {
        let scanBudgetUnitsPerJob = max(scanBudgetUnitsPerJob, 1)
        phase = .scan
        scanCompletedUnits = 0
        optOutCompletedUnits = 0
        plannedScans = Dictionary(uniqueKeysWithValues: summary.scanJobs.map {
            (
                $0.id,
                PlannedItemProgress(
                    id: $0.id,
                    allottedUnits: scanBudgetUnitsPerJob,
                    isCompleted: false
                )
            )
        })
        plannedOptOuts = [:]
        scanTotalUnits = max(plannedScans.values.reduce(0) { $0 + $1.allottedUnits }, scanBudgetUnitsPerJob)
        reservedOptOutUnits = scanTotalUnits
        optOutTotalUnits = reservedOptOutUnits
    }

    func enterScanPhase() {
        phase = .scan
    }

    func enterOptOutPhase(summary: OptOutSummary) {
        phase = .optOut
        optOutTotalUnits = reservedOptOutUnits
        let allottedUnitsPerJob = distribute(totalUnits: reservedOptOutUnits, acrossItemCount: summary.optOutJobs.count)
        plannedOptOuts = Dictionary(uniqueKeysWithValues: zip(summary.optOutJobs, allottedUnitsPerJob).map { job, allottedUnits in
            (
                job.id,
                PlannedItemProgress(
                    id: job.id,
                    allottedUnits: allottedUnits,
                    isCompleted: false
                )
            )
        })
    }

    // MARK: - Progress Updates

    func advanceHeartbeat() {
        switch phase {
        case .scan:
            advance(completedUnits: &scanCompletedUnits, totalUnits: &scanTotalUnits)
        case .optOut:
            advance(completedUnits: &optOutCompletedUnits, totalUnits: &optOutTotalUnits)
        case .none:
            return
        }
    }

    func completeScanPhase() {
        plannedScans = plannedScans.mapValues { progress in
            var progress = progress
            progress.isCompleted = true
            return progress
        }
        scanCompletedUnits = max(scanCompletedUnits, scanTotalUnits)
    }

    func completeOptOutPhase() {
        plannedOptOuts = plannedOptOuts.mapValues { progress in
            var progress = progress
            progress.isCompleted = true
            return progress
        }
        optOutCompletedUnits = max(optOutCompletedUnits, optOutTotalUnits)
    }

    func completeAll() {
        completeScanPhase()
        completeOptOutPhase()
    }

    func recordCompletedScan(_ id: ScanJobID) {
        guard var progress = plannedScans[id], !progress.isCompleted else { return }
        progress.isCompleted = true
        plannedScans[id] = progress
        scanCompletedUnits = max(scanCompletedUnits, plannedScans.values.filter(\.isCompleted).reduce(0) { $0 + $1.allottedUnits })
    }

    func recordCompletedOptOut(_ id: OptOutJobID) {
        guard var progress = plannedOptOuts[id], !progress.isCompleted else { return }
        progress.isCompleted = true
        plannedOptOuts[id] = progress
        optOutCompletedUnits = max(optOutCompletedUnits, plannedOptOuts.values.filter(\.isCompleted).reduce(0) { $0 + $1.allottedUnits })
    }

    // MARK: - Reporting

    func snapshot() -> Snapshot {
        Snapshot(completed: scanCompletedUnits + optOutCompletedUnits,
                 total: max(scanTotalUnits + optOutTotalUnits, 1))
    }

    var scanSubtitle: String {
        let brokerCount = uniqueScanBrokerCount
        guard brokerCount > 0 else {
            return Constants.preparingScanSubtitle
        }

        return "Scanning \(completedScanBrokerCount) of \(brokerCount) brokers"
    }

    var optOutSubtitle: String {
        let optOutCount = plannedOptOuts.count
        guard optOutCount > 0 else {
            return Constants.preparingOptOutSubtitle
        }

        return "Submitting \(optOutCount) opt-out requests"
    }

    // MARK: - Helpers

    private func advance(completedUnits: inout Int64, totalUnits: inout Int64) {
        if completedUnits < totalUnits {
            completedUnits += 1
        } else {
            completedUnits += 1
            totalUnits += 1
        }
    }

    private func distribute(totalUnits: Int64, acrossItemCount itemCount: Int) -> [Int64] {
        guard itemCount > 0 else { return [] }

        let baseUnits = totalUnits / Int64(itemCount)
        let remainder = totalUnits % Int64(itemCount)

        return (0..<itemCount).map { index in
            baseUnits + (Int64(index) < remainder ? 1 : 0)
        }
    }

    private var uniqueScanBrokerCount: Int {
        Set(plannedScans.keys.map(\.brokerId)).count
    }

    private var completedScanBrokerCount: Int {
        Dictionary(grouping: plannedScans.values, by: \.id.brokerId)
            .values
            .filter { brokerJobs in brokerJobs.allSatisfy(\.isCompleted) }
            .count
    }

}

// MARK: - Summary Builders

extension DBPContinuedProcessingProgressReporter {
    static func makeInitialScanSummary(
        from brokerProfileQueryData: [BrokerProfileQueryData],
        priorityDate: Date = Date()
    ) -> InitialScanSummary {
        let eligibleJobs = BrokerProfileJob.sortedEligibleJobs(
            brokerProfileQueriesData: brokerProfileQueryData,
            jobType: .manualScan,
            priorityDate: priorityDate
        )

        let scanJobs = eligibleJobs.compactMap { $0 as? ScanJobData }
        let scanJobsSummary = scanJobs.map { job in
            return ScanJobSummary(
                id: .init(brokerId: job.brokerId, profileQueryId: job.profileQueryId)
            )
        }

        return InitialScanSummary(scanJobs: scanJobsSummary)
    }

    static func makeOptOutSummary(
        from brokerProfileQueryData: [BrokerProfileQueryData],
        priorityDate: Date = Date()
    ) -> OptOutSummary {
        let eligibleJobs = BrokerProfileJob.sortedEligibleJobs(
            brokerProfileQueriesData: brokerProfileQueryData,
            jobType: .optOut,
            priorityDate: priorityDate
        )

        let optOutJobs = eligibleJobs.compactMap { $0 as? OptOutJobData }
        let dataByKey: [SummaryKey: BrokerProfileQueryData] = Dictionary(uniqueKeysWithValues: brokerProfileQueryData.compactMap { queryData -> (SummaryKey, BrokerProfileQueryData)? in
            guard let brokerId = queryData.dataBroker.id,
                  let profileQueryId = queryData.profileQuery.id else { return nil }
            return (
                SummaryKey(brokerId: brokerId, profileQueryId: profileQueryId),
                queryData
            )
        })

        let optOutJobsSummary = optOutJobs.compactMap { job -> OptOutJobSummary? in
            guard let extractedProfileId = job.extractedProfile.id else { return nil }
            let key = SummaryKey(brokerId: job.brokerId, profileQueryId: job.profileQueryId)
            guard let queryData = dataByKey[key],
                  shouldIncludeInInitialOptOutProgress(job: job, queryData: queryData) else {
                return nil
            }

            return OptOutJobSummary(
                id: .init(
                    brokerId: job.brokerId,
                    profileQueryId: job.profileQueryId,
                    extractedProfileId: extractedProfileId
                )
            )
        }

        return OptOutSummary(optOutJobs: optOutJobsSummary)
    }

    private static func shouldIncludeInInitialOptOutProgress(
        job: OptOutJobData,
        queryData: BrokerProfileQueryData
    ) -> Bool {
        guard job.extractedProfile.removedDate == nil else {
            return false
        }

        guard !queryData.dataBroker.performsOptOutWithinParent() else {
            return false
        }

        return !job.historyEvents.doesBelongToUserRemovedRecord
    }
}
