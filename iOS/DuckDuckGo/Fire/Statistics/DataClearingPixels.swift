//
//  DataClearingPixels.swift
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

import Foundation
import PixelKit

enum DataClearingPixels {

    // MARK: - Overall Flow Metrics

    case clearingCompletion(duration: Int, option: String, trigger: String, scope: String, source: String)
    case retriggerIn20s
    case userActionBeforeCompletion

    // MARK: - Tab Manager

    case burnTabsDuration(duration: Int, scope: String)
    case burnTabsHasResidue(scope: String)
    case burnTabsError(Error)

    // MARK: - URL Cache

    case burnURLCacheDuration(Int)
    case burnURLCacheHasResidue

    // MARK: - Website Data

    case burnWebsiteDataHasResidue(step: String, scope: String?)

    // MARK: - History

    case burnHistoryDuration(duration: Int, scope: String)
    case burnHistoryError(Error)

    // MARK: - AI Chat History

    case burnAIChatHistoryDuration(duration: Int, scope: String)
    case burnAIChatHistoryError(Error)
}

// MARK: - PixelKitEvent Protocol

extension DataClearingPixels: PixelKitEvent {

    var name: String {
        switch self {
        case .clearingCompletion:
            return "m_fire_clearing_completion"
        case .retriggerIn20s:
            return "m_fire_retrigger_in_20s"
        case .userActionBeforeCompletion:
            return "m_fire_user_action_before_completion"

        case .burnTabsDuration:
            return "m_fire_burn_tabs_duration"
        case .burnTabsHasResidue:
            return "m_fire_burn_tabs_has_residue"
        case .burnTabsError:
            return "m_fire_burn_tabs_error"

        case .burnURLCacheDuration:
            return "m_fire_burn_url_cache_duration"
        case .burnURLCacheHasResidue:
            return "m_fire_burn_url_cache_has_residue"

        case .burnWebsiteDataHasResidue:
            return "m_fire_burn_website_data_has_residue"

        case .burnHistoryDuration:
            return "m_fire_burn_history_duration"
        case .burnHistoryError:
            return "m_fire_burn_history_error"

        case .burnAIChatHistoryDuration:
            return "m_fire_burn_ai_chat_history_duration"
        case .burnAIChatHistoryError:
            return "m_fire_burn_ai_chat_history_error"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .clearingCompletion(let duration, let option, let trigger, let scope, let source):
            return [
                "duration": String(duration),
                "option": option,
                "trigger": trigger,
                "scope": scope,
                "source": source
            ]

        case .burnURLCacheDuration(let duration):
            return ["duration": String(duration)]
            
        case .burnTabsDuration(let duration, let scope),
             .burnHistoryDuration(let duration, let scope),
             .burnAIChatHistoryDuration(let duration, let scope):
            return ["duration": String(duration), "scope": scope]

        case .burnWebsiteDataHasResidue(let step, let scope):
            var params = ["step": step]
            if let scope {
                params["scope"] = scope
            }
            return params
            
        case .burnTabsHasResidue(let scope):
            return ["scope": scope]
            
        case .retriggerIn20s, .userActionBeforeCompletion,
             .burnURLCacheHasResidue,
             .burnTabsError, .burnHistoryError, .burnAIChatHistoryError:
            return nil
        }
    }

    var error: NSError? {
        switch self {
        case .burnTabsError(let error),
             .burnHistoryError(let error),
             .burnAIChatHistoryError(let error):
            return error as NSError
        default:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        return [.pixelSource]
    }
}
