//
//  UIImageExtension.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import UIKit
import DesignResourcesKitIcons

extension UIImage {
    
    struct Constants {
        static let buttonBorderWidth: CGFloat = 2
    }
    
    /// Based on iconImage create image that has a border around it.
    /// Result can be used to create stack of images that overlap each other.
    static func stackedIconImage(withIconImage iconImage: UIImage,
                                 borderWidth: CGFloat = Constants.buttonBorderWidth,
                                 foregroundColor: UIColor,
                                 borderColor: UIColor) -> UIImage {
        
        let imageRect = CGRect(x: 0,
                               y: 0,
                               width: iconImage.size.width + borderWidth * 2,
                               height: iconImage.size.height + borderWidth * 2)

        let renderer = UIGraphicsImageRenderer(size: imageRect.size)
        let icon = renderer.image { imageContext in
            let context = imageContext.cgContext
            context.setFillColor(borderColor.cgColor)
            context.fillEllipse(in: imageRect)
            
            context.setFillColor(foregroundColor.cgColor)
            let contentFrame = CGRect(origin: CGPoint(x: borderWidth,
                                                      y: borderWidth),
                                      size: iconImage.size)
            iconImage.draw(in: contentFrame)
        }
        
        return icon
    }
    
}

extension BrandRefreshableImage {
    static let appDownload128 = Self(.appDownload128, refresh: .appDownload128Refresh)
    static let appDuckDuckGo32 = Self(.appDuckDuckGo32, refresh: .appDuckDuckGo32Refresh)
    static let bookmarks96 = Self(.bookmarks96, refresh: .bookmarks96Refresh)
    static let bookmarksImport96 = Self(.bookmarksImport96, refresh: .bookmarksImport96Refresh)
    static let breakage128 = Self(.breakage128, refresh: .breakage128Refresh)
    static let creditCardsAdd96 = Self(.creditCardsAdd96, refresh: .creditCardsAdd96Refresh)
    static let passwordsAdd96X96 = Self(.passwordsAdd96X96, refresh: .passwordsAdd96X96Refresh)
    static let passwordsDDG96X96 = Self(.passwordsDDG96X96, refresh: .passwordsDDG96X96Refresh)
    static let personalInformationHero = Self(.personalInformationHero, refresh: .personalInformationHeroRefresh)
    static let privacyProAddDevice128 = Self(.privacyProAddDevice128, refresh: .privacyProAddDevice128Refresh)
    static let privacyProHeader = Self(.privacyProHeader, refresh: .privacyProHeaderRefresh)
    static let privacyProHeaderAlert = Self(.privacyProHeaderAlert, refresh: .privacyProHeaderAlertRefresh)
    static let remoteDuckAI = Self(.remoteDuckAi, refresh: .remoteDuckAiRefresh)
    static let remoteMessageAnnouncement = Self(.remoteMessageAnnouncement, refresh: .remoteMessageAnnouncementRefresh)
    static let remoteMessageCriticalAppUpdate = Self(.remoteMessageCriticalAppUpdate, refresh: .remoteMessageCriticalAppUpdateRefresh)
    static let remoteMessageMacComputer = Self(.remoteMessageMacComputer, refresh: .remoteMessageMacComputerRefresh)
    static let remoteMessagePIR = Self(.remoteMessagePIR, refresh: .remoteMessagePIRRefresh)
    static let remoteMessagePrivacyShield = Self(.remoteMessagePrivacyShield, refresh: .remoteMessagePrivacyShieldRefresh)
    static let remoteMessageSubscription = Self(.remoteMessageSubscription, refresh: .remoteMessageSubscriptionRefresh)
    static let sync128 = Self(.sync128, refresh: .sync128Refresh)
    static let syncDesktopNew128 = Self(.syncDesktopNew128, refresh: .syncDesktopNew128Refresh)
    static let syncPending96 = Self(.syncPending96, refresh: .syncPending96Refresh)
    static let syncRecover128 = Self(.syncRecover128, refresh: .syncRecover128Refresh)
    static let waitlistMacComputer = Self(named: "WaitlistMacComputer")
    static let windowsWaitlistJoinWaitlist = Self(named: "WindowsWaitlistJoinWaitlist")
}
