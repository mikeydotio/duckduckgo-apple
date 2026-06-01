//
//  LoginItem.swift
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

import AppKit
import Foundation
import ServiceManagement
import os.log

public enum SMLoginItemSetEnabledError: Error {
    case failed
}

/// Takes care of enabling and disabling a login item.
///
public struct LoginItem: Equatable, Hashable {

    /// Selects which kind of login item we're driving.
    ///
    /// - `helper(bundleId:)` — a separate helper agent (the original use case;
    ///   how VPN and DBP launch their background agents).
    /// - `mainApp` — the calling main app itself, registered via
    ///   `SMAppService.mainApp`. Requires macOS 13+; older systems get a no-op.
    enum Backing: Equatable, Hashable {
        case helper(bundleId: String)
        case mainApp
    }

    private let backing: Backing
    private let launchInformation: LoginItemLaunchInformation
    private let defaults: UserDefaults
    private let logger: Logger

    public var agentBundleID: String {
        switch backing {
        case .helper(let bundleId): return bundleId
        case .mainApp: return Bundle.main.bundleIdentifier ?? ""
        }
    }

    public var isRunning: Bool {
        !runningApplications.isEmpty
    }

    private var runningApplications: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleID)
    }

    public var application: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleID).first
    }

    public enum Status {
        case notRegistered
        case enabled
        case requiresApproval
        case notFound

        public var isEnabled: Bool {
            self == .enabled
        }

        public var isInstalled: Bool {
            self == .enabled || self == .requiresApproval
        }

        @available(macOS 13.0, *)
        public init(_ status: SMAppService.Status) {
            switch status {
            case .notRegistered: self = .notRegistered
            case .enabled: self = .enabled
            case .requiresApproval: self = .requiresApproval
            case .notFound: self = .notFound
            @unknown default: self = .notFound
            }
        }
    }

    public var status: Status {
        if #available(macOS 13.0, *) {
            switch backing {
            case .helper(let bundleId):
                return Status(SMAppService.loginItem(identifier: bundleId).status)
            case .mainApp:
                return Status(SMAppService.mainApp.status)
            }
        }

        switch backing {
        case .helper(let bundleId):
            guard let job = ServiceManagement.copyAllJobDictionaries(kSMDomainUserLaunchd).first(where: {
                $0["Label"] as? String == bundleId
            }) else { return .notRegistered }

            logger.debug("🟢 found login item job: \(job.debugDescription, privacy: .public)")
            return job["OnDemand"] as? Bool == true ? .enabled : .requiresApproval
        case .mainApp:
            // `SMAppService.mainApp` requires macOS 13+; no fallback API exists
            // for self-registering the running app on older systems.
            return .notRegistered
        }
    }

    public init(bundleId: String, defaults: UserDefaults, logger: Logger) {
        self.init(backing: .helper(bundleId: bundleId), defaults: defaults, logger: logger)
    }

    /// Drives `SMAppService.mainApp` — registers the calling app itself as a
    /// login item. Requires macOS 13+ at runtime; older systems get a no-op
    /// (callers should not rely on login-item launch on those systems).
    public static func mainApp(defaults: UserDefaults, logger: Logger) -> LoginItem {
        LoginItem(backing: .mainApp, defaults: defaults, logger: logger)
    }

    private init(backing: Backing, defaults: UserDefaults, logger: Logger) {
        let bundleId: String = {
            switch backing {
            case .helper(let id): return id
            case .mainApp: return Bundle.main.bundleIdentifier ?? ""
            }
        }()
        self.backing = backing
        self.defaults = defaults
        self.launchInformation = LoginItemLaunchInformation(agentBundleID: bundleId, defaults: defaults)
        self.logger = logger
    }

    public func enable() throws {
        logger.debug("🟢 registering login item \(self.debugDescription, privacy: .public)")

        if #available(macOS 13.0, *) {
            switch backing {
            case .helper(let bundleId):
                try SMAppService.loginItem(identifier: bundleId).register()
            case .mainApp:
                try SMAppService.mainApp.register()
            }
        } else {
            switch backing {
            case .helper(let bundleId):
                let success = SMLoginItemSetEnabled(bundleId as CFString, true)
                if !success {
                    throw SMLoginItemSetEnabledError.failed
                }
            case .mainApp:
                logger.debug("ℹ️ Login-item registration for the main app requires macOS 13+; no-op on this system.")
            }
        }

        launchInformation.updateLastEnabledTimestamp()
    }

    public func disable() throws {
        logger.debug("🟢 unregistering login item \(self.debugDescription, privacy: .public)")

        if #available(macOS 13.0, *) {
            switch backing {
            case .helper(let bundleId):
                try SMAppService.loginItem(identifier: bundleId).unregister()
            case .mainApp:
                try SMAppService.mainApp.unregister()
            }
        } else {
            switch backing {
            case .helper(let bundleId):
                let success = SMLoginItemSetEnabled(bundleId as CFString, false)
                if !success {
                    throw SMLoginItemSetEnabledError.failed
                }
            case .mainApp:
                logger.debug("ℹ️ Login-item unregistration for the main app requires macOS 13+; no-op on this system.")
            }
        }
    }

    /// Restarts a login item.
    ///
    /// This call will only enable the login item if it was enabled to begin with.
    ///
    public func restart() throws {
        guard [.enabled].contains(status) else {
            logger.debug("🟢 restart not needed for login item \(self.debugDescription, privacy: .public)")
            return
        }
        try? disable()
        try enable()
    }

    public func forceStop() {
        let runningApplications = runningApplications
        logger.debug("🟢 stopping \(runningApplications.map { $0.processIdentifier }.description, privacy: .public)")
        runningApplications.forEach { $0.terminate() }
    }

    public static func == (lhs: LoginItem, rhs: LoginItem) -> Bool {
        lhs.agentBundleID == rhs.agentBundleID && lhs.launchInformation == rhs.launchInformation
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(agentBundleID)
        hasher.combine(launchInformation)
    }
}

extension LoginItem: CustomDebugStringConvertible {

    public var debugDescription: String {
        "<LoginItem \(agentBundleID) isEnabled: \(status) isRunning: \(isRunning)>"
    }

}

private protocol ServiceManagementProtocol {
    func copyAllJobDictionaries(_ domain: CFString!) -> [[String: Any]]
    var errorDomain: String { get }
}
private struct SM: ServiceManagementProtocol {

    // suppress SMCopyAllJobDictionaries deprecation warning
    @available(macOS, introduced: 10.6, deprecated: 10.10)
    func copyAllJobDictionaries(_ domain: CFString!) -> [[String: Any]] {
        SMCopyAllJobDictionaries(domain).takeRetainedValue() as? [[String: Any]] ?? []
    }

    @available(macOS, introduced: 10.6, deprecated: 10.10)
    var errorDomain: String {
        if #available(macOS 13.0, *) {
            return "SMAppServiceErrorDomain"
        } else {
            return kSMErrorDomainLaunchd as String
        }
    }

}

private var ServiceManagement: ServiceManagementProtocol { SM() } // swiftlint:disable:this identifier_name
